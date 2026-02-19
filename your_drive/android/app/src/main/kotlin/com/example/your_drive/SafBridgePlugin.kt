package com.example.your_drive

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

class SafBridgePlugin: FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    
    private lateinit var channel : MethodChannel
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "saf_bridge")
        channel.setMethodCallHandler(this)
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pickFiles" -> openSafPicker(result)
            "getFileInfo" -> getFileInfo(call, result)
            "readFileBytes" -> readFileBytes(call, result)  // ⭐ ADDED
            else -> result.notImplemented()
        }
    }
    
    private fun openSafPicker(result: Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.type = "*/*"
        
        // ⭐ enable MULTIPLE selection
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        
        pendingResult = result
        activity?.startActivityForResult(intent, 9999)
    }
    
    private fun getFileInfo(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: return result.error("NO_URI", "URI missing", null)
        val uri = Uri.parse(uriString)
        
        val cursor = activity?.contentResolver?.query(uri, null, null, null, null)
        cursor?.use {
            val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
            
            it.moveToFirst()
            val name = it.getString(nameIndex)
            val size = it.getLong(sizeIndex)
            
            result.success(mapOf("name" to name, "size" to size))
        } ?: result.error("QUERY_FAIL", "Cannot read file info", null)
    }
    
    // ⭐ NEW METHOD - Read file bytes from SAF URI
    private fun readFileBytes(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: return result.error("NO_URI", "URI missing", null)
        val uri = Uri.parse(uriString)
        
        try {
            val inputStream = activity?.contentResolver?.openInputStream(uri)
            val bytes = inputStream?.readBytes()
            inputStream?.close()
            
            if (bytes != null) {
                result.success(bytes)
            } else {
                result.error("READ_FAIL", "Cannot read file", null)
            }
        } catch (e: Exception) {
            result.error("READ_ERROR", e.message, null)
        }
    }
    
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        
        binding.addActivityResultListener { requestCode, resultCode, data ->
            
            if (requestCode == 9999) {
                if (resultCode == Activity.RESULT_OK) {
                    val uris = mutableListOf<String>()
                    
                    // ⭐ FIX: Check clipData first (multiple files)
                    data?.clipData?.let { clip ->
                        for (i in 0 until clip.itemCount) {
                            uris.add(clip.getItemAt(i).uri.toString())
                        }
                    } ?: run {
                        // Fallback to single file
                        data?.data?.let { uris.add(it.toString()) }
                    }
                    
                    pendingResult?.success(uris)
                    pendingResult = null
                } else {
                    // User cancelled
                    pendingResult?.success(emptyList<String>())
                    pendingResult = null
                }
                return@addActivityResultListener true
            }
            false
        }
    }
    
    override fun onDetachedFromActivity() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}