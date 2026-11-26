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
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
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
        private const val POSE_MODEL = "pose_landmarker_lite.task"

        /** Looking for someone too far away to be found in the whole
         *  picture: the middle of it, this share each way, scaled up. A
         *  child is then found at about 22% of the frame's height instead
         *  of 35%, and once found is followed down to about 13%. */
        private const val ZOOM = 0.6f

        /** Results without anyone before the search switches between the
         *  whole picture and its middle. */
        private const val MISSES_BEFORE_SWITCH = 4

        /** The longer side the frame is scaled to before the models see
         *  it. The palm finder shrinks it to 192 pixels anyway, but the
         *  hand's points are read from a crop around the hand at this
         *  size: a child a couple of metres from the Portal's wide camera
         *  has a small hand in the picture, and at 320 pixels its points
         *  were blurry and the cursor shook. */
        private const val WORK_SIDE = 640

        /** The body mask as sent to the app: this many cells across. */
        const val MASK_WIDTH = 96
    }

    private var hands: HandLandmarker? = null
    private var poses: PoseLandmarker? = null
    private var posesFailed = false
    private val poseBusy = AtomicBoolean(false)
    private var poseFeedNs = 0L
    private var poseResults = 0
    private var poseAvgMs = 0f

    /** Whether the pose model looks at the middle of the picture, and
     *  whether the frame in flight was such a crop. */
    @Volatile private var zoomed = false
    @Volatile private var feedZoomed = false
    private var misses = 0
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
    fun offer(image: ImageProxy, rotation: Int, front: Boolean, wantHands: Boolean, wantBody: Boolean, wantPose: Boolean = false) {
        val needHands = wantHands && !handsFailed && !handBusy.get()
        val needBody = wantBody && !bodyFailed && !bodyBusy.get()
        val needPose = wantPose && !posesFailed && !poseBusy.get()
        if (!needHands && !needBody && !needPose) return
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
        if (needPose) {
            val task = poses ?: loadPoses()
            if (task != null && poseBusy.compareAndSet(false, true)) {
                try {
                    poseFeedNs = now
                    feedZoomed = zoomed
                    val input = if (zoomed) middle(frame) else frame
                    task.detectAsync(BitmapImageBuilder(input).build(), ts)
                } catch (e: Exception) {
                    poseBusy.set(false)
                    Log.w(TAG, "pose feed failed: $e")
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

    /** The middle [ZOOM] of [frame], scaled back up to its size. */
    private fun middle(frame: Bitmap): Bitmap {
        val w = (frame.width * ZOOM).toInt()
        val h = (frame.height * ZOOM).toInt()
        val crop = Bitmap.createBitmap(frame, (frame.width - w) / 2, (frame.height - h) / 2, w, h)
        return Bitmap.createScaledBitmap(crop, frame.width, frame.height, true)
    }

    /** People's bodies: per person 33 points (x, y as the child sees the
     *  picture, 0..1, and how sure the model is each point is in view). */
    private fun onPoses(result: PoseLandmarkerResult) {
        poseBusy.set(false)
        val ms = (System.nanoTime() - poseFeedNs) / 1_000_000f
        poseResults++
        poseAvgMs += (ms - poseAvgMs) / min(poseResults, 30).toFloat()
        if (poseResults == 1 || poseResults % 300 == 0) {
            Log.i(TAG, "poses: ${"%.0f".format(poseAvgMs)} ms a look${if (zoomed) " (zoomed)" else ""}")
        }
        val wasZoomed = feedZoomed
        // A crop of the middle maps back to the whole picture.
        val scale = if (wasZoomed) ZOOM else 1f
        val offset = if (wasZoomed) (1f - ZOOM) / 2f else 0f
        val out = ArrayList<FloatArray>(2)
        var widest = 0f
        for (person in result.landmarks()) {
            if (person.size < 33) continue
            val pts = FloatArray(33 * 3)
            var minX = 1f
            var maxX = 0f
            for (i in 0 until 33) {
                val x = person[i].x()
                val y = person[i].y()
                minX = min(minX, x)
                maxX = max(maxX, x)
                pts[i * 3] = offset + x * scale
                pts[i * 3 + 1] = offset + y * scale
                pts[i * 3 + 2] = person[i].visibility().orElse(0f)
            }
            widest = max(widest, maxX - minX)
            out.add(pts)
        }
        if (out.isEmpty()) {
            // Nobody: look the other way (whole picture or its middle).
            if (++misses >= MISSES_BEFORE_SWITCH) {
                misses = 0
                zoomed = !zoomed
            }
        } else {
            misses = 0
            // Someone filling the zoomed view: back to the whole picture.
            if (wasZoomed && widest > 0.8f) zoomed = false
        }
        emit(mapOf("gposes" to out, "aspect" to aspect.toDouble(), "ms" to poseAvgMs.toDouble()))
    }

    private fun loadPoses(): PoseLandmarker? {
        if (posesFailed) return null
        return try {
            val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath(POSE_MODEL).setDelegate(Delegate.CPU).build())
                .setRunningMode(RunningMode.LIVE_STREAM)
                // Two: the player and someone beside them (or two players).
                .setNumPoses(2)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setOutputSegmentationMasks(false)
                .setResultListener { result, _ -> onPoses(result) }
                .setErrorListener { e ->
                    poseBusy.set(false)
                    Log.w(TAG, "pose landmarker error: $e")
                }
                .build()
            PoseLandmarker.createFromOptions(context, options).also {
                poses = it
                Log.i(TAG, "game poses loaded")
            }
        } catch (e: Throwable) {
            posesFailed = true
            Log.e(TAG, "game poses unavailable: $e", e)
            null
        }
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
            // The hand's size (wrist to the middle knuckle) in widths of
            // the frame: how far away the child is, so a game can ask for
            // the same arm movement near or far.
            val sx = h[9].x() - h[0].x()
            val sy = (h[9].y() - h[0].y()) * aspect
            val size = kotlin.math.sqrt(sx * sx + sy * sy)
            out.add(mapOf("x" to px.toDouble(), "y" to py.toDouble(), "f" to read.fingers, "lm" to pts,
                "s" to size.toDouble(), "a" to aspect.toDouble()))
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
                // Two, even for one-player games: with two children in
                // view the app needs both to keep following the player's.
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.45f)
                .setMinHandPresenceConfidence(0.4f)
                // Keep following a hand through motion blur rather than
                // dropping it and finding it again (a visible jump).
                .setMinTrackingConfidence(0.3f)
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
        try { poses?.close() } catch (_: Exception) {}
        hands = null
        body = null
        poses = null
        poseBusy.set(false)
        zoomed = false
        misses = 0
        handBusy.set(false)
        bodyBusy.set(false)
    }
}
