import Flutter
import UIKit
import FirebaseAuth

/// Custom Flutter plugin that invokes Firebase Phone Auth on the **main actor**,
/// bypassing the crash where Firebase 11.x's internal Task accesses UIKit from
/// Swift's cooperative thread pool (com.apple.root.user-initiated-qos.cooperative).
///
/// Key design decisions:
/// - `sendCode` uses `Task { @MainActor in }` + the async API so the ENTIRE
///   Firebase async call runs pinned to the main actor, not a background Task.
/// - `present`/`dismiss` use main-sync (not async) so Firebase's reCAPTCHA
///   SFSafariViewController is visually on screen before Firebase continues.
/// - Static strong refs keep both the channel and instance alive.
@objc class PhoneAuthPlugin: NSObject, AuthUIDelegate {

  // Retain strongly so ARC doesn't release them after register() returns
  private static var sharedChannel: FlutterMethodChannel?
  private static var sharedInstance: PhoneAuthPlugin?

  @objc static func register(with messenger: FlutterBinaryMessenger) {
    let instance = PhoneAuthPlugin()
    let channel = FlutterMethodChannel(
      name: "closeteye/phone_auth",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    sharedInstance = instance
    sharedChannel  = channel
  }

  // MARK: - Method channel handler

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      call.method == "verifyPhoneNumber",
      let args = call.arguments as? [String: Any],
      let phoneNumber = args["phoneNumber"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    sendCode(to: phoneNumber, flutterResult: result)
  }

  // MARK: - Core: send OTP via Firebase Phone Auth

  private func sendCode(to phoneNumber: String, flutterResult: @escaping FlutterResult) {
    // Task { @MainActor in } ensures the Firebase async function starts AND
    // runs its synchronous setup code on the main thread, not a cooperative
    // background thread. This fixes the UIKit nil-unwrap crash in Firebase 11.x.
    Task { @MainActor in
      do {
        let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(
          phoneNumber,
          uiDelegate: self   // we provide AuthUIDelegate → in-app reCAPTCHA via SFSafariVC
        )
        flutterResult(verificationID)
      } catch let nsError as NSError {
        // Extract the underlying Firebase error for better diagnostics
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let detail = [
          "domain": nsError.domain,
          "code": nsError.code,
          "message": nsError.localizedDescription,
          "underlying": underlying?.localizedDescription ?? "none",
          "userInfo": nsError.userInfo.description
        ].description
        print("[PhoneAuthPlugin] verifyPhoneNumber error: \(detail)")
        flutterResult(FlutterError(
          code: "VERIFY_FAILED_\(nsError.code)",
          message: nsError.localizedDescription,
          details: underlying?.localizedDescription ?? nsError.userInfo.description
        ))
      }
    }
  }

  // MARK: - AuthUIDelegate (presents reCAPTCHA SFSafariViewController in-app)

  func present(
    _ viewControllerToPresent: UIViewController,
    animated flag: Bool,
    completion: (() -> Void)? = nil
  ) {
    // Always dispatch to main async — avoids potential deadlock with
    // Swift's actor scheduler when called from a cooperative thread.
    DispatchQueue.main.async {
      self.topViewController()?.present(viewControllerToPresent, animated: flag, completion: completion)
    }
  }

  func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
    DispatchQueue.main.async {
      self.topViewController()?.dismiss(animated: flag, completion: completion)
    }
  }

  // MARK: - Scene-compatible top view controller lookup

  private func topViewController() -> UIViewController? {
    // Flutter 3.x uses scene-based lifecycle; UIApplication.keyWindow is nil.
    // Walk the active UIWindowScene to find the real key window.
    let activeScene = UIApplication.shared.connectedScenes
      .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    guard
      let window = activeScene?.windows.first(where: { $0.isKeyWindow })
                ?? activeScene?.windows.first
    else { return nil }

    var top: UIViewController? = window.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
