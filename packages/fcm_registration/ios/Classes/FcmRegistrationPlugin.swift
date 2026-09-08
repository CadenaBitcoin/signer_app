import Flutter
import FirebaseCore
import FirebaseMessaging
import UIKit

public class FcmRegistrationPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, MessagingDelegate {
    private var sink: FlutterEventSink?
    private var latest: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FcmRegistrationPlugin()
        let methods = FlutterMethodChannel(name: "cadena/fcm_registration", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        let events = FlutterEventChannel(name: "cadena/fcm_registration/registered", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)
        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "register" else { result(FlutterMethodNotImplemented); return }
        guard FirebaseApp.app() != nil else {
            result(FlutterError(code: "firebase_not_initialized", message: "Firebase is not initialized", details: nil))
            return
        }
        let messaging = Messaging.messaging()
        messaging.delegate = self
        messaging.isAutoInitEnabled = true
        // APNs enrollment is registration infrastructure, not a request for alert permission.
        UIApplication.shared.registerForRemoteNotifications()
        messaging.register { error in
            if error != nil {
                result(FlutterError(code: "fcm_registration_failed", message: "FCM registration failed", details: nil))
            } else { result(nil) }
        }
    }

    public func messaging(_ messaging: Messaging, didReceiveRegistration installationId: String?) {
        guard let fid = installationId else { return }
        DispatchQueue.main.async {
            self.latest = fid
            self.sink?(fid)
        }
    }

    public func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        // APNs may finish after the first FCM attempt. Retry once at this lifecycle event.
        Messaging.messaging().register { error in
            if error != nil { NSLog("event=fcm_registration_failed") }
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        if let fid = latest { events(fid) }
        return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
