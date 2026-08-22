package com.therivanta.pixelcompressor.cache

import android.content.Context
import java.io.File
import java.util.UUID

/** The plugin-owned cache subtree kinds, each a subdirectory under
 * `context.cacheDir/pixel_compressor/`.
 */
enum class CacheKind(val dirName: String) {
  IMAGES("images"),
  VIDEOS("videos"),
  THUMBNAILS("thumbnails"),
}

/**
 * Manages the plugin's own cache subtree: `context.cacheDir/pixel_compressor/{images,videos,thumbnails}`.
 * Created lazily on first resolved path. `size()` sums every file
 * recursively (0 if the root doesn't exist yet); `clear()` deletes the
 * whole subtree and recreates an empty root.
 */
class CacheManager(private val context: Context) {

  private val root: File
    get() = File(context.cacheDir, "pixel_compressor")

  private fun dirFor(kind: CacheKind): File {
    val dir = File(root, kind.dirName)
    if (!dir.exists()) dir.mkdirs()
    return dir
  }

  /**
   * Resolves an output path for a new file of [kind] with the given
   * [extension] (no leading dot). Used when the request's `outputPath` is
   * null, i.e. the caller wants a cache-managed temp file.
   */
  fun resolveOutputPath(kind: CacheKind, extension: String): String {
    val dir = dirFor(kind)
    val name = "${UUID.randomUUID()}.$extension"
    return File(dir, name).absolutePath
  }

  fun size(): Long {
    if (!root.exists()) return 0L
    return root.walkTopDown().filter { it.isFile }.sumOf { it.length() }
  }

  fun clear() {
    if (root.exists()) {
      root.deleteRecursively()
    }
    root.mkdirs()
  }
}
