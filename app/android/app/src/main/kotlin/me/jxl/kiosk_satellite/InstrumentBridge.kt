package me.jxl.kiosk_satellite

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Instant notes for the Kids Portal's piano (and its other instruments).
 *
 * A key press must sound at once and several keys must ring together, which
 * a media player per note cannot do: each one has to open, buffer and start.
 * SoundPool decodes every note into memory up front and mixes them, so a
 * play is a few milliseconds and up to [MAX_STREAMS] notes overlap.
 *
 * Methods on kiosk_satellite/instrument:
 *  - load {paths: [String]} -> [Int] sample ids, in order. Loading finishes
 *    in the background; a play before then is silent (the next one lands).
 *  - play {id: Int, volume: Double} -> Boolean
 *  - unload -> frees every sample.
 */
class InstrumentBridge(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "kiosk_satellite/instrument")
    private val loaded = ConcurrentHashMap.newKeySet<Int>()

    private var pool: SoundPool? = newPool()

    private fun newPool(): SoundPool? = try {
        SoundPool.Builder()
            .setMaxStreams(MAX_STREAMS)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .build()
            .also { p ->
                p.setOnLoadCompleteListener { _, id, status ->
                    if (status == 0) loaded.add(id)
                }
            }
    } catch (_: Exception) {
        null
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> {
                    val p = pool ?: newPool().also { pool = it }
                    if (p == null) {
                        result.success(emptyList<Int>())
                        return@setMethodCallHandler
                    }
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val ids = paths.map { path ->
                        try {
                            p.load(path, 1)
                        } catch (_: Exception) {
                            0
                        }
                    }
                    result.success(ids)
                }
                "play" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val volume = (call.argument<Double>("volume") ?: 1.0).toFloat().coerceIn(0f, 1f)
                    val p = pool
                    val ok = p != null && id != 0 && loaded.contains(id) &&
                        p.play(id, volume, volume, 1, 0, 1f) != 0
                    result.success(ok)
                }
                "unload" -> {
                    pool?.release()
                    pool = null
                    loaded.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val MAX_STREAMS = 12
    }
}
