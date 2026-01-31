import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Let FlutterAppDelegate set up the engine first.
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Register plugins.
    //
    // Note: Many Flutter plugins are implemented in Swift. Those classes are not reliably
    // discoverable via NSClassFromString without module prefixes, so a manual registrant can
    // silently skip them. The generated registrant is the safest option.
    GeneratedPluginRegistrant.register(with: self)
    return ok
  }
}
