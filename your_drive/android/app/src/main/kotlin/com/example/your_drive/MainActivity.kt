package com.example.your_drive

import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "saf_upload_channel"
    private var pendingResult: MethodChannel.Result? = null

    // 📂 MULTI-FILE SAF picker launcher  ✅ FIXED
    private val pickFilesLauncher =
        registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris: List<Uri> ->

            if (uris.isEmpty()) {
                pendingResult?.error("NO_FILE", "No file selected", null)
                pendingResult = null
                return@registerForActivityResult
            }

            try {
                val files = uris.map { uri ->
                    hashMapOf(
                        "uri" to uri.toString(),
                        "name" to getFileName(uri),
                        "size" to getFileSize(uri)
                    )
                }

                pendingResult?.success(files)

            } catch (e: Exception) {
                pendingResult?.error("READ_ERROR", e.message, null)
            }

            pendingResult = null
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // 🔹 Open MULTI SAF picker  ✅ FIXED
                "pickFilesSaf" -> {
                    pendingResult = result
                    pickFilesLauncher.launch(arrayOf("*/*"))
                }

                // 🔹 Read chunk from SAF stream (for future streaming upload)
                "readSafChunk" -> {
                    val uriString = call.argument<String>("uri")!!
                    val offset = call.argument<Int>("offset")!!
                    val length = call.argument<Int>("length")!!

                    try {
                        val uri = Uri.parse(uriString)
                        val inputStream: InputStream =
                            contentResolver.openInputStream(uri)!!

                        inputStream.skip(offset.toLong())

                        val buffer = ByteArray(length)
                        val read = inputStream.read(buffer)

                        inputStream.close()

                        if (read <= 0) {
                            result.success(null)
                        } else {
                            result.success(buffer.copyOf(read))
                        }

                    } catch (e: Exception) {
                        result.error("STREAM_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // 📄 Get file name
    private fun getFileName(uri: Uri): String {
        val cursor = contentResolver.query(uri, null, null, null, null)
        cursor?.use {
            val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (it.moveToFirst()) return it.getString(index)
        }
        return "unknown_file"
    }

    // 📏 Get file size
    private fun getFileSize(uri: Uri): Long {
        val cursor = contentResolver.query(uri, null, null, null, null)
        cursor?.use {
            val index = it.getColumnIndex(OpenableColumns.SIZE)
            if (it.moveToFirst()) return it.getLong(index)
        }
        return 0L
    }
}
