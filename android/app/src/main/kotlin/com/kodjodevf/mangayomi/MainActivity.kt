package com.kodjodevf.mangayomi

import androidx.annotation.NonNull
import libmtorrentserver.Libmtorrentserver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.embedding.android.FlutterFragmentActivity
import androidx.core.content.FileProvider
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.net.Uri
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import java.io.File

class MainActivity: FlutterFragmentActivity() {

    private var splashContainer: View? = null
    private var splashPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // TV-only native splash: play a short branded clip over the Flutter view
        // while the engine and first frame come up, covering the startup hang.
        // It renders on the platform's own video surface, so it animates smoothly
        // even while the Dart isolate is busy initialising (a Flutter-drawn video
        // would stutter with it). Plays to the end, then reveals the app. Phones
        // start fast enough not to need it, so it is gated to TV.
        if (savedInstanceState == null && isTvDevice()) {
            showSplashVideo()
        }
    }

    private fun showSplashVideo() {
        val container = FrameLayout(this)
        // White backing matches the launch theme and the clip's own background,
        // so there is no black flash before the first video frame.
        container.setBackgroundColor(Color.WHITE)
        val textureView = TextureView(this)
        container.addView(
            textureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        addContentView(
            container,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        splashContainer = container

        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                val mp = MediaPlayer.create(this@MainActivity, R.raw.startup_video)
                if (mp == null) {
                    removeSplashVideo()
                    return
                }
                splashPlayer = mp
                mp.setSurface(Surface(surface))
                mp.setOnCompletionListener { removeSplashVideo() }
                mp.setOnErrorListener { _, _, _ ->
                    removeSplashVideo()
                    true
                }
                try {
                    mp.start()
                } catch (e: Exception) {
                    removeSplashVideo()
                }
            }

            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {}
            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true
            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
        }

        // Safety net: never let a stalled decode trap the app behind the splash.
        Handler(mainLooper).postDelayed({ removeSplashVideo() }, 10000)
    }

    private fun removeSplashVideo() {
        splashPlayer?.let {
            try {
                it.release()
            } catch (e: Exception) {
            }
        }
        splashPlayer = null
        splashContainer?.let { c ->
            (c.parent as? ViewGroup)?.removeView(c)
        }
        splashContainer = null
    }

    override fun onDestroy() {
        removeSplashVideo()
        super.onDestroy()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.kodjodevf.mangayomi.libmtorrentserver",
            StandardMethodCodec.INSTANCE,
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val config = call.argument<String>("config")
                    try {
                        val port = Libmtorrentserver.start(config)
                        result.success(port)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.kodjodevf.mangayomi.apk_install",
            StandardMethodCodec.INSTANCE,
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    installApk(filePath)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.kodjodevf.mangayomi.device",
            StandardMethodCodec.INSTANCE
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> {
                    result.success(isTvDevice())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // Reports whether this is an Android TV / leanback device. Used by the
    // Dart side to branch the UI on form factor (see #729). Kept conservative
    // so a phone is never misdetected as a TV: a phone has neither the
    // television UI mode nor the leanback feature.
    private fun isTvDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private fun installApk(filePath: String?) {
        if (filePath == null) return
        val file = File(filePath)
        val intent = Intent(Intent.ACTION_VIEW)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            intent.flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } else {
            Uri.fromFile(file)
        }
        intent.setDataAndType(apkUri, "application/vnd.android.package-archive")
        startActivity(intent)
    }
}
