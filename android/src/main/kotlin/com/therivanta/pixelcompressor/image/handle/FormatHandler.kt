package com.therivanta.pixelcompressor.image.handle

import android.content.Context
import com.therivanta.pixelcompressor.image.ext.ResizeSpec
import java.io.OutputStream

interface FormatHandler {

  val type: Int

  val typeName: String

  fun handleByteArray(context: Context, byteArray: ByteArray, outputStream: OutputStream, minWidth: Int, minHeight: Int, quality: Int, rotate: Int, keepExif: Boolean, inSampleSize: Int, resize: ResizeSpec = ResizeSpec.NONE)

  fun handleFile(context: Context, path: String, outputStream: OutputStream, minWidth: Int, minHeight: Int, quality: Int, rotate: Int, keepExif: Boolean, inSampleSize: Int, numberOfRetries: Int, resize: ResizeSpec = ResizeSpec.NONE)
}