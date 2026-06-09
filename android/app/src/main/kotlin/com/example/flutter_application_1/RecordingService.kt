package com.example.flutter_application_1

import android.app.*
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.*
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class RecordingService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var mediaRecorder: MediaRecorder? = null
    private var outputPath: String = ""

    companion object {
        const val CHANNEL_ID = "recording_channel"
        const val NOTIF_ID = 1001
        const val ACTION_START = "START_RECORDING"
        const val ACTION_STOP = "STOP_RECORDING"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
        const val EXTRA_WIDTH = "width"
        const val EXTRA_HEIGHT = "height"
        const val EXTRA_DPI = "dpi"
        const val EXTRA_AUDIO_SOURCE = "audio_source"
        const val EXTRA_OUTPUT_PATH = "output_path"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = buildNotification()
                startForeground(NOTIF_ID, notification)
                startRecording(intent)
            }
            ACTION_STOP -> {
                stopRecording()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun startRecording(intent: Intent) {
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        } ?: return

        val width = intent.getIntExtra(EXTRA_WIDTH, 1280)
        val height = intent.getIntExtra(EXTRA_HEIGHT, 720)
        val dpi = intent.getIntExtra(EXTRA_DPI, 320)
        val audioSource = intent.getStringExtra(EXTRA_AUDIO_SOURCE) ?: "mic"
        outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: getDefaultOutputPath()

        val projManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projManager.getMediaProjection(resultCode, resultData)

        try {
            setupMediaRecorder(width, height, dpi, audioSource)
        } catch (e: Exception) {
            stopSelf()
        }
    }

    private fun setupMediaRecorder(width: Int, height: Int, dpi: Int, audioSource: String) {
        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        val useAudio = when (audioSource) {
            "mic", "both" -> true
            "system" -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
            else -> false
        }

        mediaRecorder?.apply {
            if (useAudio) {
                val src = if (audioSource == "system" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    MediaRecorder.AudioSource.REMOTE_SUBMIX
                else
                    MediaRecorder.AudioSource.MIC
                try {
                    setAudioSource(src)
                } catch (e: Exception) { /* continuar sin audio */ }
            }

            setVideoSource(MediaRecorder.VideoSource.SURFACE)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)

            if (useAudio) {
                try {
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(128000)
                    setAudioSamplingRate(44100)
                } catch (e: Exception) { /* continuar sin audio */ }
            }

            setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            setVideoSize(width, height)
            setVideoFrameRate(30)
            setVideoEncodingBitRate(5 * 1000 * 1000)
            setOutputFile(outputPath)

            try {
                prepare()
            } catch (e: Exception) {
                throw RuntimeException("Error al preparar: ${e.message}")
            }
        }

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenRecorder",
            width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            mediaRecorder?.surface, null, null
        ) ?: throw RuntimeException("No se pudo crear VirtualDisplay")

        mediaRecorder?.start()
    }  // <-- cierre de setupMediaRecorder

    private fun stopRecording() {
        try {
            mediaRecorder?.stop()
        } catch (e: Exception) { /* ignorar si no hay datos */ }
        mediaRecorder?.release()
        mediaRecorder = null
        virtualDisplay?.release()
        virtualDisplay = null
        mediaProjection?.stop()
        mediaProjection = null

        if (outputPath.isNotEmpty()) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaScannerConnection.scanFile(
                        this, arrayOf(outputPath), arrayOf("video/mp4"), null
                    )
                } else {
                    @Suppress("DEPRECATION")
                    sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
                        data = android.net.Uri.fromFile(File(outputPath))
                    })
                }
            } catch (e: Exception) { /* ignorar */ }
        }
    }

    private fun getDefaultOutputPath(): String {
        val dir = File(getExternalFilesDir(null), "ScreenRecordings")
        if (!dir.exists()) dir.mkdirs()
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        return "${dir.absolutePath}/rec_$timestamp.mp4"
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Grabación de Pantalla",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Grabación en curso"
                setSound(null, null)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, RecordingService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔴 Grabando pantalla")
            .setContentText("Toca para abrir la app · Detener →")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(openIntent)
            .addAction(android.R.drawable.ic_media_pause, "Detener", stopIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    override fun onBind(intent: Intent?) = null
}