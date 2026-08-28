package com.clanai.clan_ai

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class MainActivity : FlutterActivity() {
    private companion object {
        private const val CHANNEL = "com.clanai.clan_ai/file_saver"
        private const val TAG = "FileSaver"
        private const val SAVE_REQUEST_CODE = 1001
    }

    private var pendingResult: Result? = null
    private var pendingContent: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            if (call.method == "saveFile") {
                handleSaveFile(call, result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun handleSaveFile(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, String>
        val filename = args?.get("filename")
        val base64Content = args?.get("content")
        val mimeType = args?.get("mimeType")

        if (filename == null || base64Content == null) {
            result.error("INVALID_ARGS", "Missing filename or content", null)
            return
        }

        try {
            pendingContent = android.util.Base64.decode(base64Content, android.util.Base64.DEFAULT)
            pendingResult = result

            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType ?: "text/plain"
                putExtra(Intent.EXTRA_TITLE, filename)
            }

            startActivityForResult(intent, SAVE_REQUEST_CODE)
        } catch (e: Exception) {
            Log.e(TAG, "Error preparing save", e)
            result.error("SAVE_ERROR", e.message, null)
            pendingResult = null
            pendingContent = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != SAVE_REQUEST_CODE) return

        if (resultCode == RESULT_OK && data?.data != null) {
            val uri = data.data!!
            val content = pendingContent
            pendingContent = null

            if (content != null && pendingResult != null) {
                try {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        out.write(content)
                    }
                    pendingResult!!.success(uri.toString())
                } catch (e: Exception) {
                    Log.e(TAG, "Error writing file", e)
                    pendingResult!!.error("WRITE_ERROR", e.message, null)
                } finally {
                    pendingResult = null
                }
            }
        } else {
            // User cancelled or error
            pendingResult?.success(null)
            pendingResult = null
            pendingContent = null
        }
    }
}
