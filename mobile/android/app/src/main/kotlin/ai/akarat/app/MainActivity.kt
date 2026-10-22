package ai.akarat.app

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity rather than FlutterActivity: the Android photo
// picker used by image_picker, and flutter_secure_storage's biometric
// option, both need a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private var intro: IntroPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12+: the system splash fades out by default, a dip through
        // black into the app's first frame, which shows the same logo in the
        // same place (lib/app/launch_splash.dart). Taken away at once, the
        // hand-over cannot be seen.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { view -> view.remove() }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The opening's intro, prepared now, while the engine still starts.
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IntroPlayer.CHANNEL)
        intro = IntroPlayer.create(this, flutterEngine.renderer, channel)
        channel.setMethodCallHandler { call, result ->
            val player = intro
            if (player == null) result.success(null) else player.handle(call, result)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        intro?.release()
        intro = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
