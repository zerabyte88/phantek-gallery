package com.phantek.virgo.spica

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private var pendingFolderPickerResult: MethodChannel.Result? = null
    private val REQUEST_CODE_PICK_FOLDER = 9921

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

        val executor = java.util.concurrent.Executors.newFixedThreadPool(4)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.phantek.gallery/thumbnail"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getVideoThumbnail") {
                val assetId = call.argument<String>("assetId")
                val path = call.argument<String>("path") ?: ""
                val size = call.argument<Int>("size") ?: 512
                if (path.isEmpty() && assetId == null) {
                    result.error("INVALID_ARGS", "Both path and assetId are null/empty", null)
                    return@setMethodCallHandler
                }
                executor.execute {
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
                val path = call.argument<String>("path")
                val size = call.argument<Int>("size") ?: 512
                if (path == null) {
                    result.error("INVALID_PATH", "Path is null", null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    try {
                        val bytes = extractImageThumbnail(path, size)
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
                if (path == null) {
                    result.error("INVALID_PATH", "Path is null", null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    try {
                        val bytes = extractVideoFrame(path, timeUs, width, height)
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

    private fun extractImageThumbnail(path: String, targetSize: Int): ByteArray? {
        val file = File(path)
        if (!file.exists() || !file.canRead()) return null

        var bitmap: android.graphics.Bitmap? = null
        val cleanPath = file.absolutePath
        val canonicalPath = try { file.canonicalPath } catch (_: Throwable) { cleanPath }

        // 1. Android Q+ (API 29+) MediaStore contentResolver.loadThumbnail (Fastest system cache)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val projection = arrayOf(android.provider.MediaStore.Images.Media._ID)
                var id: Long? = null
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
        if (bitmap == null) {
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
                        inPreferredConfig = android.graphics.Bitmap.Config.RGB_565
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
                            android.graphics.Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                        } else {
                            decoded
                        }

                        // Scale to target size if still significantly larger
                        val curMax = Math.max(rotated.width, rotated.height)
                        bitmap = if (curMax > targetSize * 1.5) {
                            val scale = targetSize.toFloat() / curMax.toFloat()
                            val dstW = Math.max(2, (rotated.width * scale).toInt())
                            val dstH = Math.max(2, (rotated.height * scale).toInt())
                            android.graphics.Bitmap.createScaledBitmap(rotated, dstW, dstH, true)
                        } else {
                            rotated
                        }
                    }
                }
            } catch (_: Throwable) {}
        }

        if (bitmap == null) return null

        val stream = java.io.ByteArrayOutputStream()
        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, stream)
        val bytes = stream.toByteArray()
        if (!bitmap.isRecycled) {
            bitmap.recycle()
        }
        return if (bytes.isNotEmpty()) bytes else null
    }

    private fun extractVideoThumbnail(path: String, assetId: String?, targetSize: Int): ByteArray? {
        var bitmap: android.graphics.Bitmap? = null
        val needHighRes = targetSize > 512

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

        // 1. Primary extractor: MediaMetadataRetriever (guarantees native aspect ratio, full resolution, accurate frames)
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

                val attempts = arrayOf(
                    Pair(-1L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC),
                    Pair(0L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC),
                    Pair(0L, android.media.MediaMetadataRetriever.OPTION_CLOSEST),
                    Pair(500000L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                )

                for (att in attempts) {
                    if (bitmap != null) break
                    try {
                        bitmap = retriever.getFrameAtTime(att.first, att.second)
                    } catch (_: Throwable) {}
                }

                // Correct rotation if needed (API 27+ getFrameAtTime may or may not apply rotation depending on OEM)
                if (bitmap != null && (rotation == 90 || rotation == 270)) {
                    // For 90 or 270 degree rotation, visual frame must be portrait (height >= width)
                    // If width > height, it was not rotated yet by the platform.
                    if (bitmap!!.width > bitmap!!.height) {
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

        // 2. Fallbacks if MediaMetadataRetriever failed to get a bitmap
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

    private fun extractVideoFrame(path: String, timeUs: Long, targetWidth: Int, targetHeight: Int): ByteArray? {
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
                try {
                    retriever.setDataSource(path)
                    dataSourceSet = true
                } catch (_: Throwable) {
                    return null
                }
            }

            val widthStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val heightStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotationStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            val origW = widthStr?.toIntOrNull() ?: 0
            val origH = heightStr?.toIntOrNull() ?: 0
            val rotation = rotationStr?.toIntOrNull() ?: 0

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

            // Prioritize OPTION_CLOSEST for accurate frame at requested timestamp,
            // followed by OPTION_CLOSEST_SYNC and OPTION_PREVIOUS_SYNC as fallbacks.
            val options = intArrayOf(
                android.media.MediaMetadataRetriever.OPTION_CLOSEST,
                android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                android.media.MediaMetadataRetriever.OPTION_PREVIOUS_SYNC
            )

            val safeTimeUs = timeUs.coerceAtLeast(0L)
            var bitmap: android.graphics.Bitmap? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                for (opt in options) {
                    if (bitmap != null) break
                    try {
                        bitmap = retriever.getScaledFrameAtTime(safeTimeUs, opt, dstW, dstH)
                    } catch (_: Throwable) {}
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
                    } catch (_: Throwable) {}
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
        } finally {
            try { retriever.release() } catch (_: Throwable) {}
            try { fis?.close() } catch (_: Throwable) {}
            try { pfd?.close() } catch (_: Throwable) {}
        }
        return null
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
        }
    }
}
