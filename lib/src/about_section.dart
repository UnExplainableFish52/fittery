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
            'Fittery is a small, lightweight, free and open-source Android app built with Flutter and Dart, with Kotlin for native Android features. It tracks charging, discharging, and battery temperature, and offers customizable alarms for your charging target, low battery, and high temperature.',
          ),
          faq(
            'How do I report a bug or contact the developer?',
            'Email $supportEmail — email is the preferred way to get in touch. You can also visit ${developerWebsiteUrl.isEmpty ? 'https://saksham.info.np' : developerWebsiteUrl} and use any contact method listed there. For bugs, include your phone model, Android version, Fittery version, and steps to reproduce the issue. Screenshots help too.',
          ),
          faq(
            'How can I support the developer?',
            'A personal message is a wonderful way to support Fittery. Visit ${developerWebsiteUrl.isEmpty ? 'https://saksham.info.np' : developerWebsiteUrl} and send a message through one of the contact options, or email me directly at $supportEmail. Share how you use the app, suggest an idea, or simply say hello.\n\nTaking a moment to reach out means a lot to me. Your messages bring happiness and encouragement, and knowing that Fittery is useful to you makes the work worthwhile. Thank you for supporting this free, open-source project.',
          ),
          faq(
            'Why would I use Fittery every day?',
            'A charging icon tells you power is connected, but not how quickly your battery is filling. A weak charger, damaged cable, or low-power laptop USB port may leave your phone charging very slowly. A quick look at current and wattage in Fittery can help you spot this and compare another cable, charger, or port.\n\nUnder 1 W means little net power is reaching the battery at that moment. Fittery measures battery-side power, not the charger’s rated output; phone use, heat, and a nearly full battery can also explain a low reading. You can also check battery history and, on supported devices, cycle count to better understand usage as your phone ages.',
          ),
          faq(
            'How can alarms help me build better charging habits?',
            'In Settings, enable Charging limit and choose a target such as 80%, then enable Low battery at 20% or 30%. Allow notifications and, if you want audible alerts, turn on Alarm sound and check the system alarm volume. Unplug when the charging alarm rings, and reconnect when the low-battery alarm reminds you. Turn on background monitoring so alerts can continue after you leave the app.\n\nSpending less time fully charged and avoiding frequent deep discharges can help reduce battery wear. Charging above 80% is not an immediate damage threshold; choose targets that suit your day. Fittery reminds you to unplug — it cannot stop charging automatically.',
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
            'Some phones, especially Xiaomi, Redmi, and POCO devices, restrict background apps to save power. First turn on background monitoring in Fittery and allow notifications. Then open your phone’s Settings → Apps → Fittery → Battery or Power, and select No restrictions or Unrestricted. On some Xiaomi phones, this is under Battery saver. Enable Autostart or Background autostart if available. Menu names vary by phone.\n\nFittery’s Settings includes Battery optimization and Autostart & background access shortcuts. The ongoing monitoring notification is part of Android’s background service. We’re working to improve background reliability, but device restrictions may still interrupt monitoring. If it keeps stopping, please report it by email.',
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
              builder: (ctx) => AlertDialog(
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
