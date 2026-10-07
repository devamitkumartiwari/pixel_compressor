package com.therivanta.pixelcompressor.image

import android.content.Context
import com.therivanta.pixelcompressor.image.core.CompressFileHandler
import com.therivanta.pixelcompressor.image.core.CompressListHandler
import com.therivanta.pixelcompressor.image.format.FormatRegister
import com.therivanta.pixelcompressor.image.handle.common.CommonHandler
import com.therivanta.pixelcompressor.image.handle.heif.HeifHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class ImageCompressHandler(private val context: Context) : MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "pixel_compressor/image"

        var showLog = false
    }

    init {
        FormatRegister.registerFormat(CommonHandler(0)) // jpeg
        FormatRegister.registerFormat(CommonHandler(1)) // png
        FormatRegister.registerFormat(HeifHandler()) // heic / heif
        FormatRegister.registerFormat(CommonHandler(3)) // webp
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "showLog" -> result.success(handleLog(call))
            "compressWithList" -> CompressListHandler(call, result).handle(context)
            "compressWithFile" -> CompressFileHandler(call, result).handle(context)
            "compressWithFileAndGetFile" -> CompressFileHandler(call, result).handleGetFile(context)
            else -> result.notImplemented()
        }
    }

    private fun handleLog(call: MethodCall): Int {
        val arg = call.arguments<Boolean>()
        showLog = (arg == true)
        return 1
    }
}
