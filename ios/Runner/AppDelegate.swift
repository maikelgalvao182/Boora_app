import Flutter
import UIKit
import GoogleMaps
import FBSDKCoreKit
import AppsFlyerLib

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    ApplicationDelegate.shared.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    
    GeneratedPluginRegistrant.register(with: self)

    // Google Maps SDK API Key (iOS)
    // Recebida do Dart via MethodChannel (fonte de verdade: constants.dart)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.example.partiu/google_maps_ios",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "setApiKey":
          if let args = call.arguments as? [String: Any],
             let apiKey = args["apiKey"] as? String,
             !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            GMSServices.provideAPIKey(apiKey)
            result("ok")
          } else {
            result(FlutterError(code: "INVALID_ARGS", message: "apiKey ausente", details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MARK: - AppsFlyer Universal Links (Deep Links)
  // Necessário para capturar deep links quando o app já está instalado
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    // Passa o Universal Link para o AppsFlyer SDK
    AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
    
    // Chama o handler padrão do Flutter
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
  
  // MARK: - AppsFlyer URI Scheme (Deep Links)
  // Necessário para capturar deep links via URI scheme (boora://)
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // Passa o URL scheme para o AppsFlyer SDK
    AppsFlyerLib.shared().handleOpen(url, options: options)
    
    // Chama o handler padrão do Flutter (para Facebook, etc)
    return super.application(app, open: url, options: options)
  }
}
