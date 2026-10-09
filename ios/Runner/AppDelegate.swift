import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var routingBridge: RoutingBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: RoutingBridge.channelName) else {
      return
    }
    let bridge = RoutingBridge()
    routingBridge = bridge
    let channel = FlutterMethodChannel(
      name: RoutingBridge.channelName,
      binaryMessenger: registrar.messenger(),
    )
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
  }
}
