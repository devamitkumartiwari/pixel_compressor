package com.therivanta.pixelcompressor.video

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer

/// Moves an MP4's `moov` box in front of `mdat` ("fast start"), so the file
/// can be played while it downloads, without the ~400 KB of padding Media3's
/// streamable mode reserves. Chunk offsets (`stco` / `co64`) are shifted by
/// the size of the moved box. Leaves the file untouched when `moov` is
/// already first or the layout isn't understood.
internal object Mp4FastStart {
    private data class Box(val type: String, val start: Long, val size: Long)

    private val CONTAINERS = setOf("moov", "trak", "mdia", "minf", "stbl", "edts", "udta", "meta")

    /// Returns true when the file was rewritten.
    fun apply(file: File): Boolean {
        val boxes = RandomAccessFile(file, "r").use { topLevelBoxes(it) } ?: return false
        val moov = boxes.firstOrNull { it.type == "moov" } ?: return false
        val mdatIndex = boxes.indexOfFirst { it.type == "mdat" }
        if (mdatIndex < 0 || boxes.indexOf(moov) < mdatIndex) return false
        if (moov.size > Int.MAX_VALUE) return false

        val moovData = ByteArray(moov.size.toInt())
        RandomAccessFile(file, "r").use { it.seek(moov.start); it.readFully(moovData) }
        if (!shiftChunkOffsets(ByteBuffer.wrap(moovData), 0, moovData.size, moov.size)) return false

        val tmp = File(file.parentFile, "${file.name}.faststart")
        try {
            RandomAccessFile(file, "r").use { input ->
                RandomAccessFile(tmp, "rw").use { output ->
                    output.setLength(0)
                    val inChannel = input.channel
                    val outChannel = output.channel
                    fun copy(box: Box) {
                        var position = box.start
                        val end = box.start + box.size
                        while (position < end) {
                            position += inChannel.transferTo(position, end - position, outChannel)
                        }
                    }
                    var moovWritten = false
                    for (box in boxes) {
                        if (box.type == "moov") continue
                        if (box.type == "mdat" && !moovWritten) {
                            outChannel.write(ByteBuffer.wrap(moovData))
                            moovWritten = true
                        }
                        copy(box)
                    }
                }
            }
            if (!tmp.renameTo(file)) {
                tmp.copyTo(file, overwrite = true)
                tmp.delete()
            }
            return true
        } catch (e: Exception) {
            tmp.delete()
            return false
        }
    }

    private fun topLevelBoxes(file: RandomAccessFile): List<Box>? {
        val boxes = mutableListOf<Box>()
        val length = file.length()
        var position = 0L
        val header = ByteArray(16)
        while (position + 8 <= length) {
            file.seek(position)
            file.readFully(header, 0, 8)
            var size = ByteBuffer.wrap(header, 0, 4).int.toLong() and 0xFFFFFFFFL
            val type = String(header, 4, 4, Charsets.US_ASCII)
            if (size == 1L) {
                file.readFully(header, 8, 8)
                size = ByteBuffer.wrap(header, 8, 8).long
            } else if (size == 0L) {
                size = length - position
            }
            if (size < 8 || position + size > length) return null
            boxes.add(Box(type, position, size))
            position += size
        }
        return boxes
    }

    /// Adds [delta] to every chunk offset under [start, end).
    private fun shiftChunkOffsets(buffer: ByteBuffer, start: Int, end: Int, delta: Long): Boolean {
        var position = start
        while (position + 8 <= end) {
            val size = buffer.getInt(position).toLong() and 0xFFFFFFFFL
            val type = String(ByteArray(4) { buffer.get(position + 4 + it) }, Charsets.US_ASCII)
            if (size < 8 || position + size > end) return false
            val body = position + 8
            when (type) {
                "stco" -> {
                    val count = buffer.getInt(body + 4)
                    for (i in 0 until count) {
                        val at = body + 8 + i * 4
                        val shifted = (buffer.getInt(at).toLong() and 0xFFFFFFFFL) + delta
                        if (shifted > 0xFFFFFFFFL) return false // would need co64
                        buffer.putInt(at, shifted.toInt())
                    }
                }
                "co64" -> {
                    val count = buffer.getInt(body + 4)
                    for (i in 0 until count) {
                        val at = body + 8 + i * 8
                        buffer.putLong(at, buffer.getLong(at) + delta)
                    }
                }
                "meta" -> if (!shiftChunkOffsets(buffer, body + 4, (position + size).toInt(), delta)) return false
                in CONTAINERS -> if (!shiftChunkOffsets(buffer, body, (position + size).toInt(), delta)) return false
            }
            position += size.toInt()
        }
        return true
    }
}
