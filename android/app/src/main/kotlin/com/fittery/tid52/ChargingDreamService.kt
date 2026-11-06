package com.fittery.tid52

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.service.dreams.DreamService
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** System-selected, charging-only screen saver. No activity launch or overlay. */
class ChargingDreamService : DreamService() {
    companion object {
        fun syncAvailability(context: Context) {
            val component = ComponentName(context, ChargingDreamService::class.java)
            val enabled = ChargingDreamPolicy.enabled(BatteryEngine.get(context).settings())
            val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            if (context.packageManager.getComponentEnabledSetting(component) != state) {
                context.packageManager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            }
        }
    }

    private val battery by lazy { BatteryEngine.get(this) }
    private var engine: FlutterEngine? = null
    private var flutterView: FlutterView? = null
    private var methods: MethodChannel? = null
    private var readings: EventChannel? = null
    private var platform: MethodChannel? = null
    private var observer: ((Map<String, Any?>) -> Unit)? = null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isInteractive = true
        isFullscreen = true
        isScreenBright = false
        window?.decorView?.setBackgroundColor(Color.BLACK)
        if (!ChargingDreamPolicy.allowed(battery.snapshot())) { finish(); return }
        try {
            // A separate renderer exists only while the system is dreaming.
            // It shares the process VM and the single native battery sampler.
            val renderingEngine = FlutterEngine(this, null, false)
            engine = renderingEngine
            val messenger = renderingEngine.dartExecutor.binaryMessenger
            // Dreams have a system-owned window rather than an Activity for
            // Flutter's usual PlatformPlugin. Window styling is owned here.
            platform = MethodChannel(messenger, "flutter/platform").also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "SystemNavigator.pop" -> { result.success(null); finish() }
                        "SystemChrome.setSystemUIOverlayStyle", "SystemChrome.setEnabledSystemUIMode",
                        "SystemChrome.setEnabledSystemUIOverlays", "SystemChrome.restoreSystemUIOverlays",
                        "SystemChrome.setPreferredOrientations", "SystemChrome.setApplicationSwitcherDescription",
                        "SystemChrome.setSystemUIChangeListener", "SystemNavigator.setFrameworkHandlesBack",
                        "SystemSound.play", "HapticFeedback.vibrate" -> result.success(null)
                        else -> result.notImplemented()
                    }
                }
            }
            methods = MethodChannel(messenger, "fittery/battery").also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "initial" -> result.success(battery.snapshot())
                        "finishDream" -> { result.success(null); finish() }
                        else -> result.notImplemented()
                    }
                }
            }
            readings = EventChannel(messenger, "fittery/readings").also { channel ->
                channel.setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        val callback: (Map<String, Any?>) -> Unit = { reading ->
                            if (!ChargingDreamPolicy.allowed(reading)) finish() else events.success(reading)
                        }
                        observer = callback
                        battery.dreamListener = callback
                        callback(battery.snapshot())
                    }
                    override fun onCancel(arguments: Any?) { removeObserver() }
                })
            }
            val view = FlutterView(this, FlutterSurfaceView(this))
            flutterView = view
            setContentView(view)
            hideChargingDashboardBars(window)
            view.attachToFlutterEngine(renderingEngine)
            renderingEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(), "chargingDreamMain"
            ))
        } catch (error: Exception) {
            android.util.Log.e("Fittery", "Screen saver could not start", error)
            releaseRenderer()
            finish()
        }
    }

    override fun onDreamingStarted() {
        super.onDreamingStarted()
        if (engine == null || !ChargingDreamPolicy.allowed(battery.snapshot())) { finish(); return }
        battery.setDreaming(true)
        engine?.lifecycleChannel?.aWindowIsFocused()
        engine?.lifecycleChannel?.appIsResumed()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideChargingDashboardBars(window)
        if (hasFocus) engine?.lifecycleChannel?.aWindowIsFocused()
        else engine?.lifecycleChannel?.noWindowsAreFocused()
    }

    override fun onDreamingStopped() {
        releaseRenderer()
        super.onDreamingStopped()
    }

    override fun onDetachedFromWindow() {
        releaseRenderer()
        super.onDetachedFromWindow()
    }

    override fun onDestroy() {
        releaseRenderer()
        super.onDestroy()
    }

    private fun removeObserver() {
        if (battery.dreamListener === observer) battery.dreamListener = null
        observer = null
    }

    private fun releaseRenderer() {
        engine?.lifecycleChannel?.appIsPaused()
        removeObserver()
        battery.setDreaming(false)
        methods?.setMethodCallHandler(null)
        readings?.setStreamHandler(null)
        platform?.setMethodCallHandler(null)
        methods = null; readings = null; platform = null
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        engine?.lifecycleChannel?.appIsDetached()
        engine?.destroy()
        engine = null
    }
}
