import 'package:flutter/services.dart';

/// Only registered-FID events are exposed, never raw FIS IDs or FCM tokens.
class FcmRegistration {
  static const _methods = MethodChannel('cadena/fcm_registration');
  static const _events = EventChannel('cadena/fcm_registration/registered');
  static final Stream<String> registeredFids =
      _events.receiveBroadcastStream().cast<String>();

  static Future<void> register() => _methods.invokeMethod<void>('register');
}
