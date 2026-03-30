import Flutter
import UIKit
import FirebaseAuth
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register for remote notifications so Firebase Phone Auth can get an
    // APNs token. Without this, Firebase returns FIRAuthErrorCodeInternalError
    // before even attempting the reCAPTCHA fallback.
    // We request provisional authorization (iOS 12+) which doesn't show a
    // permission dialog — it silently delivers notifications to the Notification Center.
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
      DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Forward APNs device token to Firebase Auth — allows the SDK to use the
  // silent-push verification path and/or confirm APNs availability.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Forward APNs failures too — Firebase handles them gracefully (falls back to reCAPTCHA).
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[AppDelegate] APNs registration failed: \(error) — Firebase will use reCAPTCHA fallback")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // Let Firebase intercept its own silent push notifications.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    PhoneAuthPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "PhoneAuthPlugin")!.messenger())
  }

  // Firebase Auth needs a non-nil window to present reCAPTCHA.
  // In Flutter 3.x with scene-based lifecycle, keyWindow is nil by default.
  // This override returns the active scene's window so Firebase can find
  // the root view controller.
  // Pass reCAPTCHA redirect URLs back to Firebase Auth.
  // When the SFSafariViewController finishes reCAPTCHA, iOS opens
  // com.googleusercontent.apps.XXXX://firebaseauth/link?... — Firebase
  // Auth intercepts it here to complete phone number verification.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if Auth.auth().canHandle(url) { return true }
    return super.application(app, open: url, options: options)
  }

  override var window: UIWindow? {
    get {
      if let scene = UIApplication.shared.connectedScenes
          .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
        return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
      }
      return super.window
    }
    set { super.window = newValue }
  }
}
