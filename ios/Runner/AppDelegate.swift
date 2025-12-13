import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps SDK API Key (iOS) - DEVE vir ANTES de GeneratedPluginRegistrant
    GMSServices.provideAPIKey("AIzaSyD9DcPOLt4FggQqmHPJd7JRlWdhR0XV4gQ")
    print("✅ Google Maps API Key configurada")
    
    GeneratedPluginRegistrant.register(with: self)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
