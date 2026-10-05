package com.minuta.minuta_native

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

/**
 * Registered on every Flutter engine of the app (the main UI and the floating
 * overlay), so it doubles as a message bus between them.
 */
class MinutaNativePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    companion object {
        private val instances = mutableSetOf<MinutaNativePlugin>()
        private val main = Handler(Looper.getMainLooper())
        private val worker = Executors.newSingleThreadExecutor()
        private var pendingConsent: Result? = null

        /** Called once the user answered the screen-capture consent dialog. */
        fun deliverConsent(granted: Boolean) {
            main.post {
                pendingConsent?.success(granted)
                pendingConsent = null
            }
        }
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "minuta_native")
        channel.setMethodCallHandler(this)
        synchronized(instances) { instances.add(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        synchronized(instances) { instances.remove(this) }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "broadcast" -> {
                val others = synchronized(instances) { instances.filter { it !== this } }
                for (p in others) p.channel.invokeMethod("onMessage", call.arguments)
                result.success(null)
            }
            "isScreenCaptureActive" -> result.success(ScreenCaptureService.instance?.isReady == true)
            "requestScreenCapture" -> {
                if (ScreenCaptureService.instance?.isReady == true) {
                    result.success(true)
                    return
                }
                if (pendingConsent != null) {
                    result.error("BUSY", "A consent request is already open", null)
                    return
                }
                pendingConsent = result
                try {
                    val intent = Intent(context, ScreenConsentActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                } catch (e: Exception) {
                    pendingConsent = null
                    result.error("CONSENT", e.message, null)
                }
            }
            "captureScreen" -> {
                val maxSide = call.argument<Int>("maxSide") ?: 1280
                val service = ScreenCaptureService.instance
                if (service == null) {
                    result.success(null)
                    return
                }
                worker.execute {
                    val bytes = try {
                        service.captureJpeg(maxSide)
                    } catch (e: Exception) {
                        null
                    }
                    main.post { result.success(bytes) }
                }
            }
            "stopScreenCapture" -> {
                ScreenCaptureService.instance?.shutdown()
                result.success(null)
            }
            "moveTaskToBack" -> {
                activity?.moveTaskToBack(true)
                result.success(activity != null)
            }
            "openApp" -> {
                val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                if (intent != null) context.startActivity(intent)
                result.success(intent != null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
