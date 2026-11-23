package me.jxl.kiosk_satellite

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenterResult
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Vision for the Kids Portal's camera games, built for speed rather than
 * for the power budget the gesture and screensaver legs live on: every
 * frame the camera delivers is offered, turned upright and mirrored the
 * way the child sees themself, to
 *
 *  - a hand landmarker that follows up to two hands and reports each
 *    one's palm, finger count and all 21 points (for the glowing hand
 *    drawn over the game), and
 *  - a selfie segmenter that reports the body as a small mask (for the
 *    glowing outline of the child the game sees).
 *
 * Both run in MediaPipe's live-stream mode on their own threads and drop
 * frames while busy, so the analyzer never waits on them and a result is
 * always about the newest frame. Results are emitted as soon as they are
 * ready. Only runs while a game asks for it; nothing is stored or sent.
 */
class GameVision(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "GameVision"
        private const val HAND_MODEL = "hand_landmarker.task"
        private const val BODY_MODEL = "selfie_segmenter.tflite"

        /** The longer side the frame is scaled to before the models see
         *  it: the hand model looks at 192-224 pixel inputs, the body
         *  model at 256, so more only costs the conversion. */
        private const val WORK_SIDE = 320

        /** The body mask as sent to the app: this many cells across. */
        const val MASK_WIDTH = 96
    }

    private var hands: HandLandmarker? = null
    private var body: ImageSegmenter? = null
    private var handsFailed = false
    private var bodyFailed = false
    private val handBusy = AtomicBoolean(false)
    private val bodyBusy = AtomicBoolean(false)
    private var lastTsMs = 0L
    private var aspect = 0.75f
    private var handResults = 0
    private var bodyResults = 0
    private var handFeedNs = 0L
    private var bodyFeedNs = 0L
    private var handAvgMs = 0f
    private var bodyAvgMs = 0f

    /** Offer one frame. [front]: mirror it, as a front camera's picture is
     *  the mirror of what faces it. */
    fun offer(image: ImageProxy, rotation: Int, front: Boolean, wantHands: Boolean, wantBody: Boolean) {
        val needHands = wantHands && !handsFailed && !handBusy.get()
        val needBody = wantBody && !bodyFailed && !bodyBusy.get()
        if (!needHands && !needBody) return
        val frame = try {
            upright(image, rotation, front)
        } catch (e: Exception) {
            Log.w(TAG, "frame conversion failed: $e")
            return
        }
        aspect = frame.height.toFloat() / frame.width
        // MediaPipe wants strictly increasing timestamps per task.
        val ts = max(SystemClock.uptimeMillis(), lastTsMs + 1)
        lastTsMs = ts
        val now = System.nanoTime()
        if (needHands) {
            val task = hands ?: loadHands()
            if (task != null && handBusy.compareAndSet(false, true)) {
                try {
                    handFeedNs = now
                    task.detectAsync(BitmapImageBuilder(frame).build(), ts)
                } catch (e: Exception) {
                    handBusy.set(false)
                    Log.w(TAG, "hand feed failed: $e")
                }
            }
        }
        if (needBody) {
            val task = body ?: loadBody()
            if (task != null && bodyBusy.compareAndSet(false, true)) {
                try {
                    bodyFeedNs = now
                    task.segmentAsync(BitmapImageBuilder(frame).build(), ts)
                } catch (e: Exception) {
                    bodyBusy.set(false)
                    Log.w(TAG, "body feed failed: $e")
                }
            }
        }
    }

    /** The frame upright, mirrored for a front camera, scaled down. */
    private fun upright(image: ImageProxy, rotation: Int, front: Boolean): Bitmap {
        val src = image.toBitmap()
        val turned = rotation == 90 || rotation == 270
        val w = if (turned) src.height else src.width
        val h = if (turned) src.width else src.height
        val scale = min(1f, WORK_SIDE.toFloat() / max(w, h))
        val m = Matrix()
        m.postRotate(rotation.toFloat())
        if (front) m.postScale(-1f, 1f)
        m.postScale(scale, scale)
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
    }

    private fun onHands(result: HandLandmarkerResult) {
        handBusy.set(false)
        val ms = (System.nanoTime() - handFeedNs) / 1_000_000f
        handResults++
        handAvgMs += (ms - handAvgMs) / min(handResults, 30).toFloat()
        if (handResults == 1 || handResults % 300 == 0) Log.i(TAG, "hands: ${"%.0f".format(handAvgMs)} ms a look")
        val out = ArrayList<Map<String, Any?>>(2)
        for (h in result.landmarks()) {
            if (h.size < 21) continue
            val pts = FloatArray(42)
            for (i in 0 until 21) {
                pts[i * 2] = h[i].x()
                pts[i * 2 + 1] = h[i].y()
            }
            val read = readHand({ i -> h[i].x() }, { i -> h[i].y() * aspect })
            val palm = intArrayOf(0, 5, 9, 13, 17)
            val px = palm.map { h[it].x() }.average().toFloat()
            val py = palm.map { h[it].y() }.average().toFloat()
            out.add(mapOf("x" to px.toDouble(), "y" to py.toDouble(), "f" to read.fingers, "lm" to pts))
        }
        emit(mapOf("ghands" to out, "aspect" to aspect.toDouble(), "ms" to handAvgMs.toDouble()))
    }

    private fun onBody(result: ImageSegmenterResult) {
        bodyBusy.set(false)
        val ms = (System.nanoTime() - bodyFeedNs) / 1_000_000f
        bodyResults++
        bodyAvgMs += (ms - bodyAvgMs) / min(bodyResults, 30).toFloat()
        if (bodyResults == 1 || bodyResults % 300 == 0) Log.i(TAG, "body: ${"%.0f".format(bodyAvgMs)} ms a look")
        try {
            val masks = result.confidenceMasks()
            if (!masks.isPresent || masks.get().isEmpty()) return
            val mask = masks.get()[0]
            val mw = mask.width
            val mh = mask.height
            val buf = ByteBufferExtractor.extract(mask).order(ByteOrder.nativeOrder()).asFloatBuffer()
            val ow = MASK_WIDTH
            val oh = max(1, (MASK_WIDTH * mh.toFloat() / mw).roundToInt())
            val cells = ByteArray(ow * oh)
            for (y in 0 until oh) {
                val sy = min(mh - 1, ((y + 0.5f) * mh / oh).toInt())
                for (x in 0 until ow) {
                    val sx = min(mw - 1, ((x + 0.5f) * mw / ow).toInt())
                    val v = buf.get(sy * mw + sx).coerceIn(0f, 1f)
                    cells[y * ow + x] = (v * 255f).roundToInt().toByte()
                }
            }
            emit(mapOf("body" to cells, "bw" to ow, "bh" to oh))
        } catch (e: Exception) {
            Log.w(TAG, "body mask failed: $e")
        }
    }

    private fun loadHands(): HandLandmarker? {
        if (handsFailed) return null
        return try {
            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath(HAND_MODEL).setDelegate(Delegate.CPU).build())
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.4f)
                .setMinHandPresenceConfidence(0.4f)
                .setMinTrackingConfidence(0.4f)
                .setResultListener { result, _ -> onHands(result) }
                .setErrorListener { e ->
                    handBusy.set(false)
                    Log.w(TAG, "hand landmarker error: $e")
                }
                .build()
            HandLandmarker.createFromOptions(context, options).also {
                hands = it
                Log.i(TAG, "game hands loaded (two hands)")
            }
        } catch (e: Throwable) {
            handsFailed = true
            Log.e(TAG, "game hands unavailable: $e", e)
            null
        }
    }

    private fun loadBody(): ImageSegmenter? {
        if (bodyFailed) return null
        return try {
            val options = ImageSegmenter.ImageSegmenterOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath(BODY_MODEL).setDelegate(Delegate.CPU).build())
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setOutputConfidenceMasks(true)
                .setOutputCategoryMask(false)
                .setResultListener { result, _ -> onBody(result) }
                .setErrorListener { e ->
                    bodyBusy.set(false)
                    Log.w(TAG, "body segmenter error: $e")
                }
                .build()
            ImageSegmenter.createFromOptions(context, options).also {
                body = it
                Log.i(TAG, "game body segmenter loaded")
            }
        } catch (e: Throwable) {
            bodyFailed = true
            Log.e(TAG, "body segmenter unavailable: $e", e)
            null
        }
    }

    fun close() {
        try { hands?.close() } catch (_: Exception) {}
        try { body?.close() } catch (_: Exception) {}
        hands = null
        body = null
        handBusy.set(false)
        bodyBusy.set(false)
    }
}
