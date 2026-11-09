package com.fundsapp.funds

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth for the fingerprint / PIN prompt.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "funds/downloads")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // Saving into Downloads without any storage permission needs Android 10+.
                        "supported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                        "save" -> result.success(
                            save(call.argument<String>("name")!!, call.argument<ByteArray>("bytes")!!)
                        )
                        "list" -> result.success(list(call.argument<String>("prefix")!!))
                        "delete" -> result.success(
                            contentResolver.delete(Uri.parse(call.argument<String>("uri")!!), null, null) > 0
                        )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("downloads", e.message, null)
                }
            }
    }

    /** Writes a file to Downloads/Funds. Files there stay if the app is uninstalled. */
    private fun save(name: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) throw IllegalStateException("Needs Android 10 or newer")
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/json")
            put(MediaStore.Downloads.RELATIVE_PATH, "Download/Funds")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create the file")
        resolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("Could not write the file")
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    /** This app's own files in Downloads/Funds whose name starts with [prefix], newest first. */
    private fun list(prefix: String): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val out = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Downloads._ID,
            MediaStore.Downloads.DISPLAY_NAME,
            MediaStore.Downloads.DATE_ADDED,
        )
        contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Downloads.RELATIVE_PATH} LIKE ? AND ${MediaStore.Downloads.DISPLAY_NAME} LIKE ?",
            arrayOf("Download/Funds%", "$prefix%"),
            "${MediaStore.Downloads.DATE_ADDED} DESC",
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Downloads._ID)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
            val dateCol = c.getColumnIndexOrThrow(MediaStore.Downloads.DATE_ADDED)
            while (c.moveToNext()) {
                val uri = Uri.withAppendedPath(MediaStore.Downloads.EXTERNAL_CONTENT_URI, c.getLong(idCol).toString())
                out.add(
                    mapOf(
                        "uri" to uri.toString(),
                        "name" to c.getString(nameCol),
                        "added" to c.getLong(dateCol),
                    )
                )
            }
        }
        return out
    }
}
