package com.example.flutter_application_1

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "screen_recorder"
    private val REQUEST_MEDIA_PROJECTION = 1001
    private val REQUEST_OVERLAY = 1002
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMediaProjection" -> {
                    pendingResult = result
                    val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                }
                "startRecording" -> {
                    val width = call.argument<Int>("width") ?: 1280
                    val height = call.argument<Int>("height") ?: 720
                    val dpi = call.argument<Int>("dpi") ?: 320
                    val audioSource = call.argument<String>("audioSource") ?: "mic"
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    startRecordingService(width, height, dpi, audioSource, outputPath)
                    result.success(true)
                }
                "stopRecording" -> {
                    val intent = Intent(this, RecordingService::class.java).apply {
                        action = RecordingService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "checkOverlayPermission" -> {
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            Settings.canDrawOverlays(this)
                        else true
                    )
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        pendingResult = result
                        startActivityForResult(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")),
                            REQUEST_OVERLAY
                        )
                    } else result.success(true)
                }
                "getScreenMetrics" -> {
                    val metrics = resources.displayMetrics
                    result.success(mapOf(
                        "width" to metrics.widthPixels,
                        "height" to metrics.heightPixels,
                        "density" to metrics.densityDpi
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    // Guardamos el intent de MediaProjection para pasarlo al servicio
    private var projectionResultCode: Int = Activity.RESULT_CANCELED
    private var projectionResultData: Intent? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_MEDIA_PROJECTION -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    projectionResultCode = resultCode
                    projectionResultData = data
                    pendingResult?.success(mapOf("resultCode" to resultCode, "granted" to true))
                } else {
                    pendingResult?.success(mapOf("granted" to false))
                }
                pendingResult = null
            }
            REQUEST_OVERLAY -> {
                val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    Settings.canDrawOverlays(this) else true
                pendingResult?.success(granted)
                pendingResult = null
            }
        }
    }

    fun startRecordingService(width: Int, height: Int, dpi: Int, audioSource: String, outputPath: String) {
        val intent = Intent(this, RecordingService::class.java).apply {
            action = RecordingService.ACTION_START
            putExtra(RecordingService.EXTRA_RESULT_CODE, projectionResultCode)
            putExtra(RecordingService.EXTRA_RESULT_DATA, projectionResultData)
            putExtra(RecordingService.EXTRA_WIDTH, width)
            putExtra(RecordingService.EXTRA_HEIGHT, height)
            putExtra(RecordingService.EXTRA_DPI, dpi)
            putExtra(RecordingService.EXTRA_AUDIO_SOURCE, audioSource)
            putExtra(RecordingService.EXTRA_OUTPUT_PATH, outputPath)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}