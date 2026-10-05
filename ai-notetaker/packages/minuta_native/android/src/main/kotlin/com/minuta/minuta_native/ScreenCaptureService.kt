package com.minuta.minuta_native

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Holds a MediaProjection mirror of the screen and keeps the newest frame so a
 * screenshot can be taken at any moment, even while the screen is static.
 */
class ScreenCaptureService : Service() {
    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        private const val CHANNEL = "minuta_screen"
        private const val NOTIFICATION_ID = 7342

        @Volatile
        var instance: ScreenCaptureService? = null
    }

    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private val lock = Any()
    private var latest: Image? = null

    @Volatile
    var isReady = false
        private set

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must be in the foreground before asking for the projection (Android 14+).
        startInForeground()
        if (isReady) {
            MinutaNativePlugin.deliverConsent(true)
            return START_NOT_STICKY
        }
        val code = intent?.getIntExtra(EXTRA_CODE, 0) ?: 0
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_DATA)
        }
        if (data == null) {
            MinutaNativePlugin.deliverConsent(false)
            shutdown()
            return START_NOT_STICKY
        }
        try {
            start(code, data)
            instance = this
            isReady = true
            MinutaNativePlugin.deliverConsent(true)
        } catch (e: Exception) {
            MinutaNativePlugin.deliverConsent(false)
            shutdown()
        }
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Leitura da tela", NotificationManager.IMPORTANCE_LOW)
            )
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("Assistente pode ver a tela")
            .setContentText("Usado só quando você toca em \"Analisar tela\".")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun start(code: Int, data: Intent) {
        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val proj = mpm.getMediaProjection(code, data) ?: throw IllegalStateException("No projection")
        val t = HandlerThread("minuta-capture").also { it.start() }
        val handler = Handler(t.looper)
        thread = t
        projection = proj
        // Android 14 requires the callback before creating the virtual display.
        proj.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                shutdown()
            }
        }, handler)

        val metrics = resources.displayMetrics
        val w0 = metrics.widthPixels
        val h0 = metrics.heightPixels
        val scale = minOf(1f, 1600f / max(w0, h0))
        val w = (w0 * scale).roundToInt().coerceAtLeast(2)
        val h = (h0 * scale).roundToInt().coerceAtLeast(2)

        val r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 3)
        r.setOnImageAvailableListener({ ir ->
            val img = try {
                ir.acquireLatestImage()
            } catch (e: Exception) {
                null
            } ?: return@setOnImageAvailableListener
            synchronized(lock) {
                latest?.close()
                latest = img
            }
        }, handler)
        reader = r
        display = proj.createVirtualDisplay(
            "minuta-screen", w, h, metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, handler
        )
    }

    /** JPEG of the most recent frame, scaled so its longest side is [maxSide]. */
    fun captureJpeg(maxSide: Int): ByteArray? {
        val bitmap = synchronized(lock) {
            val img = latest ?: return null
            val plane = img.planes[0]
            val buffer = plane.buffer
            buffer.rewind()
            val pixelStride = plane.pixelStride
            val rowPadding = plane.rowStride - pixelStride * img.width
            val padded = Bitmap.createBitmap(
                img.width + rowPadding / pixelStride, img.height, Bitmap.Config.ARGB_8888
            )
            padded.copyPixelsFromBuffer(buffer)
            buffer.rewind()
            if (rowPadding == 0) padded else Bitmap.createBitmap(padded, 0, 0, img.width, img.height)
        }
        val longest = max(bitmap.width, bitmap.height)
        val out = if (longest > maxSide) {
            val s = maxSide.toFloat() / longest
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * s).roundToInt(), (bitmap.height * s).roundToInt(), true)
        } else {
            bitmap
        }
        val stream = ByteArrayOutputStream()
        out.compress(Bitmap.CompressFormat.JPEG, 82, stream)
        return stream.toByteArray()
    }

    fun shutdown() {
        isReady = false
        instance = null
        synchronized(lock) {
            latest?.close()
            latest = null
        }
        try { display?.release() } catch (_: Exception) {}
        display = null
        try { reader?.close() } catch (_: Exception) {}
        reader = null
        val p = projection
        projection = null
        try { p?.stop() } catch (_: Exception) {}
        thread?.quitSafely()
        thread = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        if (isReady || projection != null) shutdown()
        super.onDestroy()
    }
}
