# Charging dashboard screen saver - Build 21

The main battery display is now the touch target for opening the manual dashboard. The separate square shortcut is removed. A thin **Monitor Battery** row and a matching outlined **Fullscreen Dashboard** button sit below the charging status; they stack on narrow screens or with large text. Settings switches and the monitoring thumb use a 360 ms eased transition, with immediate updates when reduced motion is requested. Pending monitoring permission requests still disable repeated taps.

## Set up the optional system screen saver

1. Connect a charger.
2. In Fittery Settings, turn on **Charging dashboard on lock screen**. This also enables the master dashboard feature; it does not turn on monitoring or request notifications.
3. Tap **Set up Android screen saver**.
4. In Android settings, select **Fittery charging dashboard**, enable the system screen saver, and choose a start condition such as **While charging** if the phone offers it. Use Android's Preview/Test option while plugged in.
5. Leave the display on and let it become idle naturally. Android and the manufacturer control actual activation. Pressing Power is not a reliable way to start a screen saver; this does not promise an immediate screen on charger insertion or replace Android authentication.

The native `ChargingDreamService` is signature-protected with `BIND_DREAM_SERVICE`; this protects who can bind to the service and is not an overlay or runtime permission requested from the user. The component is disabled by default and enabled only while both dashboard and screen-saver preferences are on. Disabling the master dashboard preference clears the screen-saver preference too. Fittery opens the official `ACTION_DREAM_SETTINGS` activity, with a display-settings fallback for manufacturers that omit it. It never silently changes the selected system screen saver.

## Rendering and data lifecycle

Android owns the screen-saver window. It hosts a dedicated Flutter renderer only while dreaming, using the existing charging dashboard and its original artwork. Close/slide exits the dream with `finish()`; it does not change keyguard or open ordinary app screens. The screen saver requests dimmable presentation and does not acquire its own wake lock or force full brightness.

The Dart root subscribes only to readings. It does not load history/device information, subscribe to network/current-chart streams, start preview audio, or create a history refresh timer. The native `BatteryEngine` keeps one shared receiver and sampling loop at the usual three-second rate. A separate dream callback preserves the activity callback. Dream-only viewing does not write foreground history or begin a recording; existing user-enabled monitoring/alarms continue normally. The dream's interest, observer, view, method handlers and renderer are released on stop/detach/destruction. Unplugging or disabling either preference ends the dream.

## Verification

Flutter tests cover battery touch activation, compact layouts, switch request guards, read-only dream subscriptions, screen-saver setup, coupled preferences, and dream dismissal without Activity lock flags. Native tests cover policy gates, the shared three-second loop, no dream-only history writes, independent callbacks, and preservation of monitoring. Android lint and an AOT release build check the new service and preserved Dart entry point.

Physical-device checks still required: select Fittery in system settings; run Preview while charging; wait for idle activation; test close/slide, unplugging, power-button wake behavior and normal authentication; verify an active monitor recording and alarm remain functional across entry/exit. Compare memory and frame behavior in a release/profile build. OEM idle/lock behavior cannot be established by unit tests.

## Official references

- [Android DreamService lifecycle and interactive dismissal](https://developer.android.com/reference/android/service/dreams/DreamService)
- [Android screen-saver settings action](https://developer.android.com/reference/android/provider/Settings#ACTION_DREAM_SETTINGS)
- [Google's screen-saver setup and Power-button caveat](https://support.google.com/pixelphone/answer/2818748?hl=en)
- [Flutter engine and view embedding](https://api.flutter.dev/javadoc/io/flutter/embedding/engine/FlutterEngine.html)
