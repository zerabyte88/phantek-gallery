package com.phantek.virgo.spica

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    private var pendingFolderPickerResult: MethodChannel.Result? = null
    private val REQUEST_CODE_PICK_FOLDER = 9921
    private var pendingAppLockResult: MethodChannel.Result? = null
    private val REQUEST_CODE_APP_LOCK = 9922
    private val scrubExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var activeScrubPath: String? = null
    private var activeScrubRetriever: android.media.MediaMetadataRetriever? = null
    private var activeScrubFis: java.io.FileInputStream? = null
    private var activeScrubPfd: android.os.ParcelFileDescriptor? = null
    private var activeScrubOrigW: Int = 0
    private var activeScrubOrigH: Int = 0
    private var activeScrubRotation: Int = 0

    override fun onDestroy() {
        try {
            if (!scrubExecutor.isShutdown) {
                scrubExecutor.execute { releaseActiveScrubRetriever() }
            }
            scrubExecutor.shutdown()
        } catch (_: Throwable) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/app_lock"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canAuthenticate" -> result.success(canAuthenticateDevice())
                "authenticate" -> {
                    val title = call.argument<String>("title") ?: "Unlock"
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    authenticateDevice(title, subtitle, result)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/screen_keeper"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "keepOn" -> {
                    window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "clearKeepOn" -> {
                    window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "setMaxBrightness" -> {
                    val lp = window.attributes
                    lp.screenBrightness = 1.0f
                    window.attributes = lp
                    result.success(null)
                }
                "restoreBrightness" -> {
                    val lp = window.attributes
                    lp.screenBrightness = android.view.WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = lp
                    result.success(null)
                }
                "setSecure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/folder_picker"
        ).setMethodCallHandler { call, result ->
            if (call.method == "pickFolder") {
                if (pendingFolderPickerResult != null) {
                    result.error("BUSY", "A folder picker is already in progress", null)
                    return@setMethodCallHandler
                }
                pendingFolderPickerResult = result
                try {
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    startActivityForResult(intent, REQUEST_CODE_PICK_FOLDER)
                } catch (e: Exception) {
                    pendingFolderPickerResult = null
                    result.error("PICK_FAILED", e.message, null)
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

        val executor = java.util.concurrent.Executors.newFixedThreadPool(4)
        val videoExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)
        val hiResExecutor = java.util.concurrent.Executors.newFixedThreadPool(2) { r ->
            Thread(r, "grid-hires").apply { priority = Thread.MIN_PRIORITY + 1 }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/thumbnail"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getVideoThumbnail") {
                val assetId = call.argument<String>("assetId")
                val path = call.argument<String>("path") ?: ""
                val size = call.argument<Int>("size") ?: 512
                val lowPriority = call.argument<Boolean>("lowPriority") ?: false
                if (path.isEmpty() && assetId == null) {
                    result.error("INVALID_ARGS", "Both path and assetId are null/empty", null)
                    return@setMethodCallHandler
                }
                val pool = if (lowPriority) hiResExecutor else videoExecutor
                pool.execute {
                    try {
                        val bytes = extractVideoThumbnail(path, assetId, size)
                        runOnUiThread {
                            result.success(bytes)
                        }
                    } catch (e: Throwable) {
                        runOnUiThread {
                            result.success(null)
                        }
                    }
                }
            } else if (call.method == "getImageThumbnail") {
                val assetId = call.argument<String>("assetId")
                val path = call.argument<String>("path")
                val size = call.argument<Int>("size") ?: 512
                val lowPriority = call.argument<Boolean>("lowPriority") ?: false
                if (path == null && assetId == null) {
                    result.error("INVALID_ARGS", "Both path and assetId are null", null)
                    return@setMethodCallHandler
                }
                val pool = if (lowPriority) hiResExecutor else executor
                pool.execute {
                    try {
                        val bytes = extractImageThumbnail(path ?: "", assetId, size)
                        runOnUiThread {
                            result.success(bytes)
                        }
                    } catch (e: Throwable) {
                        runOnUiThread {
                            result.success(null)
                        }
                    }
                }
            } else if (call.method == "getVideoFrame") {
                val path = call.argument<String>("path")
                val timeUs = (call.argument<Number>("timeUs"))?.toLong() ?: 0L
                val width = call.argument<Int>("width") ?: 256
                val height = call.argument<Int>("height") ?: 256
                val exact = call.argument<Boolean>("exact") ?: false
                if (path == null) {
                    result.error("INVALID_PATH", "Path is null", null)
                    return@setMethodCallHandler
                }
                if (!scrubExecutor.isShutdown) {
                    try {
                        scrubExecutor.execute {
                            try {
                                val bytes = extractVideoFrame(path, timeUs, width, height, exact)
                                runOnUiThread {
                                    result.success(bytes)
                                }
                            } catch (e: Throwable) {
                                runOnUiThread {
                                    result.success(null)
                                }
                            }
                        }
                    } catch (_: Throwable) {
                        result.success(null)
                    }
                } else {
                    result.success(null)
                }
            } else if (call.method == "releaseVideoFrameRetriever") {
                try {
                    if (!scrubExecutor.isShutdown) {
                        scrubExecutor.execute {
                            releaseActiveScrubRetriever()
                        }
                    }
                } catch (_: Throwable) {}
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/metadata"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getMediaMetadata") {
                val path = call.argument<String>("path") ?: ""
                val assetId = call.argument<String>("assetId")
                val isVideo = call.argument<Boolean>("isVideo") ?: false
                if (path.isEmpty() && assetId == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    try {
                        val map = if (isVideo) {
                            extractVideoMetadata(path, assetId)
                        } else {
                            extractImageMetadata(path, assetId)
                        }
                        runOnUiThread { result.success(map) }
                    } catch (_: Throwable) {
                        runOnUiThread { result.success(null) }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun extractImageThumbnail(path: String, assetId: String?, targetSize: Int): ByteArray? {
        val file = if (path.isNotEmpty()) File(path) else null
        if (file != null && (!file.exists() || !file.canRead()) && assetId == null) return null

        var bitmap: android.graphics.Bitmap? = null
        val cleanPath = file?.absolutePath ?: ""
        val canonicalPath = try { file?.canonicalPath ?: cleanPath } catch (_: Throwable) { cleanPath }

        // 1. Android Q+ (API 29+) MediaStore contentResolver.loadThumbnail (Fastest system cache)
        if (targetSize <= 512 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                var id: Long? = assetId?.toLongOrNull()
                if (id == null && file != null) {
                    val projection = arrayOf(android.provider.MediaStore.Images.Media._ID)
                    val cursor = contentResolver.query(
                        android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        projection,
                        "${android.provider.MediaStore.Images.Media.DATA} = ? OR ${android.provider.MediaStore.Images.Media.DATA} = ?",
                        arrayOf(cleanPath, canonicalPath),
                        null
                    )
                    cursor?.use {
                        if (it.moveToFirst()) {
                            id = it.getLong(it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media._ID))
                        }
                    }
                    if (id == null) {
                        val nameCursor = contentResolver.query(
                            android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            projection,
                            "${android.provider.MediaStore.Images.Media.DISPLAY_NAME} = ? AND ${android.provider.MediaStore.Images.Media.SIZE} = ?",
                            arrayOf(file.name, file.length().toString()),
                            null
                        )
                        nameCursor?.use {
                            if (it.moveToFirst()) {
                                id = it.getLong(it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media._ID))
                            }
                        }
                    }
                }
                if (id != null) {
                    val uri = android.content.ContentUris.withAppendedId(
                        android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        id!!
                    )
                    bitmap = contentResolver.loadThumbnail(uri, android.util.Size(targetSize, targetSize), null)
                }
            } catch (_: Throwable) {}
        }

        // 2. High-performance native downsampled decoding via BitmapFactory.Options.inSampleSize
        if (bitmap == null && cleanPath.isNotEmpty()) {
            try {
                val boundsOptions = android.graphics.BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                android.graphics.BitmapFactory.decodeFile(cleanPath, boundsOptions)

                val origW = boundsOptions.outWidth
                val origH = boundsOptions.outHeight
                if (origW > 0 && origH > 0) {
                    var sampleSize = 1
                    val maxDim = Math.max(origW, origH)
                    while ((maxDim / (sampleSize * 2)) >= targetSize) {
                        sampleSize *= 2
                    }

                    val decodeOptions = android.graphics.BitmapFactory.Options().apply {
                        inSampleSize = sampleSize
                        inPreferredConfig = if (targetSize > 512) {
                            android.graphics.Bitmap.Config.ARGB_8888
                        } else {
                            android.graphics.Bitmap.Config.RGB_565
                        }
                    }
                    val decoded = android.graphics.BitmapFactory.decodeFile(cleanPath, decodeOptions)
                    if (decoded != null) {
                        // Handle EXIF rotation
                        var degrees = 0
                        try {
                            val exif = android.media.ExifInterface(cleanPath)
                            val orientation = exif.getAttributeInt(
                                android.media.ExifInterface.TAG_ORIENTATION,
                                android.media.ExifInterface.ORIENTATION_NORMAL
                            )
                            degrees = when (orientation) {
                                android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90
                                android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180
                                android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270
                                else -> 0
                            }
                        } catch (_: Throwable) {}

                        val rotated = if (degrees != 0) {
                            val matrix = android.graphics.Matrix().apply { postRotate(degrees.toFloat()) }
                            val r = android.graphics.Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                            if (r !== decoded && !decoded.isRecycled) {
                                decoded.recycle()
                            }
                            r
                        } else {
                            decoded
                        }

                        // Scale to target size if still significantly larger
                        val curMax = Math.max(rotated.width, rotated.height)
                        bitmap = if (curMax > targetSize * 1.5) {
                            val scale = targetSize.toFloat() / curMax.toFloat()
                            val dstW = Math.max(2, (rotated.width * scale).toInt())
                            val dstH = Math.max(2, (rotated.height * scale).toInt())
                            val scaled = android.graphics.Bitmap.createScaledBitmap(rotated, dstW, dstH, true)
                            if (scaled !== rotated && !rotated.isRecycled) {
                                rotated.recycle()
                            }
                            scaled
                        } else {
                            rotated
                        }
                    }
                }
            } catch (_: Throwable) {}
        }

        if (bitmap == null) return null

        val stream = java.io.ByteArrayOutputStream()
        val jpegQuality = if (targetSize > 512) 90 else 85
        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, jpegQuality, stream)
        val bytes = stream.toByteArray()
        if (!bitmap.isRecycled) {
            bitmap.recycle()
        }
        return if (bytes.isNotEmpty()) bytes else null
    }

    private fun extractVideoThumbnail(path: String, assetId: String?, targetSize: Int): ByteArray? {
        var bitmap: android.graphics.Bitmap? = null

        // Resolve MediaStore URI from assetId or path
        var id: Long? = assetId?.toLongOrNull()
        val file = if (path.isNotEmpty()) File(path) else null
        val cleanPath = file?.absolutePath ?: ""
        val canonicalPath = try { file?.canonicalPath ?: cleanPath } catch (_: Throwable) { cleanPath }

        if (id == null && (cleanPath.isNotEmpty() || file != null)) {
            try {
                val projection = arrayOf(android.provider.MediaStore.Video.Media._ID)
                val cursor = contentResolver.query(
                    android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    "${android.provider.MediaStore.Video.Media.DATA} = ? OR ${android.provider.MediaStore.Video.Media.DATA} = ?",
                    arrayOf(cleanPath, canonicalPath),
                    null
                )
                cursor?.use {
                    if (it.moveToFirst()) {
                        id = it.getLong(it.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media._ID))
                    }
                }

                // Fallback lookup by DISPLAY_NAME + SIZE if DATA column was blocked/redacted by Scoped Storage
                if (id == null && file != null) {
                    val nameCursor = contentResolver.query(
                        android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                        projection,
                        "${android.provider.MediaStore.Video.Media.DISPLAY_NAME} = ? AND ${android.provider.MediaStore.Video.Media.SIZE} = ?",
                        arrayOf(file.name, file.length().toString()),
                        null
                    )
                    nameCursor?.use {
                        if (it.moveToFirst()) {
                            id = it.getLong(it.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media._ID))
                        }
                    }
                }
            } catch (_: Throwable) {}
        }

        val uri = if (id != null) {
            android.content.ContentUris.withAppendedId(
                android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                id!!
            )
        } else null

        // 1. Android Q+ (API 29+): prioritize contentResolver.loadThumbnail in <2ms when targetSize <= 512 and uri != null
        if (targetSize <= 512 && uri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                bitmap = contentResolver.loadThumbnail(
                    uri,
                    android.util.Size(targetSize.coerceAtMost(1080), targetSize.coerceAtMost(1080)),
                    null
                )
            } catch (_: Throwable) {}
        }

        // 2. MediaMetadataRetriever (for high-res or when system cache is absent)
        if (bitmap == null) {
            val retriever = android.media.MediaMetadataRetriever()
            var pfd: android.os.ParcelFileDescriptor? = null
            var fis: java.io.FileInputStream? = null
            try {
                var sourceSet = false

                // Primary source: MediaStore ParcelFileDescriptor (bypasses Scoped Storage restrictions)
                if (uri != null) {
                    try {
                        pfd = contentResolver.openFileDescriptor(uri, "r")
                        if (pfd != null) {
                            retriever.setDataSource(pfd.fileDescriptor)
                            sourceSet = true
                        }
                    } catch (_: Throwable) {}
                    if (!sourceSet) {
                        try {
                            retriever.setDataSource(applicationContext, uri)
                            sourceSet = true
                        } catch (_: Throwable) {}
                    }
                }

                // Secondary source: direct file path / FileInputStream
                if (!sourceSet && path.isNotEmpty()) {
                    try {
                        retriever.setDataSource(path)
                        sourceSet = true
                    } catch (_: Throwable) {
                        if (file != null && file.exists()) {
                            try {
                                fis = java.io.FileInputStream(file)
                                retriever.setDataSource(fis.fd, 0, file.length())
                                sourceSet = true
                            } catch (_: Throwable) {
                                try {
                                    fis?.close()
                                    fis = java.io.FileInputStream(file)
                                    retriever.setDataSource(fis.fd)
                                    sourceSet = true
                                } catch (_: Throwable) {}
                            }
                        }
                    }
                }

                if (sourceSet) {
                    val rotationStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    val rotation = rotationStr?.toIntOrNull() ?: 0

                    val streamW = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                    val streamH = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                    val durationMs = retriever.extractMetadata(
                        android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                    )?.toLongOrNull() ?: 0L
                    val altTimeUs = if (durationMs > 1000L) (durationMs * 1000L) / 3L else 500000L
                    val scaleTarget = if (streamW >= 1920 || streamH >= 1920) targetSize.coerceAtMost(1280) else targetSize

                    val attempts = arrayOf(
                        Pair(-1L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC),
                        Pair(0L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC),
                        Pair(altTimeUs, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC),
                        Pair(500000L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    )

                    for (att in attempts) {
                        if (bitmap != null) break
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                                bitmap = retriever.getScaledFrameAtTime(att.first, att.second, scaleTarget, scaleTarget)
                            }
                            if (bitmap == null) {
                                bitmap = retriever.getFrameAtTime(att.first, att.second)
                            }
                        } catch (_: Throwable) {}
                    }

                    // Correct rotation if needed (API 27+ getFrameAtTime may or may not apply rotation depending on OEM)
                    if (bitmap != null && rotation != 0) {
                        val alreadyRotated = if (rotation == 90 || rotation == 270) {
                            if (streamW > 0 && streamH > 0 && streamW != streamH) {
                                (streamW > streamH && bitmap!!.height > bitmap!!.width) ||
                                    (streamH > streamW && bitmap!!.width > bitmap!!.height)
                            } else {
                                false
                            }
                        } else {
                            false
                        }
                        if (!alreadyRotated) {
                            val matrix = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }
                            val rotated = android.graphics.Bitmap.createBitmap(
                                bitmap!!, 0, 0, bitmap!!.width, bitmap!!.height, matrix, true
                            )
                            if (rotated != bitmap) {
                                bitmap?.recycle()
                                bitmap = rotated
                            }
                        }
                    }
                }
            } catch (_: Throwable) {
            } finally {
                try { retriever.release() } catch (_: Throwable) {}
                try { pfd?.close() } catch (_: Throwable) {}
                try { fis?.close() } catch (_: Throwable) {}
            }
        }

        // 3. Fallbacks if MediaMetadataRetriever failed to get a bitmap
        if (bitmap == null && uri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                bitmap = contentResolver.loadThumbnail(uri, android.util.Size(targetSize, targetSize), null)
            } catch (_: Throwable) {}
        }

        if (bitmap == null && file != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                bitmap = android.media.ThumbnailUtils.createVideoThumbnail(
                    file,
                    android.util.Size(targetSize, targetSize),
                    null
                )
            } catch (_: Throwable) {}
        }

        if (bitmap == null && path.isNotEmpty()) {
            try {
                bitmap = android.media.ThumbnailUtils.createVideoThumbnail(
                    path,
                    android.provider.MediaStore.Images.Thumbnails.MINI_KIND
                )
            } catch (_: Throwable) {}
        }

        if (bitmap == null) return null

        // Scale proportionally down to targetSize preserving exact aspect ratio
        val curMax = Math.max(bitmap!!.width, bitmap!!.height)
        val scaled = if (curMax > targetSize) {
            val scale = targetSize.toFloat() / curMax.toFloat()
            val dstW = Math.max(2, (bitmap!!.width * scale).toInt())
            val dstH = Math.max(2, (bitmap!!.height * scale).toInt())
            val sc = android.graphics.Bitmap.createScaledBitmap(bitmap!!, dstW, dstH, true)
            if (sc != bitmap) {
                bitmap?.recycle()
            }
            sc
        } else {
            bitmap!!
        }

        val bos = java.io.ByteArrayOutputStream()
        scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 92, bos)
        scaled.recycle()
        val resultBytes = bos.toByteArray()
        return if (resultBytes.isNotEmpty()) resultBytes else null
    }

    private fun releaseActiveScrubRetriever() {
        try { activeScrubRetriever?.release() } catch (_: Throwable) {}
        try { activeScrubFis?.close() } catch (_: Throwable) {}
        try { activeScrubPfd?.close() } catch (_: Throwable) {}
        activeScrubRetriever = null
        activeScrubFis = null
        activeScrubPfd = null
        activeScrubPath = null
        activeScrubOrigW = 0
        activeScrubOrigH = 0
        activeScrubRotation = 0
    }

    private fun openActiveScrubRetriever(path: String): Boolean {
        releaseActiveScrubRetriever()
        val file = File(path)
        val retriever = android.media.MediaMetadataRetriever()
        var fis: java.io.FileInputStream? = null
        var pfd: android.os.ParcelFileDescriptor? = null
        try {
            var dataSourceSet = false

            // 1. Direct path / file descriptor if file is accessible
            if (file.exists() && file.canRead()) {
                try {
                    retriever.setDataSource(file.absolutePath)
                    dataSourceSet = true
                } catch (_: Throwable) {
                    try {
                        fis = java.io.FileInputStream(file)
                        retriever.setDataSource(fis.fd, 0, file.length())
                        dataSourceSet = true
                    } catch (_: Throwable) {
                        try {
                            fis?.close()
                            fis = java.io.FileInputStream(file)
                            retriever.setDataSource(fis.fd)
                            dataSourceSet = true
                        } catch (_: Throwable) {}
                    }
                }
            }

            // 2. Try MediaStore URI fallback for Android Q+ Scoped Storage
            if (!dataSourceSet && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    val cleanPath = file.absolutePath
                    val canonicalPath = try { file.canonicalPath } catch (_: Throwable) { cleanPath }
                    val projection = arrayOf(android.provider.MediaStore.Video.Media._ID)
                    var id: Long? = null
                    val cursor = contentResolver.query(
                        android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                        projection,
                        "${android.provider.MediaStore.Video.Media.DATA} = ? OR ${android.provider.MediaStore.Video.Media.DATA} = ?",
                        arrayOf(cleanPath, canonicalPath),
                        null
                    )
                    cursor?.use {
                        if (it.moveToFirst()) {
                            id = it.getLong(it.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media._ID))
                        }
                    }
                    if (id == null) {
                        val nameCursor = contentResolver.query(
                            android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            projection,
                            "${android.provider.MediaStore.Video.Media.DISPLAY_NAME} = ? AND ${android.provider.MediaStore.Video.Media.SIZE} = ?",
                            arrayOf(file.name, file.length().toString()),
                            null
                        )
                        nameCursor?.use {
                            if (it.moveToFirst()) {
                                id = it.getLong(it.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media._ID))
                            }
                        }
                    }
                    if (id != null) {
                        val uri = android.content.ContentUris.withAppendedId(
                            android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            id!!
                        )
                        pfd = contentResolver.openFileDescriptor(uri, "r")
                        if (pfd != null) {
                            retriever.setDataSource(pfd.fileDescriptor)
                            dataSourceSet = true
                        } else {
                            retriever.setDataSource(applicationContext, uri)
                            dataSourceSet = true
                        }
                    }
                } catch (_: Throwable) {}
            }

            // 3. Fallback to raw string path
            if (!dataSourceSet) {
                retriever.setDataSource(path)
                dataSourceSet = true
            }

            val widthStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val heightStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotationStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)

            activeScrubPath = path
            activeScrubRetriever = retriever
            activeScrubFis = fis
            activeScrubPfd = pfd
            activeScrubOrigW = widthStr?.toIntOrNull() ?: 0
            activeScrubOrigH = heightStr?.toIntOrNull() ?: 0
            activeScrubRotation = rotationStr?.toIntOrNull() ?: 0
            return true
        } catch (_: Throwable) {
            try { retriever.release() } catch (_: Throwable) {}
            try { fis?.close() } catch (_: Throwable) {}
            try { pfd?.close() } catch (_: Throwable) {}
            return false
        }
    }

    private fun decodeScrubBitmap(
        retriever: android.media.MediaMetadataRetriever,
        safeTimeUs: Long,
        options: IntArray,
        dstW: Int,
        dstH: Int
    ): Pair<android.graphics.Bitmap?, Boolean> {
        var bitmap: android.graphics.Bitmap? = null
        var hadException = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            for (opt in options) {
                if (bitmap != null) break
                try {
                    bitmap = retriever.getScaledFrameAtTime(safeTimeUs, opt, dstW, dstH)
                } catch (_: Throwable) {
                    hadException = true
                }
            }
        }

        if (bitmap == null) {
            for (opt in options) {
                if (bitmap != null) break
                try {
                    val rawBitmap = retriever.getFrameAtTime(safeTimeUs, opt)
                    if (rawBitmap != null) {
                        if (rawBitmap.width > dstW || rawBitmap.height > dstH) {
                            bitmap = android.graphics.Bitmap.createScaledBitmap(rawBitmap, dstW, dstH, true)
                            if (bitmap != rawBitmap) {
                                rawBitmap.recycle()
                            }
                        } else {
                            bitmap = rawBitmap
                        }
                    }
                } catch (_: Throwable) {
                    hadException = true
                }
            }
        }
        return Pair(bitmap, hadException)
    }

    private fun extractVideoFrame(
        path: String,
        timeUs: Long,
        targetWidth: Int,
        targetHeight: Int,
        exact: Boolean = false
    ): ByteArray? {
        try {
            if (activeScrubPath != path || activeScrubRetriever == null) {
                if (!openActiveScrubRetriever(path)) {
                    return null
                }
            }

            var retriever = activeScrubRetriever ?: return null
            val origW = activeScrubOrigW
            val origH = activeScrubOrigH
            var rotation = activeScrubRotation

            val (dstW, dstH) = if (origW > 0 && origH > 0) {
                val scaleW = targetWidth.toFloat() / origW.toFloat()
                val scaleH = targetHeight.toFloat() / origH.toFloat()
                val scale = scaleW.coerceAtMost(scaleH)
                val w = (((origW * scale).toInt() / 2) * 2).coerceAtLeast(2)
                val h = (((origH * scale).toInt() / 2) * 2).coerceAtLeast(2)
                Pair(w, h)
            } else {
                Pair(targetWidth, targetHeight)
            }

            // Use sync-frame extraction during scrubbing for >=720p streams to avoid keyframe decode stalls,
            // and exact frame extraction when requested (e.g. finger release).
            val isHighRes = origW >= 1280 || origH >= 1280
            val options = if (exact || !isHighRes) {
                intArrayOf(
                    android.media.MediaMetadataRetriever.OPTION_CLOSEST,
                    android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    android.media.MediaMetadataRetriever.OPTION_PREVIOUS_SYNC
                )
            } else {
                intArrayOf(
                    android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    android.media.MediaMetadataRetriever.OPTION_PREVIOUS_SYNC
                )
            }

            val safeTimeUs = timeUs.coerceAtLeast(0L)
            var (bitmap, hadException) = decodeScrubBitmap(retriever, safeTimeUs, options, dstW, dstH)
            if (bitmap == null && hadException) {
                if (openActiveScrubRetriever(path)) {
                    retriever = activeScrubRetriever ?: return null
                    rotation = activeScrubRotation
                    bitmap = decodeScrubBitmap(retriever, safeTimeUs, options, dstW, dstH).first
                }
            }

            if (bitmap != null && rotation != 0) {
                try {
                    val matrix = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }
                    val rotated = android.graphics.Bitmap.createBitmap(
                        bitmap!!,
                        0,
                        0,
                        bitmap!!.width,
                        bitmap!!.height,
                        matrix,
                        true
                    )
                    if (rotated != bitmap) {
                        bitmap?.recycle()
                        bitmap = rotated
                    }
                } catch (_: Throwable) {}
            }

            if (bitmap != null) {
                val bos = java.io.ByteArrayOutputStream()
                bitmap!!.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, bos)
                bitmap!!.recycle()
                val resultBytes = bos.toByteArray()
                return if (resultBytes.isNotEmpty()) resultBytes else null
            }
        } catch (_: Throwable) {
            releaseActiveScrubRetriever()
        }
        return null
    }

    private fun parseExifRational(raw: String?): Double? {
        if (raw.isNullOrBlank()) return null
        val trimmed = raw.trim()
        val slashIdx = trimmed.indexOf('/')
        if (slashIdx > 0 && slashIdx < trimmed.length - 1) {
            val num = trimmed.substring(0, slashIdx).trim().toDoubleOrNull() ?: return null
            val den = trimmed.substring(slashIdx + 1).trim().toDoubleOrNull() ?: return null
            if (den == 0.0) return null
            return num / den
        }
        return trimmed.toDoubleOrNull()
    }

    private fun extractXmpCreatorTool(xmp: String?): String? {
        if (xmp.isNullOrBlank()) return null
        val tagRegex = Regex("<xmp:CreatorTool[^>]*>([^<]+)</xmp:CreatorTool>", RegexOption.IGNORE_CASE)
        tagRegex.find(xmp)?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val attrRegex = Regex("xmp:CreatorTool=\"([^\"]+)\"", RegexOption.IGNORE_CASE)
        attrRegex.find(xmp)?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        return null
    }

    private fun readPngMetadata(file: File, out: HashMap<String, Any>) {
        if (!file.exists() || !file.canRead() || file.length() < 33L) return
        try {
            java.io.DataInputStream(java.io.BufferedInputStream(java.io.FileInputStream(file), 8192)).use { dis ->
                val sig = ByteArray(8)
                dis.readFully(sig)
                val pngMagic = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
                if (!sig.contentEquals(pngMagic)) return

                var bytesScanned = 8L
                val maxScanBytes = 262_144L
                while (bytesScanned < maxScanBytes) {
                    val length = dis.readInt()
                    if (length < 0 || length > 200_000) break
                    val typeBytes = ByteArray(4)
                    dis.readFully(typeBytes)
                    val type = String(typeBytes, Charsets.US_ASCII)
                    if (type == "IDAT" || type == "IEND") break

                    if (type == "pHYs" && length == 9) {
                        val ppuX = dis.readInt().toLong() and 0xFFFFFFFFL
                        dis.readInt() // ppuY
                        val unit = dis.readUnsignedByte()
                        if (unit == 1 && ppuX > 0L && !out.containsKey("dpi")) {
                            val dpi = Math.round(ppuX / 39.3701).toInt()
                            if (dpi in 1..2400) out["dpi"] = dpi
                        }
                        dis.skipBytes(4) // CRC
                    } else if ((type == "tEXt" || type == "iTXt") && length > 0 && !out.containsKey("software")) {
                        val data = ByteArray(length)
                        dis.readFully(data)
                        dis.skipBytes(4) // CRC
                        val zeroIdx = data.indexOf(0.toByte())
                        if (zeroIdx > 0 && zeroIdx < data.size - 1) {
                            val key = String(data, 0, zeroIdx, Charsets.ISO_8859_1).trim()
                            if (type == "tEXt" && (key.equals("Software", true) || key.equals("Creator", true) || key.equals("Source", true))) {
                                val value = String(data, zeroIdx + 1, data.size - zeroIdx - 1, Charsets.ISO_8859_1).trim()
                                if (value.isNotEmpty() && value.length <= 120) {
                                    out["software"] = value
                                }
                            } else if (type == "iTXt") {
                                // iTXt: keyword\0 compFlag(1) compMethod(1) langTag\0 translatedKey\0 text
                                val compFlag = data.getOrNull(zeroIdx + 1)?.toInt() ?: 1
                                if (compFlag == 0) {
                                    var pos = zeroIdx + 3
                                    while (pos < data.size && data[pos] != 0.toByte()) pos++
                                    pos++ // skip langTag \0
                                    while (pos < data.size && data[pos] != 0.toByte()) pos++
                                    pos++ // skip translatedKey \0
                                    if (pos < data.size) {
                                        val text = String(data, pos, data.size - pos, Charsets.UTF_8).trim()
                                        if (key == "XML:com.adobe.xmp") {
                                            extractXmpCreatorTool(text)?.let { out["software"] = it }
                                        } else if (key.equals("Software", true) || key.equals("Creator", true)) {
                                            if (text.isNotEmpty() && text.length <= 120) {
                                                out["software"] = text
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        var toSkip = length.toLong() + 4L
                        while (toSkip > 0L) {
                            val skipped = dis.skip(toSkip)
                            if (skipped <= 0L) break
                            toSkip -= skipped
                        }
                    }
                    bytesScanned += 12L + length.toLong()
                }
            }
        } catch (_: Throwable) {}
    }

    private fun readPsdMetadata(file: File, out: HashMap<String, Any>) {
        if (!file.exists() || !file.canRead() || file.length() < 26L) return
        try {
            java.io.DataInputStream(java.io.FileInputStream(file)).use { dis ->
                val sig = ByteArray(4)
                dis.readFully(sig)
                if (String(sig, Charsets.US_ASCII) != "8BPS") return
                dis.readUnsignedShort() // version
                dis.skipBytes(6) // reserved
                dis.readUnsignedShort() // channels
                val height = dis.readInt()
                val width = dis.readInt()
                val depth = dis.readUnsignedShort()
                val colorMode = dis.readUnsignedShort()
                if (width > 0 && height > 0) {
                    out["width"] = width
                    out["height"] = height
                }
                val modeName = when (colorMode) {
                    0 -> "Bitmap"
                    1 -> "Grayscale"
                    2 -> "Indexed"
                    3 -> "RGB"
                    4 -> "CMYK"
                    7 -> "Multichannel"
                    8 -> "Duotone"
                    9 -> "Lab"
                    else -> null
                }
                if (modeName != null) {
                    out["colorSpace"] = if (depth > 0) "$modeName ($depth-bit)" else modeName
                }
                out["mimeType"] = "image/vnd.adobe.photoshop"
            }
        } catch (_: Throwable) {}
    }

    private fun extractImageMetadata(path: String, assetId: String?): Map<String, Any> {
        val out = HashMap<String, Any>()
        val file = if (path.isNotEmpty()) File(path) else null
        val lowerPath = path.lowercase()

        if (file != null && lowerPath.endsWith(".psd")) {
            readPsdMetadata(file, out)
            return out
        }

        // 1. Decode bounds, mimeType, and ColorSpace without allocating pixels.
        if (file != null && file.exists() && file.canRead()) {
            try {
                val opts = android.graphics.BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                android.graphics.BitmapFactory.decodeFile(file.absolutePath, opts)
                if (opts.outWidth > 0 && opts.outHeight > 0) {
                    out["width"] = opts.outWidth
                    out["height"] = opts.outHeight
                }
                opts.outMimeType?.takeIf { it.isNotBlank() }?.let { out["mimeType"] = it }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    opts.outColorSpace?.name?.takeIf { it.isNotBlank() }?.let {
                        out["colorSpace"] = it
                    }
                }
            } catch (_: Throwable) {}
        }

        // 2. EXIF via android.media.ExifInterface
        var pfd: android.os.ParcelFileDescriptor? = null
        try {
            var exif: android.media.ExifInterface? = null
            if (file != null && file.exists() && file.canRead()) {
                try {
                    exif = android.media.ExifInterface(file.absolutePath)
                } catch (_: Throwable) {}
            }
            if (exif == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val id = assetId?.toLongOrNull()
                if (id != null) {
                    val uri = android.content.ContentUris.withAppendedId(
                        android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        id
                    )
                    pfd = contentResolver.openFileDescriptor(uri, "r")
                    if (pfd != null) {
                        exif = android.media.ExifInterface(pfd.fileDescriptor)
                    }
                }
            }
            if (exif != null) {
                val make = exif.getAttribute(android.media.ExifInterface.TAG_MAKE)?.trim().orEmpty()
                val model = exif.getAttribute(android.media.ExifInterface.TAG_MODEL)?.trim().orEmpty()
                val camera = when {
                    make.isNotEmpty() && model.isNotEmpty() -> {
                        if (model.startsWith(make, ignoreCase = true)) model else "$make $model"
                    }
                    model.isNotEmpty() -> model
                    make.isNotEmpty() -> make
                    else -> ""
                }
                if (camera.isNotEmpty()) out["camera"] = camera

                val isoRaw = exif.getAttribute("ISOSpeedRatings")
                    ?: exif.getAttribute("PhotographicSensitivity")
                val isoInt = isoRaw?.trim()?.split(',', ' ')?.firstOrNull()?.toIntOrNull()
                if (isoInt != null && isoInt > 0) out["iso"] = isoInt

                val fNumber = parseExifRational(exif.getAttribute("FNumber"))
                if (fNumber != null && fNumber > 0.0) out["aperture"] = fNumber

                val exposure = parseExifRational(exif.getAttribute("ExposureTime"))
                if (exposure != null && exposure > 0.0) out["shutterSpeed"] = exposure

                val focal = parseExifRational(exif.getAttribute(android.media.ExifInterface.TAG_FOCAL_LENGTH))
                if (focal != null && focal > 0.0) out["focalLength"] = focal

                val focal35 = exif.getAttribute("FocalLengthIn35mmFilm")?.trim()?.toIntOrNull()
                if (focal35 != null && focal35 > 0) out["focalLength35mm"] = focal35

                val software = exif.getAttribute("Software")?.trim()
                if (!software.isNullOrEmpty() && software.length <= 120) {
                    out["software"] = software
                }

                if (!out.containsKey("software") && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    extractXmpCreatorTool(exif.getAttribute("Xmp"))?.let {
                        out["software"] = it
                    }
                }

                val xRes = parseExifRational(exif.getAttribute("XResolution"))
                if (xRes != null && xRes > 0.0) {
                    val unit = exif.getAttributeInt("ResolutionUnit", 2)
                    val dpi = when (unit) {
                        3 -> Math.round(xRes * 2.54).toInt()
                        else -> Math.round(xRes).toInt()
                    }
                    if (dpi in 1..2400) out["dpi"] = dpi
                }

                if (!out.containsKey("colorSpace")) {
                    when (exif.getAttributeInt("ColorSpace", -1)) {
                        1 -> out["colorSpace"] = "sRGB"
                        2 -> out["colorSpace"] = "Adobe RGB"
                    }
                }

                val orientation = exif.getAttributeInt(
                    android.media.ExifInterface.TAG_ORIENTATION,
                    android.media.ExifInterface.ORIENTATION_NORMAL
                )
                if (orientation == android.media.ExifInterface.ORIENTATION_ROTATE_90 ||
                    orientation == android.media.ExifInterface.ORIENTATION_ROTATE_270
                ) {
                    val w = out["width"] as? Int
                    val h = out["height"] as? Int
                    if (w != null && h != null && w > 0 && h > 0) {
                        out["width"] = h
                        out["height"] = w
                    }
                }
            }
        } catch (_: Throwable) {
        } finally {
            try { pfd?.close() } catch (_: Throwable) {}
        }

        // 3. Lightweight PNG chunk scan for Photoshop / Clip Studio Paint software & DPI.
        if (file != null && (lowerPath.endsWith(".png") || out["mimeType"] == "image/png")) {
            readPngMetadata(file, out)
        }

        return out
    }

    private fun extractVideoMetadata(path: String, assetId: String?): Map<String, Any> {
        val out = HashMap<String, Any>()
        val file = if (path.isNotEmpty()) File(path) else null
        val id = assetId?.toLongOrNull()
        val uri = if (id != null) {
            android.content.ContentUris.withAppendedId(
                android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                id
            )
        } else null

        // 1. MediaExtractor for video/audio codecs, FPS, channels, sample rate.
        val extractor = android.media.MediaExtractor()
        var extPfd: android.os.ParcelFileDescriptor? = null
        var extFis: java.io.FileInputStream? = null
        try {
            var sourceSet = false
            if (file != null && file.exists() && file.canRead()) {
                try {
                    extractor.setDataSource(file.absolutePath)
                    sourceSet = true
                } catch (_: Throwable) {
                    try {
                        extFis = java.io.FileInputStream(file)
                        extractor.setDataSource(extFis.fd)
                        sourceSet = true
                    } catch (_: Throwable) {}
                }
            }
            if (!sourceSet && uri != null) {
                try {
                    extPfd = contentResolver.openFileDescriptor(uri, "r")
                    if (extPfd != null) {
                        extractor.setDataSource(extPfd.fileDescriptor)
                        sourceSet = true
                    }
                } catch (_: Throwable) {
                    try {
                        extractor.setDataSource(applicationContext, uri, null)
                        sourceSet = true
                    } catch (_: Throwable) {}
                }
            }

            if (sourceSet) {
                var gotVideo = false
                var gotAudio = false
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: continue
                    if (!gotVideo && mime.startsWith("video/")) {
                        gotVideo = true
                        out["videoCodec"] = mime
                        if (format.containsKey(android.media.MediaFormat.KEY_FRAME_RATE)) {
                            val fps = try {
                                format.getFloat(android.media.MediaFormat.KEY_FRAME_RATE).toDouble()
                            } catch (_: Throwable) {
                                try {
                                    format.getInteger(android.media.MediaFormat.KEY_FRAME_RATE).toDouble()
                                } catch (_: Throwable) {
                                    0.0
                                }
                            }
                            if (fps > 0.0) out["fps"] = fps
                        }
                        if (format.containsKey(android.media.MediaFormat.KEY_BIT_RATE)) {
                            try {
                                val br = format.getInteger(android.media.MediaFormat.KEY_BIT_RATE)
                                if (br > 0) out["bitrate"] = br
                            } catch (_: Throwable) {}
                        }
                        if (format.containsKey(android.media.MediaFormat.KEY_WIDTH) &&
                            format.containsKey(android.media.MediaFormat.KEY_HEIGHT)
                        ) {
                            val w = format.getInteger(android.media.MediaFormat.KEY_WIDTH)
                            val h = format.getInteger(android.media.MediaFormat.KEY_HEIGHT)
                            val rot = if (format.containsKey("rotation-degrees")) {
                                try { format.getInteger("rotation-degrees") } catch (_: Throwable) { 0 }
                            } else 0
                            if (w > 0 && h > 0) {
                                if (rot == 90 || rot == 270) {
                                    out["width"] = h
                                    out["height"] = w
                                } else {
                                    out["width"] = w
                                    out["height"] = h
                                }
                            }
                        }
                    } else if (!gotAudio && mime.startsWith("audio/")) {
                        gotAudio = true
                        out["audioCodec"] = mime
                        if (format.containsKey(android.media.MediaFormat.KEY_CHANNEL_COUNT)) {
                            try {
                                val ch = format.getInteger(android.media.MediaFormat.KEY_CHANNEL_COUNT)
                                if (ch > 0) out["audioChannels"] = ch
                            } catch (_: Throwable) {}
                        }
                        if (format.containsKey(android.media.MediaFormat.KEY_SAMPLE_RATE)) {
                            try {
                                val sr = format.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE)
                                if (sr > 0) out["audioSampleRate"] = sr
                            } catch (_: Throwable) {}
                        }
                    }
                    if (gotVideo && gotAudio) break
                }
            }
        } catch (_: Throwable) {
        } finally {
            try { extractor.release() } catch (_: Throwable) {}
            try { extPfd?.close() } catch (_: Throwable) {}
            try { extFis?.close() } catch (_: Throwable) {}
        }

        // 2. MediaMetadataRetriever for total bitrate & FPS/dimension fallbacks.
        val retriever = android.media.MediaMetadataRetriever()
        var retPfd: android.os.ParcelFileDescriptor? = null
        var retFis: java.io.FileInputStream? = null
        try {
            var sourceSet = false
            if (file != null && file.exists() && file.canRead()) {
                try {
                    retriever.setDataSource(file.absolutePath)
                    sourceSet = true
                } catch (_: Throwable) {
                    try {
                        retFis = java.io.FileInputStream(file)
                        retriever.setDataSource(retFis.fd)
                        sourceSet = true
                    } catch (_: Throwable) {}
                }
            }
            if (!sourceSet && uri != null) {
                try {
                    retPfd = contentResolver.openFileDescriptor(uri, "r")
                    if (retPfd != null) {
                        retriever.setDataSource(retPfd.fileDescriptor)
                        sourceSet = true
                    }
                } catch (_: Throwable) {
                    try {
                        retriever.setDataSource(applicationContext, uri)
                        sourceSet = true
                    } catch (_: Throwable) {}
                }
            }

            if (sourceSet) {
                val totalBitrate = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE
                )?.toIntOrNull()
                if (totalBitrate != null && totalBitrate > 0) {
                    out["bitrate"] = totalBitrate
                }

                val durationMs = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L

                if (!out.containsKey("fps") && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val capFps = retriever.extractMetadata(
                        android.media.MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE
                    )?.toDoubleOrNull()
                    if (capFps != null && capFps > 0.0) {
                        out["fps"] = capFps
                    }
                }

                if (!out.containsKey("fps") && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && durationMs > 0L) {
                    val frameCount = retriever.extractMetadata(
                        android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT
                    )?.toDoubleOrNull()
                    if (frameCount != null && frameCount > 0.0) {
                        val computedFps = frameCount / (durationMs / 1000.0)
                        if (computedFps in 1.0..480.0) {
                            out["fps"] = computedFps
                        }
                    }
                }

                if (!out.containsKey("width") || !out.containsKey("height")) {
                    val w = retriever.extractMetadata(
                        android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
                    )?.toIntOrNull() ?: 0
                    val h = retriever.extractMetadata(
                        android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
                    )?.toIntOrNull() ?: 0
                    val rot = retriever.extractMetadata(
                        android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
                    )?.toIntOrNull() ?: 0
                    if (w > 0 && h > 0) {
                        if (rot == 90 || rot == 270) {
                            out["width"] = h
                            out["height"] = w
                        } else {
                            out["width"] = w
                            out["height"] = h
                        }
                    }
                }
            }
        } catch (_: Throwable) {
        } finally {
            try { retriever.release() } catch (_: Throwable) {}
            try { retPfd?.close() } catch (_: Throwable) {}
            try { retFis?.close() } catch (_: Throwable) {}
        }

        return out
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

    private fun canAuthenticateDevice(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val bm = getSystemService(android.hardware.biometrics.BiometricManager::class.java)
                val status = bm?.canAuthenticate(
                    android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
                if (status == android.hardware.biometrics.BiometricManager.BIOMETRIC_SUCCESS) {
                    return true
                }
            } catch (_: Throwable) {}
            val km = getSystemService(android.app.KeyguardManager::class.java)
            return km?.isDeviceSecure == true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val km = getSystemService(android.app.KeyguardManager::class.java)
            return km?.isDeviceSecure == true
        }
        val km = getSystemService(android.content.Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        @Suppress("DEPRECATION")
        return km?.isKeyguardSecure == true
    }

    private fun finishAppLock(success: Boolean) {
        val res = pendingAppLockResult ?: return
        pendingAppLockResult = null
        runOnUiThread {
            res.success(success)
        }
    }

    private fun authenticateDevice(
        title: String,
        subtitle: String,
        result: MethodChannel.Result
    ) {
        if (pendingAppLockResult != null) {
            result.error("BUSY", "Authentication is already in progress", null)
            return
        }
        pendingAppLockResult = result

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val builder = android.hardware.biometrics.BiometricPrompt.Builder(this)
                    .setTitle(title)
                if (subtitle.isNotEmpty()) {
                    builder.setSubtitle(subtitle)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    builder.setAllowedAuthenticators(
                        android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_WEAK or
                            android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    )
                } else {
                    @Suppress("DEPRECATION")
                    builder.setDeviceCredentialAllowed(true)
                }
                val prompt = builder.build()
                val cancellationSignal = android.os.CancellationSignal()
                prompt.authenticate(
                    cancellationSignal,
                    mainExecutor,
                    object : android.hardware.biometrics.BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(
                            authResult: android.hardware.biometrics.BiometricPrompt.AuthenticationResult
                        ) {
                            finishAppLock(true)
                        }

                        override fun onAuthenticationError(
                            errorCode: Int,
                            errString: CharSequence
                        ) {
                            finishAppLock(false)
                        }

                        override fun onAuthenticationFailed() {
                            // Ignored: user may retry; onAuthenticationError fires on cancel/lockout.
                        }
                    }
                )
                return
            } catch (_: Throwable) {
                // Fall through to KeyguardManager credential intent fallback.
            }
        }

        try {
            val km = getSystemService(android.content.Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
            @Suppress("DEPRECATION")
            val intent = km?.createConfirmDeviceCredentialIntent(title, subtitle)
            if (intent != null) {
                startActivityForResult(intent, REQUEST_CODE_APP_LOCK)
            } else {
                finishAppLock(false)
            }
        } catch (_: Throwable) {
            finishAppLock(false)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_FOLDER) {
            val result = pendingFolderPickerResult ?: return
            pendingFolderPickerResult = null
            if (resultCode == Activity.RESULT_OK && data != null && data.data != null) {
                val uri = data.data!!
                try {
                    val docId = DocumentsContract.getTreeDocumentId(uri)
                    val split = docId.split(":")
                    val type = split[0]
                    val relPath = if (split.size > 1) split[1] else ""
                    val path = if ("primary".equals(type, ignoreCase = true)) {
                        if (relPath.isNotEmpty()) "/storage/emulated/0/$relPath" else "/storage/emulated/0"
                    } else {
                        if (relPath.isNotEmpty()) "/storage/$type/$relPath" else "/storage/$type"
                    }
                    result.success(path)
                } catch (e: Exception) {
                    result.error("PARSE_FAILED", e.message, null)
                }
            } else {
                result.success(null)
            }
        } else if (requestCode == REQUEST_CODE_APP_LOCK) {
            finishAppLock(resultCode == Activity.RESULT_OK)
        }
    }
}
