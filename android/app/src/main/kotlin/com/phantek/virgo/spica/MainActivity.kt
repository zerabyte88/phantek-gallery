package com.phantek.virgo.spica

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/install"
        ).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("INVALID_PATH", "APK path is null", null)
                    return@setMethodCallHandler
                }
                try {
                    installApk(path)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/share"
        ).setMethodCallHandler { call, result ->
            if (call.method == "shareFiles") {
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                try {
                    shareFiles(paths, mimeType)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SHARE_FAILED", e.message, null)
                }
            } else if (call.method == "setAsWallpaper") {
                val path = call.argument<String>("path")
                val mimeType = call.argument<String>("mimeType") ?: "image/*"
                if (path == null) {
                    result.error("INVALID_PATH", "Path is null", null)
                    return@setMethodCallHandler
                }
                try {
                    setAsWallpaper(path, mimeType)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("WALLPAPER_FAILED", e.message, null)
                }
            } else if (call.method == "scanFile") {
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                try {
                    android.media.MediaScannerConnection.scanFile(
                        applicationContext,
                        paths.toTypedArray(),
                        null,
                        null
                    )
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SCAN_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        val executor = java.util.concurrent.Executors.newFixedThreadPool(2) // HW decoder instances are scarce; 4 parallel 1080p+/HEVC retrievers fail

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/thumbnail"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getVideoThumbnail") {
                val path = call.argument<String>("path")
                val size = call.argument<Int>("size") ?: 384
                if (path == null) {
                    result.error("INVALID_PATH", "Path is null", null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    try {
                        val bytes = extractVideoThumbnail(path, size)
                        runOnUiThread {
                            result.success(bytes)
                        }
                    } catch (e: Throwable) {
                        runOnUiThread {
                            result.success(null)
                        }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun extractVideoThumbnail(path: String, targetSize: Int): ByteArray? {
        val file = File(path)
        if (!file.exists() || !file.canRead()) return null

        var bitmap: android.graphics.Bitmap? = null

        // 1. Android Q+ (API 29+) MediaStore contentResolver.loadThumbnail
        // Fast system-level cache that handles 4K, 2K, 1080p, HEVC, VP9, and all MediaStore indexed formats
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val projection = arrayOf(
                    android.provider.MediaStore.Video.Media._ID,
                    android.provider.MediaStore.Video.Media.WIDTH,
                    android.provider.MediaStore.Video.Media.HEIGHT
                )
                val cursor = contentResolver.query(
                    android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    "${android.provider.MediaStore.Video.Media.DATA} = ?",
                    arrayOf(path),
                    null
                )
                cursor?.use {
                    if (it.moveToFirst()) {
                        val id = it.getLong(it.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media._ID))
                        val wIdx = it.getColumnIndex(android.provider.MediaStore.Video.Media.WIDTH)
                        val hIdx = it.getColumnIndex(android.provider.MediaStore.Video.Media.HEIGHT)
                        val mW = if (wIdx >= 0) it.getInt(wIdx) else 0
                        val mH = if (hIdx >= 0) it.getInt(hIdx) else 0

                        val reqSize = if (mW > 0 && mH > 0) {
                            val maxDim = mW.coerceAtLeast(mH)
                            val scale = if (maxDim > targetSize) targetSize.toFloat() / maxDim.toFloat() else 1f
                            val w = (((mW * scale).toInt() / 2) * 2).coerceAtLeast(2)
                            val h = (((mH * scale).toInt() / 2) * 2).coerceAtLeast(2)
                            android.util.Size(w, h)
                        } else {
                            android.util.Size(targetSize, targetSize)
                        }

                        val uri = android.content.ContentUris.withAppendedId(
                            android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            id
                        )
                        bitmap = contentResolver.loadThumbnail(uri, reqSize, null)
                    }
                }
            } catch (_: Throwable) {}
        }

        // 2. Direct MediaMetadataRetriever (handles MKV, WebM, MOV, MP4, 3GP, H.265/HEVC, VP9, H.264, 2K/4K)
        if (bitmap == null) {
            val retriever = android.media.MediaMetadataRetriever()
            var fis: java.io.FileInputStream? = null
            try {
                try {
                    fis = java.io.FileInputStream(file)
                    retriever.setDataSource(fis.fd)
                } catch (_: Throwable) {
                    retriever.setDataSource(path)
                }

                // Extract video dimensions and orientation
                val widthStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                val heightStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                val rotationStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                val origW = widthStr?.toIntOrNull() ?: 0
                val origH = heightStr?.toIntOrNull() ?: 0
                val rotation = rotationStr?.toIntOrNull() ?: 0

                // Proportional dimensions strictly matching original aspect ratio (never stretched into square)
                val (dstW, dstH) = if (origW > 0 && origH > 0) {
                    val maxDim = origW.coerceAtLeast(origH)
                    val scale = if (maxDim > targetSize) targetSize.toFloat() / maxDim.toFloat() else 1f
                    val w = ((origW * scale).toInt() / 2) * 2
                    val h = ((origH * scale).toInt() / 2) * 2
                    Pair(w.coerceAtLeast(2), h.coerceAtLeast(2))
                } else {
                    Pair(targetSize, targetSize)
                }

                // Enforce OPTION_CLOSEST_SYNC (sync/keyframes only) to prevent decoder hangs on H.265/HEVC
                val opt = android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                // Try time 0 first (first keyframe), then 1s, 0.5s, -1s
                val timePoints = longArrayOf(0L, 1000000L, 500000L, -1L)

                // 3a. Hardware/native scaled frame decoding with pre-downsampled bounds (Android O_MR1+)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    for (t in timePoints) {
                        try {
                            bitmap = retriever.getScaledFrameAtTime(t, opt, dstW, dstH)
                            if (bitmap != null) break
                        } catch (_: Throwable) {}
                    }
                }

                // 3b. Scaled frame with RGB_565 (50% less RAM) for Android R+ (API 30+)
                if (bitmap == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        val params = android.media.MediaMetadataRetriever.BitmapParams()
                        params.preferredConfig = android.graphics.Bitmap.Config.RGB_565
                        for (t in timePoints) {
                            try {
                                bitmap = retriever.getScaledFrameAtTime(t, opt, dstW, dstH, params)
                                if (bitmap != null) break
                            } catch (_: Throwable) {}
                        }
                    } catch (_: Throwable) {}
                }

                // 3c. Fallback: RGB_565 unscaled (Android P+) - sync frame only
                if (bitmap == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    try {
                        val params = android.media.MediaMetadataRetriever.BitmapParams()
                        params.preferredConfig = android.graphics.Bitmap.Config.RGB_565
                        for (t in timePoints) {
                            try {
                                bitmap = retriever.getFrameAtTime(t, opt, params)
                                if (bitmap != null) break
                            } catch (_: Throwable) {}
                        }
                    } catch (_: Throwable) {}
                }

                // 3d. Fallback: standard getFrameAtTime with sync option
                if (bitmap == null) {
                    for (t in timePoints) {
                        try {
                            bitmap = retriever.getFrameAtTime(t, opt)
                            if (bitmap != null) break
                        } catch (_: Throwable) {}
                    }
                }

                // Handle camera/recorded video rotation (90, 180, 270)
                if (bitmap != null && rotation != 0) {
                    try {
                        val matrix = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }
                        val rotated = android.graphics.Bitmap.createBitmap(
                            bitmap!!, 0, 0, bitmap!!.width, bitmap!!.height, matrix, true
                        )
                        if (rotated != bitmap) {
                            bitmap?.recycle()
                            bitmap = rotated
                        }
                    } catch (_: Throwable) {}
                }
            } catch (_: Throwable) {
            } finally {
                try { retriever.release() } catch (_: Throwable) {}
                try { fis?.close() } catch (_: Throwable) {}
            }
        }

        // 3. Legacy ThumbnailUtils fallback (API < 29)
        if (bitmap == null) {
            try {
                bitmap = android.media.ThumbnailUtils.createVideoThumbnail(
                    path,
                    android.provider.MediaStore.Images.Thumbnails.MINI_KIND
                )
            } catch (_: Throwable) {}
        }

        if (bitmap == null) return null

        // Scale down if larger than targetSize and recycle original bitmap to save memory
        val scaled = if (bitmap!!.width > targetSize || bitmap!!.height > targetSize) {
            val ratio = bitmap!!.width.toFloat() / bitmap!!.height.toFloat()
            val w = if (ratio >= 1f) targetSize else (targetSize * ratio).toInt().coerceAtLeast(1)
            val h = if (ratio >= 1f) (targetSize / ratio).toInt().coerceAtLeast(1) else targetSize
            val sc = android.graphics.Bitmap.createScaledBitmap(bitmap!!, w, h, true)
            if (sc != bitmap) {
                bitmap?.recycle()
            }
            sc
        } else {
            bitmap!!
        }

        val bos = java.io.ByteArrayOutputStream()
        scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, bos)
        scaled.recycle()
        val resultBytes = bos.toByteArray()
        return if (resultBytes.isNotEmpty()) resultBytes else null
    }

    private fun installApk(apkPath: String) {
        val apkFile = File(apkPath)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK file does not exist: $apkPath")
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // API 24+: must use FileProvider to share the file URI.
                val uri = FileProvider.getUriForFile(
                    this@MainActivity,
                    "${applicationContext.packageName}.fileprovider",
                    apkFile
                )
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                setDataAndType(
                    Uri.fromFile(apkFile),
                    "application/vnd.android.package-archive"
                )
            }
        }
        startActivity(intent)
    }

    private fun shareFiles(paths: List<String>, mimeType: String) {
        if (paths.isEmpty()) return
        val uris = ArrayList<Uri>()
        for (p in paths) {
            val file = File(p)
            if (file.exists()) {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        file
                    )
                } else {
                    Uri.fromFile(file)
                }
                uris.add(uri)
            }
        }
        if (uris.isEmpty()) return

        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uris[0])
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = mimeType
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        val chooser = Intent.createChooser(intent, "Share media via").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(chooser)
    }

    private fun setAsWallpaper(path: String, mimeType: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("File does not exist: $path")
        }
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )
        } else {
            Uri.fromFile(file)
        }
        val intent = Intent(Intent.ACTION_ATTACH_DATA).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra("mimeType", mimeType)
        }
        val chooser = Intent.createChooser(intent, "Set as").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(chooser)
    }
}
