import Flutter
import UIKit
import GoogleMaps
import flutter_local_notifications

// Obs: FBSDKCoreKit pode não expor módulos Swift (dependendo da instalação via CocoaPods).
// O SDK do Facebook normalmente é inicializado automaticamente via plugin.

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // ✅ IMPORTANTE: Configurar flutter_local_notifications para receber cliques
    // Isso é NECESSÁRIO para que o callback onDidReceiveNotificationResponse funcione no iOS
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    
    // Registrar plugins normalmente
    GeneratedPluginRegistrant.register(with: self)

    // ✅ Configurar para receber notificações quando app está em foreground
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

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
}
