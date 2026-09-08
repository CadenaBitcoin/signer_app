package com.cadena.fcm_registration

import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// All access is dispatched to the main thread. Only native onRegistered writes IDs.
internal object RegisteredFids {
    var latest: String? = null
    val listeners = mutableSetOf<EventChannel.EventSink>()
    fun publish(fid: String) {
        Handler(Looper.getMainLooper()).post {
            latest = fid
            listeners.toList().forEach { it.success(fid) }
        }
    }
}

class RegisteredFidService : FirebaseMessagingService() {
    override fun onRegistered(installationId: String) {
        RegisteredFids.publish(installationId)
    }
}

class FcmRegistrationPlugin : FlutterPlugin, EventChannel.StreamHandler {
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, "cadena/fcm_registration")
        events = EventChannel(binding.binaryMessenger, "cadena/fcm_registration/registered")
        events!!.setStreamHandler(this)
        methods!!.setMethodCallHandler { call, result ->
            if (call.method != "register") {
                result.notImplemented()
            } else {
                try {
                    val messaging = FirebaseMessaging.getInstance()
                    messaging.isAutoInitEnabled = true
                    messaging.register().addOnCompleteListener { task ->
                        if (task.isSuccessful) result.success(null)
                        else result.error("fcm_registration_failed", "FCM registration failed", null)
                    }
                } catch (_: Exception) {
                    result.error("fcm_registration_failed", "FCM registration unavailable", null)
                }
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        RegisteredFids.listeners.add(events)
        RegisteredFids.latest?.let { events.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        sink?.let { RegisteredFids.listeners.remove(it) }
        sink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        onCancel(null)
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
    }
}
