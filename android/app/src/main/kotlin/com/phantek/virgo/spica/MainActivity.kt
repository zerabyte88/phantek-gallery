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
