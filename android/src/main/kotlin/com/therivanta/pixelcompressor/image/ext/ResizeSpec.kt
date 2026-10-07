package com.therivanta.pixelcompressor.image.ext

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.max
import kotlin.math.min

/// Additions on top of min-bound scaling: `maxWidth`/`maxHeight` caps and an
/// exact output size. Sent as six trailing ints after the base arguments;
/// 0 = unset.
data class ResizeSpec(
    val maxWidth: Int = 0,
    val maxHeight: Int = 0,
    val exactWidth: Int = 0,
    val exactHeight: Int = 0,
    /// 0 = stretch, 1 = contain (pad), 2 = cover (crop).
    val fit: Int = 1,
    /// ARGB, used by contain.
    val padColor: Int = 0,
) {
    val hasExact: Boolean get() = exactWidth > 0 && exactHeight > 0

    /// Max bounds follow min bounds when EXIF says the image is rotated 90/270.
    fun swapMaxBounds(): ResizeSpec = copy(maxWidth = maxHeight, maxHeight = maxWidth)

    companion object {
        val NONE = ResizeSpec()

        fun fromArgs(args: List<Any?>, start: Int): ResizeSpec {
            fun int(i: Int) = (args.getOrNull(start + i) as? Number)?.toInt() ?: 0
            return ResizeSpec(int(0), int(1), int(2), int(3), int(4), int(5))
        }
    }
}

/// Scale divisor for this bitmap: the min-bound rule, then shrunk
/// further to fit [resize]'s max bounds. With an exact size, pre-scale so the
/// image just covers the target (in pre-rotation axes); [fitTo] does the rest.
fun Bitmap.calcScale(minWidth: Int, minHeight: Int, resize: ResizeSpec, rotate: Int): Float {
    if (resize.hasExact) {
        val quarterTurn = ((rotate % 360) + 360) % 180 == 90
        return if (quarterTurn) {
            calcScale(resize.exactHeight, resize.exactWidth)
        } else {
            calcScale(resize.exactWidth, resize.exactHeight)
        }
    }
    var scale = calcScale(minWidth, minHeight)
    if (resize.maxWidth > 0) scale = max(scale, width / resize.maxWidth.toFloat())
    if (resize.maxHeight > 0) scale = max(scale, height / resize.maxHeight.toFloat())
    return scale
}

/// Final exact-size pass, applied after rotation. Returns `this` when unset.
fun Bitmap.fitTo(resize: ResizeSpec): Bitmap {
    if (!resize.hasExact) return this
    val w = resize.exactWidth
    val h = resize.exactHeight
    if (width == w && height == h) return this
    val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(out)
    val sw = width.toFloat()
    val sh = height.toFloat()
    val dst = if (resize.fit == 0) {
        RectF(0f, 0f, w.toFloat(), h.toFloat())
    } else {
        val s = if (resize.fit == 1) min(w / sw, h / sh) else max(w / sw, h / sh)
        val dw = sw * s
        val dh = sh * s
        RectF((w - dw) / 2, (h - dh) / 2, (w + dw) / 2, (h + dh) / 2)
    }
    if (resize.fit == 1) canvas.drawColor(resize.padColor)
    canvas.drawBitmap(this, null, dst, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
    return out
}
