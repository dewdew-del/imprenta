// Minimal IPP/1.1 (RFC 8010) encoder/decoder. Written by hand so we control every attribute.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class Tag {
  static const operation = 0x01, job = 0x02, end = 0x03, printer = 0x04, unsupportedGroup = 0x05;
  static const unsupported = 0x10, unknown = 0x12, noValue = 0x13;
  static const integer = 0x21, boolean = 0x22, enumeration = 0x23;
  static const octetString = 0x30, dateTime = 0x31, resolution = 0x32, range = 0x33;
  static const begCollection = 0x34, endCollection = 0x37, memberName = 0x4A;
  static const text = 0x41, name = 0x42, keyword = 0x44, uri = 0x45;
  static const charset = 0x47, language = 0x48, mimeType = 0x49;
}

class Op {
  static const printJob = 0x0002, cancelJob = 0x0008, getJobAttributes = 0x0009, getJobs = 0x000A, getPrinterAttributes = 0x000B;
}

/// A collection value (e.g. media-col). Use with tag [Tag.begCollection].
class IppCol {
  final List<IppAttr> members;
  IppCol(this.members);
}

/// One attribute to send. Values are int (integer/enum), bool, String or [IppCol].
class IppAttr {
  final int tag;
  final String name;
  final List<Object> values;
  IppAttr(this.tag, this.name, this.values);
}

class IppResolution {
  final int x, y, units; // units: 3 = dpi, 4 = dpcm
  IppResolution(this.x, this.y, this.units);
  @override
  String toString() => '${x}x$y${units == 3 ? 'dpi' : 'dpcm'}';
}

class IppRange {
  final int low, high;
  IppRange(this.low, this.high);
  @override
  String toString() => '$low-$high';
}

Uint8List encodeRequest(int op, int requestId, Map<int, List<IppAttr>> groups, {List<int>? document}) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v >> 8 & 0xff, v & 0xff]);
  void u32(int v) => b.add([v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff]);
  b.add([1, 1]); // version 1.1: accepted by every IPP printer
  u16(op);
  u32(requestId);
  void raw(int tag, List<int> name, List<int> value) {
    b.addByte(tag);
    u16(name.length);
    b.add(name);
    u16(value.length);
    b.add(value);
  }

  // Members of a collection carry their name in a memberAttrName value, never in the name field.
  void attr(IppAttr a, {bool member = false}) {
    if (member) raw(Tag.memberName, const [], utf8.encode(a.name));
    for (var i = 0; i < a.values.length; i++) {
      final v = a.values[i];
      final name = member || i > 0 ? const <int>[] : utf8.encode(a.name);
      if (v is IppCol) {
        raw(Tag.begCollection, name, const []);
        for (final m in v.members) {
          attr(m, member: true);
        }
        raw(Tag.endCollection, const [], const []);
        continue;
      }
      raw(a.tag, name, switch (v) {
        int n => Uint8List(4)..buffer.asByteData().setInt32(0, n),
        bool x => [x ? 1 : 0],
        String s => utf8.encode(s),
        _ => throw ArgumentError('Unsupported value $v'),
      });
    }
  }

  groups.forEach((groupTag, attrs) {
    b.addByte(groupTag);
    for (final a in attrs) {
      attr(a);
    }
  });
  b.addByte(Tag.end);
  if (document != null) b.add(document);
  return b.toBytes();
}

class IppResponse {
  final int version, status, requestId;
  /// Each group: (group tag, attributes name -> values).
  final List<(int, Map<String, List<Object?>>)> groups;
  IppResponse(this.version, this.status, this.requestId, this.groups);

  bool get ok => status < 0x0100;
  Map<String, List<Object?>> group(int tag) =>
      groups.firstWhere((g) => g.$1 == tag, orElse: () => (tag, {})).$2;
}

IppResponse decodeResponse(Uint8List data) {
  final d = ByteData.sublistView(data);
  var p = 0;
  int u8() => d.getUint8(p++);
  int u16() { final v = d.getUint16(p); p += 2; return v; }
  Uint8List take(int n) { final s = data.sublist(p, p + n); p += n; return s; }

  final version = u16();
  final status = u16();
  final requestId = d.getUint32(p);
  p += 4;

  Object? value(int tag, Uint8List v) {
    final vd = ByteData.sublistView(v);
    return switch (tag) {
      Tag.integer || Tag.enumeration => vd.getInt32(0),
      Tag.boolean => v[0] != 0,
      Tag.resolution => IppResolution(vd.getInt32(0), vd.getInt32(4), v[8]),
      Tag.range => IppRange(vd.getInt32(0), vd.getInt32(4)),
      Tag.unsupported || Tag.unknown || Tag.noValue => null,
      Tag.octetString || Tag.dateTime => v,
      _ => utf8.decode(v, allowMalformed: true),
    };
  }

  // Reads members until endCollection; returns them as a map. Caller already consumed begCollection.
  Map<String, List<Object?>> collection() {
    final members = <String, List<Object?>>{};
    String? member;
    while (true) {
      final tag = u8();
      take(u16()); // name is always empty inside collections
      final v = take(u16());
      if (tag == Tag.endCollection) return members;
      if (tag == Tag.memberName) {
        member = utf8.decode(v);
        members[member] = [];
      } else if (tag == Tag.begCollection) {
        members[member!]!.add(collection());
      } else {
        members[member!]!.add(value(tag, v));
      }
    }
  }

  final groups = <(int, Map<String, List<Object?>>)>[];
  Map<String, List<Object?>>? current;
  String? last;
  while (p < data.length) {
    final tag = u8();
    if (tag == Tag.end) break;
    if (tag < 0x10) {
      current = {};
      groups.add((tag, current));
      continue;
    }
    final name = utf8.decode(take(u16()));
    final v = take(u16());
    if (name.isNotEmpty) {
      last = name;
      current![name] = [];
    }
    current![last]!.add(tag == Tag.begCollection ? collection() : value(tag, v));
  }
  return IppResponse(version, status, requestId, groups);
}

/// Sends one IPP request over HTTP (port 631) and decodes the reply.
class IppClient {
  final String host;
  final String path;
  int _id = 1;
  IppClient(this.host, {this.path = '/ipp/print'});

  String get printerUri => 'ipp://$host:631$path';

  List<IppAttr> _opAttrs() => [
        IppAttr(Tag.charset, 'attributes-charset', ['utf-8']),
        IppAttr(Tag.language, 'attributes-natural-language', ['en']),
        IppAttr(Tag.uri, 'printer-uri', [printerUri]),
        IppAttr(Tag.name, 'requesting-user-name', ['imprenta']),
      ];

  Future<IppResponse> send(int op, {List<IppAttr> extra = const [], Map<int, List<IppAttr>> more = const {}, List<int>? document}) async {
    final body = encodeRequest(op, _id++, {Tag.operation: [..._opAttrs(), ...extra], ...more}, document: document);
    // Sent by Kotlin so it goes out over the joined printer network (see MainActivity.post).
    final bytes = await _channel.invokeMethod<Uint8List>('post', {'url': 'http://$host:631$path', 'body': body});
    return decodeResponse(bytes!);
  }

  static const _channel = MethodChannel('imprenta/wifi');

  Future<IppResponse> getPrinterAttributes([List<String> which = const ['all', 'media-col-database']]) =>
      send(Op.getPrinterAttributes, extra: [IppAttr(Tag.keyword, 'requested-attributes', which)]);

  /// Sends a document; returns the printer's job-id. Throws [IppException] if the printer refuses.
  Future<int> printJob(Uint8List doc, {required String format, required List<IppAttr> jobAttrs, String name = 'Imprenta'}) async {
    final r = _check(await send(Op.printJob,
        extra: [IppAttr(Tag.name, 'job-name', [name]), IppAttr(Tag.mimeType, 'document-format', [format])],
        more: {Tag.job: jobAttrs},
        document: doc));
    return r.group(Tag.job)['job-id']!.first as int;
  }

  Future<Map<String, List<Object?>>> jobStatus(int jobId) async => _check(await send(Op.getJobAttributes, extra: [
        IppAttr(Tag.integer, 'job-id', [jobId]),
        IppAttr(Tag.keyword, 'requested-attributes', ['job-state', 'job-state-reasons', 'job-impressions-completed']),
      ])).group(Tag.job);

  /// IDs of this app's unfinished jobs (requesting-user-name "imprenta"), never other people's.
  Future<List<int>> myActiveJobs() async {
    final r = _check(await send(Op.getJobs, extra: [
      IppAttr(Tag.keyword, 'which-jobs', ['not-completed']),
      IppAttr(Tag.boolean, 'my-jobs', [true]),
      IppAttr(Tag.keyword, 'requested-attributes', ['job-id', 'job-originating-user-name']),
    ]));
    return [
      for (final g in r.groups)
        if (g.$1 == Tag.job && g.$2['job-originating-user-name']?.first == 'imprenta') g.$2['job-id']!.first as int,
    ];
  }

  Future<void> cancelJob(int jobId) async => _check(await send(Op.cancelJob, extra: [IppAttr(Tag.integer, 'job-id', [jobId])]));

  IppResponse _check(IppResponse r) {
    if (r.ok) return r;
    final msg = r.group(Tag.operation)['status-message']?.first;
    throw IppException(r.status, r.group(Tag.unsupportedGroup).keys.toList(), msg as String?);
  }
}

class IppException implements Exception {
  final int status;
  final List<String> unsupported;
  final String? message;
  IppException(this.status, this.unsupported, this.message);
  @override
  String toString() => 'Printer refused (0x${status.toRadixString(16).padLeft(4, '0')})'
      '${message != null ? ': $message' : ''}${unsupported.isNotEmpty ? ' · unsupported: ${unsupported.join(', ')}' : ''}';
}

/// Job attributes that set the exact paper: the PWG keyword when there is one, else media-col with the size.
List<IppAttr> mediaAttrs(String? pwg, int width, int height) => pwg != null
    ? [IppAttr(Tag.keyword, 'media', [pwg])]
    : [
        IppAttr(Tag.begCollection, 'media-col', [
          IppCol([
            IppAttr(Tag.begCollection, 'media-size', [
              IppCol([IppAttr(Tag.integer, 'x-dimension', [width]), IppAttr(Tag.integer, 'y-dimension', [height])]),
            ]),
          ]),
        ]),
      ];
