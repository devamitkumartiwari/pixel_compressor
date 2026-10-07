package com.therivanta.pixelcompressor.image.logger

import android.util.Log
import com.therivanta.pixelcompressor.image.ImageCompressHandler

fun log(any: Any?) {
  if (ImageCompressHandler.showLog) {
    Log.i("pixel_compressor", any?.toString() ?: "null")
  }
}
