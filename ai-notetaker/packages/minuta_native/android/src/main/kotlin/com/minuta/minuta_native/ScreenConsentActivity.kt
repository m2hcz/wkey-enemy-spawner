package com.minuta.minuta_native

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle

/** Invisible activity that shows the system "start recording the screen?" dialog. */
class ScreenConsentActivity : Activity() {
    private var answered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST) return
        answered = true
        if (resultCode == RESULT_OK && data != null) {
            // The service reports the final answer once the projection is live.
            val intent = Intent(this, ScreenCaptureService::class.java)
                .putExtra(ScreenCaptureService.EXTRA_CODE, resultCode)
                .putExtra(ScreenCaptureService.EXTRA_DATA, data)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            } catch (e: Exception) {
                MinutaNativePlugin.deliverConsent(false)
            }
        } else {
            MinutaNativePlugin.deliverConsent(false)
        }
        finish()
    }

    override fun onDestroy() {
        if (!answered && isFinishing) MinutaNativePlugin.deliverConsent(false)
        super.onDestroy()
    }

    companion object {
        private const val REQUEST = 4021
    }
}
