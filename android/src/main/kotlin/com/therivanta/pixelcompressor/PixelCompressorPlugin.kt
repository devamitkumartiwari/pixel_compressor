package com.therivanta.pixelcompressor

import com.therivanta.pixelcompressor.image.ImageCompressHandler
import com.therivanta.pixelcompressor.video.VideoCompressHandler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/// Single Flutter entry point. Registers the image channel and the video
/// channel.
class PixelCompressorPlugin : FlutterPlugin {
    private var imageChannel: MethodChannel? = null
    private var videoChannel: MethodChannel? = null
    private var videoHandler: VideoCompressHandler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext

        imageChannel = MethodChannel(binding.binaryMessenger, ImageCompressHandler.CHANNEL_NAME).also {
            it.setMethodCallHandler(ImageCompressHandler(context))
        }

        videoChannel = MethodChannel(binding.binaryMessenger, VideoCompressHandler.CHANNEL_NAME).also {
            val handler = VideoCompressHandler(context, it)
            it.setMethodCallHandler(handler)
            videoHandler = handler
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        imageChannel?.setMethodCallHandler(null)
        imageChannel = null
        videoHandler?.dispose()
        videoHandler = null
        videoChannel?.setMethodCallHandler(null)
        videoChannel = null
    }
}
