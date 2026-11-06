import 'decision_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_identity.dart';
import 'controller.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.c});
  final BatteryController c;

  @override
  Widget build(BuildContext context) {
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 14),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
    Widget group(List<Widget> children) => Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(children: children),
    );
    Widget faq(String question, String answer) => ExpansionTile(
      title: Text(question, style: const TextStyle(fontSize: 13)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(answer, style: const TextStyle(fontSize: 12, height: 1.7)),
      ],
    );
    final r = c.reading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('Frequently asked questions'),
        group([
          faq(
            'What is Fittery, and what is it built with?',
            'Fittery is a lightweight, free and open-source Android battery-monitoring app. It helps you understand your battery, observe charging and discharging activity, review recorded trends, and personalize important alerts. Your readings and history stay on your device.\n\nFittery is built with Flutter and Dart, with native Android integrations written in Kotlin for battery readings, background monitoring, alerts, and charging features.',
          ),
          faq(
            'What features does Fittery offer?',
            'Fittery includes:\n\n'
                '• A full-screen Charging Dashboard you can open manually while plugged in\n'
                '• An optional charging screen saver and lock-screen notification information\n'
                '• Customizable charging-target, low-battery, and temperature alerts\n'
                '• Adjustable alert sounds and thresholds\n'
                '• Independent Background Alerts without recording\n'
                '• Monitor Mode for ongoing recording and alerts, with a configurable notification refresh interval\n'
                '• Live battery statistics, graphs, charging history, and saved recordings\n'
                '• Display, notification, and recording preferences\n\n'
                'Visit Settings to enable and adjust the features you want. Some measurements and lock-screen behavior depend on your phone and Android settings.',
          ),
          faq(
            'How do I customize Fittery?',
            'Open Settings to adjust charging-target and low-battery thresholds, temperature limits, alarm sounds, monitoring options, and Charging Dashboard preferences. You can also personalize display units, notification details, the notification refresh interval, and how long completed recordings are kept.\n\nTurn individual features on or off to suit your needs. Android notification permissions and background-access settings may also affect how they work.',
          ),
          faq(
            'How do the Charging Dashboard and lock-screen features work?',
            'The Charging Dashboard is a dedicated full-screen view of your battery’s charging information. It is enabled by default for new installations; existing users keep their previous preference. Enable it under Settings → Charging dashboard → Enable charging dashboard.\n\nWhile plugged in, tap the main battery display, use the Fullscreen Dashboard button, or open it from Settings. Viewing the dashboard does not turn on background monitoring or start a recording. You can close it with Back, the close button, or slide to dismiss; it also closes when you unplug.'
                '\n\n'
                'For the optional charging screen saver, enable Charging dashboard on lock screen in Settings, tap Set up Android screen saver, and select Fittery charging dashboard in Android’s screen-saver settings. Choose a while-charging start condition if your phone offers one.\n\nAndroid and your phone manufacturer control when the screen saver starts while charging and idle. It may not appear immediately when you connect a charger or press Power. The manual dashboard can also appear above the lock screen on supported devices; your phone stays locked and still requires its normal authentication.\n\nFor monitoring information in lock-screen notifications, use Show on lock screen in Fittery’s notification settings. Android’s own notification and privacy settings control what is visible. Availability and behavior vary by Android version and phone.',
          ),
          faq(
            'How do Background Alerts and Monitor Mode differ?',
            'Background Alerts is an optional, lightweight way to run your configured battery-level and temperature alarms while Fittery is closed. It reacts to Android battery updates without recording statistics or enabling Monitor Mode. Enable it separately in Settings.\n\nMonitor Mode records readings, history, and statistics and retains its existing alarms. Its dashboard control is independent: turning either feature off does not turn the other off. When both are enabled, they share one status notification and do not duplicate alarms.\n\nThe alert-only status notification is quiet. Dismissing it where Android allows does not disable alerts; use the Settings switch or its Stop action. Swiping away the app normally leaves the service running, but force-stop, Android’s Active apps Stop action, and manufacturer restrictions can interrupt it. Saved choices are restored after supported restarts. Alert timing depends on Android battery updates, not a guaranteed number of seconds.',
          ),
          faq(
            'How do battery alerts, graphs, and charging history work?',
            'Choose charging-target, low-battery, and temperature thresholds in Settings, allow notifications, and select sounds for each alert. Audible alarms use your phone’s alarm volume. Enable Background Alerts or Monitor Mode to receive them while the app is closed.\n\nGraphs show available charge level, current, power, voltage, and temperature readings over time. Monitor Mode records activity for later review; Background Alerts alone does not create recordings. Notification refresh interval changes the live monitor notification only, with choices of 1, 3, or 5 seconds. Recording remains at three-second intervals, subject to Android restrictions.'
                '\n\n'
                'Graphs help you review available battery measurements such as charge level, temperature, current, voltage, power, and remaining charge over time. History lets you review recorded activity, charging sessions, and saved trends.\n\nTurn on monitoring to record activity in the background. Open History or Settings → Past recordings to browse recordings by date, inspect graphs, rename recordings, or delete them. Completed recordings expire after 30 days unless you enable Keep recordings until I delete them; active recordings are protected.\n\nThe measurements available depend on your phone. Missing or unsupported readings are not evidence of a battery fault, and gaps in a graph can mean no readings were recorded during that period.',
          ),
          faq(
            'Why would I use Fittery every day?',
            'A charging icon tells you power is connected, but not how quickly your battery is filling. A weak charger, damaged cable, or low-power laptop USB port may leave your phone charging very slowly. A quick look at current and wattage in Fittery can help you spot this and compare another cable, charger, or port.\n\nUnder 1 W means little net power is reaching the battery at that moment. Fittery measures battery-side power, not the charger’s rated output; phone use, heat, and a nearly full battery can also explain a low reading. You can also check battery history and, on supported devices, cycle count to better understand usage as your phone ages.',
          ),
          faq(
            'How can alarms help me build better charging habits?',
            'In Settings, enable Charging limit and choose a target such as 80%, then enable Low battery at 20% or 30%. Allow notifications and, if you want audible alerts, turn on Alarm sound and check the system alarm volume. Unplug when the charging alarm rings, and reconnect when the low-battery alarm reminds you. Turn on Background Alerts or Monitor Mode so alerts can continue after you leave the app.\n\nSpending less time fully charged and avoiding frequent deep discharges can help reduce battery wear. Charging above 80% is not an immediate damage threshold; choose targets that suit your day. Fittery reminds you to unplug — it cannot stop charging automatically.',
          ),
          faq(
            'What should I do when my battery gets warm?',
            'Enable Battery temperature in Settings and choose a reminder such as 38°C or 40°C. These are early warning preferences, not universal danger limits; normal temperatures vary by device and conditions.\n\nIf the alarm rings, pause gaming or other demanding tasks, stop unnecessary background activity, unplug if charging, and remove the case if it traps heat. Let the phone cool in a shaded, ventilated place. Follow your phone manufacturer’s temperature guidance.',
          ),
          faq(
            'Will Fittery drain my battery?',
            'Fittery is designed to stay lightweight, with periodic background readings and no ads or analytics. Monitoring still uses some power, and actual usage depends on your phone and settings. Its purpose is to help you notice charging problems and build better battery habits. Allow background access if you want ongoing monitoring and alarms.',
          ),
          faq(
            'Why is Fittery not working in the background?',
            'Some phones, especially Xiaomi, Redmi, and POCO devices, restrict background apps to save power. First enable Background Alerts or Monitor Mode in Fittery and allow notifications. Then open your phone’s Settings → Apps → Fittery → Battery or Power, and select No restrictions or Unrestricted. On some Xiaomi phones, this is under Battery saver. Enable Autostart or Background autostart if available. Menu names vary by phone.\n\nFittery’s Settings includes Battery optimization and Autostart & background access shortcuts. The ongoing monitoring notification is part of Android’s background service. We’re working to improve background reliability, but device restrictions may still interrupt monitoring. If it keeps stopping, please report it by email.',
          ),
          faq(
            'How do I report a problem or suggest an improvement?',
            'Email $supportEmail — email is the preferred way to report a bug, suggest a feature, or contact the developer. You can also visit ${developerWebsiteUrl.isEmpty ? 'https://saksham.info.np' : developerWebsiteUrl} and use any contact method listed there.\n\nFor problems, include your phone model, Android version, Fittery version, the settings involved, and steps to reproduce the issue. Describe what you expected and what actually happened; screenshots help too. You can find your installed Fittery version under Developer details below. For suggestions, explain what you would like to do and how the change would help.',
          ),
          faq(
            'How can I support the developer?',
            'A personal message is a wonderful way to support Fittery. Visit ${developerWebsiteUrl.isEmpty ? 'https://saksham.info.np' : developerWebsiteUrl} and send a message through one of the contact options, or email me directly at $supportEmail. Share how you use the app, suggest an idea, or simply say hello.\n\nTaking a moment to reach out means a lot to me. Your messages bring happiness and encouragement, and knowing that Fittery is useful to you makes the work worthwhile. Thank you for supporting this free, open-source project.',
          ),
        ]),
        heading('Developer details'),
        group([
          const ListTile(
            leading: Icon(Icons.code_rounded),
            title: Text(developerName),
            subtitle: Text(developerCredit),
          ),
          const ListTile(
            leading: Icon(Icons.support_agent_rounded),
            title: Text('Support & privacy'),
            subtitle: SelectableText(supportEmail),
          ),
          ListTile(
            key: const ValueKey('app-version'),
            leading: const Icon(Icons.info_outline),
            title: const Text('App version'),
            subtitle: SelectableText(
              c.appInfo['version'] == null
                  ? 'Loading installed version…'
                  : '${c.appInfo['version']} · build ${c.appInfo['build']}',
            ),
          ),
          if (developerWebsiteUrl.isNotEmpty)
            ListTile(
              title: const Text('Developer website'),
              trailing: const Icon(Icons.open_in_new, size: 17),
              onTap: () => _open(context, developerWebsiteUrl),
            ),
          ListTile(
            key: const ValueKey('privacy-policy'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            subtitle: Text(
              privacyPolicyUrl.isEmpty
                  ? 'Read the policy · public link pending'
                  : privacyPolicyUrl,
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => DecisionDialog(
                title: const Text('Privacy policy'),
                content: const SingleChildScrollView(
                  child: SelectableText(
                    privacyPolicyText,
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
                actions: [
                  if (privacyPolicyUrl.isNotEmpty)
                    TextButton(
                      onPressed: () => _open(context, privacyPolicyUrl),
                      child: const Text('Open website'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          ExpansionTile(
            title: const Text('Diagnostics', style: TextStyle(fontSize: 13)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                [
                  'Last reading: ${r?.number('time') == null ? 'Unavailable' : DateTime.fromMillisecondsSinceEpoch(r!.number('time')!.toInt()).toLocal()}',
                  'Status: ${r?.text('status')} · ${r?.text('source')}',
                  'Charge level: ${r?.data['level'] ?? 'Unavailable'}%',
                  'Snapshot source: ${r?.text('batterySnapshotSource')}',
                  'Broadcast level/scale: ${r?.data['broadcastLevel']}/${r?.data['broadcastScale']}',
                  'Broadcast sequence: ${r?.data['batteryBroadcastSequence'] ?? 'Unavailable'}',
                  'Capacity property: ${r?.data['capacityProperty'] ?? 'Unavailable'}%',
                  'Raw current: ${r?.data['rawCurrent'] ?? 'Unavailable'}',
                  'Current divisor: ${r?.data['currentDivisor'] ?? 'Unavailable'}',
                  'Invert polarity: ${r?.data['currentInverted'] ?? false}',
                  'Calibrated against counter: ${r?.data['currentCalibrated'] ?? false}',
                  'Reported current: ${r?.data['currentMa'] ?? 'Unavailable'} mA',
                  'Reported voltage: ${r?.data['voltageMv'] ?? 'Unavailable'} mV',
                  'Charge counter: ${r?.data['chargeCounterMah'] ?? 'Unavailable'} mAh',
                  'Hardware full capacity: ${r?.data['fullCapacityMah'] ?? 'Unavailable'} mAh',
                  'Design capacity: ${r?.data['designCapacityMah'] ?? 'Unavailable'} mAh',
                  'Capacity controller: ${r?.data['capacityController'] ?? 'Unavailable'}',
                  'Matched capacity pair: ${r?.data['capacityPairReliable'] ?? false}',
                  'Health estimate source: ${r?.text('healthEstimateSource')}',
                  'Hardware cycles: ${r?.data['cycles'] ?? 'Unavailable'}',
                  'Charging observation: ${r?.data['chargeObservationSeconds'] ?? 0} seconds',
                  'ETA source: ${r?.text('remainingSource')}',
                  'Charging alert enabled: ${c.flag('chargeAlert')} · target ${c.settings['chargeLimit']}%',
                  'Threshold acknowledged: ${r?.data['chargeAlertLatched'] ?? false}',
                  'Active alert: ${r?.data['alarmActive'] ?? false}',
                  'Notifications allowed: ${c.notificationsAllowed}',
                ].join('\n'),
                style: const TextStyle(fontSize: 11, height: 1.7),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await c.refreshReading();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Readings could not refresh.'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh readings'),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    try {
      await c.openLink(url);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PlatformException
                  ? e.message ?? 'Link could not open.'
                  : 'Link could not open.',
            ),
          ),
        );
      }
    }
  }
}
