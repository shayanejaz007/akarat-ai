import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The Google Maps key arrives from Dart at launch (GOOGLE_MAPS_IOS_KEY in
    // the build's settings), before any map is shown: one place to set it for
    // both platforms. Locked in Google Cloud to this app's bundle id.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AkaratMapsKey") {
      let channel = FlutterMethodChannel(name: "ai.akarat.app/maps", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "provideKey", let key = call.arguments as? String, !key.isEmpty else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(GMSServices.provideAPIKey(key))
      }
    }
  }
}
