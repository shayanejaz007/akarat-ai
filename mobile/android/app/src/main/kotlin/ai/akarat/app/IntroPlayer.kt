package ai.akarat.app

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * The opening's intro clip, prepared the moment the Flutter engine exists.
 *
 * Left to Dart, the clip is only opened once the engine's start and its
 * graphics set-up have finished with the main thread: on a slow phone, two
 * seconds or more. Here the player opens and prepares the clip on its own
 * thread at once; the texture it draws into is made when Dart first asks
 * (the graphics must be up for that), and Dart starts it the moment its own
 * first frame is on screen (lib/app/launch_splash.dart).
 *
 * Muted and without an audio track, it never takes audio focus, so the
 * reader's music plays on.
 *
 * Channel "ai.akarat.app/intro":
 *  - from Dart: texture (id and size, or null), play, pause, release.
 *  - to Dart: rendering (first frame drawn), completed, error.
 */
class IntroPlayer private constructor(
    context: Context,
    private val textures: TextureRegistry,
    private val channel: MethodChannel,
) {
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("akarat-intro").apply { start() }
    private val worker = Handler(thread.looper)
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var player: MediaPlayer? = null
    private var prepared = false
    private var wanted = false
    private var failed = false
    private var released = false

    init {
        val asset = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(ASSET)
        val fd = context.assets.openFd(asset)
        worker.post {
            try {
                val p = MediaPlayer()
                player = p
                p.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build(),
                )
                p.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                p.setVolume(0f, 0f)
                p.isLooping = false
                p.setOnPreparedListener {
                    prepared = true
                    startIfWanted()
                }
                p.setOnInfoListener { _, what, _ ->
                    if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) tell("rendering")
                    false
                }
                p.setOnCompletionListener { tell("completed") }
                p.setOnErrorListener { _, _, _ ->
                    failed = true
                    tell("error")
                    true
                }
                p.prepareAsync()
            } catch (e: Exception) {
                failed = true
                tell("error")
            } finally {
                // The player keeps its own reference to the data.
                fd.close()
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "texture" -> result.success(if (released || failed) null else texture())
            "play" -> {
                worker.post {
                    wanted = true
                    startIfWanted()
                }
                result.success(null)
            }
            "pause" -> {
                worker.post {
                    wanted = false
                    if (prepared && player?.isPlaying == true) player?.pause()
                }
                result.success(null)
            }
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Made on first request, on the main thread, once the graphics are up. */
    private fun texture(): Map<String, Any> {
        val made = producer ?: textures.createSurfaceProducer().also { p ->
            producer = p
            p.setSize(WIDTH, HEIGHT)
            // Android may take the surface back (the app sent to the
            // background) and give a new one: the player follows.
            p.setCallback(
                object : TextureRegistry.SurfaceProducer.Callback {
                    override fun onSurfaceAvailable() = attach(p.surface)

                    override fun onSurfaceCleanup() = attach(null)
                },
            )
            attach(p.surface)
        }
        return mapOf("id" to made.id(), "width" to WIDTH, "height" to HEIGHT)
    }

    private fun attach(surface: Surface?) {
        worker.post {
            player?.setSurface(surface)
            startIfWanted()
        }
    }

    /** On the worker thread: plays once prepared, wanted, and drawing somewhere. */
    private fun startIfWanted() {
        val p = player ?: return
        if (prepared && wanted && producer != null && !p.isPlaying) p.start()
    }

    fun release() {
        if (released) return
        released = true
        worker.post {
            player?.release()
            player = null
            main.post { producer?.release() }
            thread.quitSafely()
        }
    }

    private fun tell(event: String) {
        main.post { if (!released) channel.invokeMethod(event, null) }
    }

    companion object {
        const val CHANNEL = "ai.akarat.app/intro"
        private const val ASSET = "assets/splash/intro.mp4"
        private const val WIDTH = 720
        private const val HEIGHT = 1280

        /** Null when the clip cannot even be opened; Dart then plays it itself. */
        fun create(context: Context, textures: TextureRegistry, channel: MethodChannel): IntroPlayer? =
            try {
                IntroPlayer(context, textures, channel)
            } catch (e: Exception) {
                null
            }
    }
}
