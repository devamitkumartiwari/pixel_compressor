package com.therivanta.pixelcompressor.video

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import android.view.Surface
import com.therivanta.pixelcompressor.errors.PixelCompressorErrors
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Minimal EGL/GLES helper for the decode-to-encode video scaling pipeline
 * (standard "bigflake"/Grafika pattern: decoder writes into a
 * `SurfaceTexture`-backed external-OES texture, a full-screen textured
 * quad renders that texture into the encoder's input `Surface`, letting
 * the GPU do the resolution scaling via `glViewport`).
 */
internal class EglCore {
  private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
  private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
  private var eglConfig: EGLConfig? = null

  init {
    eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
      throw PixelCompressorErrors.encodingError("Unable to get EGL14 display")
    }
    val version = IntArray(2)
    if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
      throw PixelCompressorErrors.encodingError("Unable to initialize EGL14")
    }
    val attribList = intArrayOf(
      EGL14.EGL_RED_SIZE, 8,
      EGL14.EGL_GREEN_SIZE, 8,
      EGL14.EGL_BLUE_SIZE, 8,
      EGL14.EGL_ALPHA_SIZE, 8,
      EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
      EGLExt.EGL_RECORDABLE_ANDROID, 1,
      EGL14.EGL_NONE,
    )
    val configs = arrayOfNulls<EGLConfig>(1)
    val numConfigs = IntArray(1)
    if (!EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, 1, numConfigs, 0)) {
      throw PixelCompressorErrors.encodingError("Unable to find a suitable EGLConfig")
    }
    eglConfig = configs[0]
    val contextAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
    eglContext = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
    if (eglContext == EGL14.EGL_NO_CONTEXT) {
      throw PixelCompressorErrors.encodingError("Unable to create EGL context")
    }
  }

  fun createWindowSurface(surface: Surface): EGLSurface {
    val attribs = intArrayOf(EGL14.EGL_NONE)
    val eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, eglConfig, surface, attribs, 0)
    if (eglSurface == EGL14.EGL_NO_SURFACE) {
      throw PixelCompressorErrors.encodingError("Unable to create EGL window surface")
    }
    return eglSurface
  }

  fun makeCurrent(eglSurface: EGLSurface) {
    if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
      throw PixelCompressorErrors.encodingError("eglMakeCurrent failed")
    }
  }

  fun setPresentationTime(eglSurface: EGLSurface, nanoseconds: Long) {
    EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, nanoseconds)
  }

  fun swapBuffers(eglSurface: EGLSurface): Boolean = EGL14.eglSwapBuffers(eglDisplay, eglSurface)

  fun releaseSurface(eglSurface: EGLSurface) {
    EGL14.eglDestroySurface(eglDisplay, eglSurface)
  }

  fun release() {
    if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
      EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
      EGL14.eglDestroyContext(eglDisplay, eglContext)
      EGL14.eglReleaseThread()
      EGL14.eglTerminate(eglDisplay)
    }
    eglDisplay = EGL14.EGL_NO_DISPLAY
    eglContext = EGL14.EGL_NO_CONTEXT
  }
}

/** Wraps an EGL window surface bound to an encoder's input [Surface] or a
 * decoder's [SurfaceTexture]-backed output surface.
 */
internal class WindowSurface(private val eglCore: EglCore, surface: Surface) {
  private val eglSurface: EGLSurface = eglCore.createWindowSurface(surface)

  fun makeCurrent() = eglCore.makeCurrent(eglSurface)

  fun setPresentationTime(nanoseconds: Long) = eglCore.setPresentationTime(eglSurface, nanoseconds)

  fun swapBuffers(): Boolean = eglCore.swapBuffers(eglSurface)

  fun release() = eglCore.releaseSurface(eglSurface)
}

/** Renders frames latched from an external-OES [SurfaceTexture] (the
 * decoder's output) into whatever EGL surface is currently current (the
 * encoder's input surface), scaling via `glViewport`.
 */
internal class TextureRenderer {
  private var program = 0
  private var textureId = -1
  private val vertexBuffer: FloatBuffer
  private val texCoordBuffer: FloatBuffer
  private val texMatrix = FloatArray(16)

  companion object {
    private val QUAD_COORDS = floatArrayOf(
      -1f, -1f,
      1f, -1f,
      -1f, 1f,
      1f, 1f,
    )
    private val QUAD_TEX_COORDS = floatArrayOf(
      0f, 0f,
      1f, 0f,
      0f, 1f,
      1f, 1f,
    )

    /**
     * Rigid rotation applied to [aPosition] (not the texture coordinates),
     * so it rotates the already-correctly-sampled frame as a whole rather
     * than depending on [SurfaceTexture]'s own flip/crop transform.
     * Combined with swapping the encoder's target width/height for 90/270
     * (done by the caller), this bakes the source's rotation hint directly
     * into the encoded pixels instead of leaving it as an MP4
     * orientation-hint for the player to apply.
     *
     * The 90/270 cases are each other's matrix inverse by construction
     * (composing them yields identity) — confirmed field-reported (~2,000
     * users) that portrait video came out rotated the wrong way at exactly
     * these two angles and correct at 180 (where the two directions
     * coincide, since 180° is self-inverse). That signature — wrong at
     * 90/270, fine at 0/180 — is the fingerprint of the two cases being
     * swapped relative to what's needed, so they're swapped here relative
     * to the original version of this function. This does not depend on
     * assumptions about [SurfaceTexture]'s own transform, since that
     * matrix is applied independently to the texture coordinate and is
     * unaffected by which of these two matrices is labeled 90 vs 270.
     *
     * MUST be verified on a real device against actual 90/180/270
     * source-rotation-metadata test videos (including a front-camera
     * clip) before shipping — this is not the kind of bug a code read
     * alone can fully certify.
     */
    fun rotationMatrixForDegrees(degrees: Int): FloatArray = when (((degrees % 360) + 360) % 360) {
      90 -> floatArrayOf(0f, 1f, 0f, 0f, -1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f)
      180 -> floatArrayOf(-1f, 0f, 0f, 0f, 0f, -1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f)
      270 -> floatArrayOf(0f, -1f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f)
      else -> FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    }

    private const val VERTEX_SHADER = """
      attribute vec4 aPosition;
      attribute vec4 aTextureCoord;
      uniform mat4 uTexMatrix;
      uniform mat4 uPositionMatrix;
      varying vec2 vTextureCoord;
      void main() {
        gl_Position = uPositionMatrix * aPosition;
        vTextureCoord = (uTexMatrix * aTextureCoord).xy;
      }
    """
    private const val FRAGMENT_SHADER = """
      #extension GL_OES_EGL_image_external : require
      precision mediump float;
      varying vec2 vTextureCoord;
      uniform samplerExternalOES sTexture;
      void main() {
        gl_FragColor = texture2D(sTexture, vTextureCoord);
      }
    """
  }

  init {
    vertexBuffer = ByteBuffer.allocateDirect(QUAD_COORDS.size * 4)
      .order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(QUAD_COORDS); position(0) }
    texCoordBuffer = ByteBuffer.allocateDirect(QUAD_TEX_COORDS.size * 4)
      .order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(QUAD_TEX_COORDS); position(0) }
    program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
    textureId = createExternalOesTexture()
  }

  val externalTextureId: Int get() = textureId

  fun drawFrame(surfaceTexture: SurfaceTexture, viewportWidth: Int, viewportHeight: Int, rotationDegrees: Int = 0) {
    surfaceTexture.getTransformMatrix(texMatrix)
    GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
    GLES20.glClearColor(0f, 0f, 0f, 1f)
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
    GLES20.glUseProgram(program)
    checkGlError("glUseProgram")

    GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)

    val positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
    GLES20.glEnableVertexAttribArray(positionHandle)
    GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 0, vertexBuffer)

    val texCoordHandle = GLES20.glGetAttribLocation(program, "aTextureCoord")
    GLES20.glEnableVertexAttribArray(texCoordHandle)
    GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 0, texCoordBuffer)

    val matrixHandle = GLES20.glGetUniformLocation(program, "uTexMatrix")
    GLES20.glUniformMatrix4fv(matrixHandle, 1, false, texMatrix, 0)

    val positionMatrixHandle = GLES20.glGetUniformLocation(program, "uPositionMatrix")
    GLES20.glUniformMatrix4fv(positionMatrixHandle, 1, false, rotationMatrixForDegrees(rotationDegrees), 0)

    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    checkGlError("glDrawArrays")

    GLES20.glDisableVertexAttribArray(positionHandle)
    GLES20.glDisableVertexAttribArray(texCoordHandle)
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
  }

  private fun createExternalOesTexture(): Int {
    val textures = IntArray(1)
    GLES20.glGenTextures(1, textures, 0)
    val texId = textures[0]
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texId)
    GLES20.glTexParameteri(
      GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
      GLES20.GL_TEXTURE_MIN_FILTER,
      GLES20.GL_LINEAR,
    )
    GLES20.glTexParameteri(
      GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
      GLES20.GL_TEXTURE_MAG_FILTER,
      GLES20.GL_LINEAR,
    )
    GLES20.glTexParameteri(
      GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
      GLES20.GL_TEXTURE_WRAP_S,
      GLES20.GL_CLAMP_TO_EDGE,
    )
    GLES20.glTexParameteri(
      GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
      GLES20.GL_TEXTURE_WRAP_T,
      GLES20.GL_CLAMP_TO_EDGE,
    )
    return texId
  }

  private fun createProgram(vertexSource: String, fragmentSource: String): Int {
    val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexSource)
    val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
    val newProgram = GLES20.glCreateProgram()
    if (newProgram == 0) throw PixelCompressorErrors.encodingError("Could not create GL program")
    GLES20.glAttachShader(newProgram, vertexShader)
    GLES20.glAttachShader(newProgram, fragmentShader)
    GLES20.glLinkProgram(newProgram)
    val linkStatus = IntArray(1)
    GLES20.glGetProgramiv(newProgram, GLES20.GL_LINK_STATUS, linkStatus, 0)
    if (linkStatus[0] != GLES20.GL_TRUE) {
      val log = GLES20.glGetProgramInfoLog(newProgram)
      GLES20.glDeleteProgram(newProgram)
      throw PixelCompressorErrors.encodingError("Could not link GL program: $log")
    }
    return newProgram
  }

  private fun loadShader(type: Int, source: String): Int {
    val shader = GLES20.glCreateShader(type)
    GLES20.glShaderSource(shader, source)
    GLES20.glCompileShader(shader)
    val compiled = IntArray(1)
    GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
    if (compiled[0] == 0) {
      val log = GLES20.glGetShaderInfoLog(shader)
      GLES20.glDeleteShader(shader)
      throw PixelCompressorErrors.encodingError("Could not compile shader $type: $log")
    }
    return shader
  }

  private fun checkGlError(op: String) {
    val error = GLES20.glGetError()
    if (error != GLES20.GL_NO_ERROR) {
      throw PixelCompressorErrors.encodingError("$op: GL error 0x${Integer.toHexString(error)}")
    }
  }
}
