package ph.dewdew.imprenta

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.URL

// Joins the printer's WiFi Direct hotspot (route A in PLAN.md) and binds app traffic to it.
class MainActivity : FlutterActivity() {
    private val cm by lazy { getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager }
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var network: Network? = null
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "imprenta/wifi").setMethodCallHandler { call, result ->
            when (call.method) {
                "connectToPrinter" -> connect(call.argument<String>("ssid")!!, call.argument<String>("passphrase") ?: "", result)
                "disconnect" -> { disconnect(); result.success(null) }
                "getNetworkInfo" -> result.success(info())
                "post" -> post(call.argument<String>("url")!!, call.argument<ByteArray>("body")!!, result)
                else -> result.notImplemented()
            }
        }
        files = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "imprenta/files").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> {
                        // Double tap: answer the earlier call so its caller doesn't hang forever.
                        pickResult?.success(null)
                        pickResult = result
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/pdf", "image/jpeg", "image/png"))
                        }, PICK)
                    }
                    // A shared file may still be loading in the background: answer once it's read.
                    "takeShared" -> {
                        dartAsked = true
                        if (sharedLoading) sharedWaiter = result else { result.success(shared); shared = null }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        loadShared(intent)
    }

    // --- Files: picker and "Share → Imprenta" ---
    private var files: MethodChannel? = null
    private var pickResult: MethodChannel.Result? = null
    private var shared: Map<String, Any?>? = null
    private var sharedLoading = false
    private var dartAsked = false
    private var sharedWaiter: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK) return
        val r = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { r.success(null); return }
        Thread { val f = runCatching { readUri(uri) }; main.post { f.fold({ r.success(it) }, { r.error("READ", it.message, null) }) } }.start()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        loadShared(intent)
    }

    // Reads a shared file off the main thread (big PDFs would freeze the app), then hands it to Dart.
    private fun loadShared(i: Intent?) {
        val uri = sharedUri(i) ?: return
        setIntent(Intent()) // handled: don't re-open this file if Android recreates the activity
        sharedLoading = true
        Thread {
            val f = runCatching { readUri(uri) }.getOrNull()
            main.post {
                sharedLoading = false
                val w = sharedWaiter
                sharedWaiter = null
                when {
                    w != null -> w.success(f)
                    // Dart already took its startup file, so push this one (app was open); else keep it for takeShared.
                    f != null && dartAsked -> files?.invokeMethod("shared", f)
                    else -> shared = f
                }
            }
        }.start()
    }

    private fun sharedUri(i: Intent?): Uri? {
        val uri: Uri? = when (i?.action) {
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") i.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> i.data
            else -> null
        }
        return uri
    }

    private fun readUri(uri: Uri): Map<String, Any?> {
        var name = "document"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) name = it.getString(0) ?: name
        }
        val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
        return mapOf("name" to name, "mime" to (contentResolver.getType(uri) ?: ""), "bytes" to bytes)
    }

    private fun connect(ssid: String, passphrase: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "Android 10+ needed to join the printer network from the app", null)
            return
        }
        disconnect()
        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
            if (passphrase.isNotEmpty()) setWpa2Passphrase(passphrase)
        }.build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()
        var replied = false
        fun reply(block: () -> Unit) = main.post { if (!replied) { replied = true; block() } }
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                network = n
                cm.bindProcessToNetwork(n)
                // LinkProperties can arrive a moment after onAvailable; give it a beat.
                main.postDelayed({ reply { result.success(info()) } }, 500)
            }
            override fun onUnavailable() {
                reply { result.error("UNAVAILABLE", "Could not join $ssid (cancelled, wrong password, or out of range)", null) }
            }
            override fun onLost(n: Network) {
                if (n == network) { cm.bindProcessToNetwork(null); network = null }
            }
        }
        callback = cb
        cm.requestNetwork(request, cb)
    }

    // Dart sockets didn't follow bindProcessToNetwork on a real phone, so IPP goes through the joined Network here.
    private fun post(url: String, body: ByteArray, result: MethodChannel.Result) {
        Thread {
            try {
                val u = URL(url)
                // A WiFi joined outside the app (no internet) isn't the default network, so pick it explicitly.
                val net = network ?: cm.allNetworks.firstOrNull {
                    cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                }
                val c = (net?.openConnection(u) ?: u.openConnection()) as HttpURLConnection
                c.connectTimeout = 8000
                c.readTimeout = 180000 // printers may answer Print-Job only after taking in the whole job
                c.doOutput = true
                c.requestMethod = "POST"
                c.setRequestProperty("Content-Type", "application/ipp")
                c.setFixedLengthStreamingMode(body.size)
                c.outputStream.use { it.write(body) }
                val code = c.responseCode
                val bytes = (if (code < 400) c.inputStream else c.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
                c.disconnect()
                main.post { if (code == 200) result.success(bytes) else result.error("HTTP", "HTTP $code from printer", null) }
            } catch (e: Exception) {
                main.post { result.error("NETWORK", "${e.javaClass.simpleName}: ${e.message}", null) }
            }
        }.start()
    }

    private fun disconnect() {
        cm.bindProcessToNetwork(null)
        callback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        callback = null
        network = null
    }

    private fun info(): Map<String, Any?> {
        val lp = network?.let { cm.getLinkProperties(it) }
        val gateway = lp?.routes?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }?.gateway?.hostAddress
        val ip = lp?.linkAddresses?.firstOrNull { it.address is Inet4Address }?.address?.hostAddress
        return mapOf("connected" to (network != null), "gateway" to gateway, "phoneIp" to ip)
    }

    override fun onDestroy() { disconnect(); super.onDestroy() }

    companion object { private const val PICK = 4711 }
}
