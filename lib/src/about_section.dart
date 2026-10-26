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
            'Why didn’t my charging-limit alarm ring?',
            'Turn the Charging limit switch on, allow notifications, and connect power. An enabled 80% target should alert immediately when the phone is already at 88%. Selecting a target again re-arms it. Silence acknowledges that target for this connection; unrelated settings do not re-trigger it. Also check Alarm sound, the chosen tone, and system alarm volume.',
          ),
          faq(
            'Does the alarm stop charging?',
            'No. It reminds you to unplug. Android does not let an ordinary app enforce a hardware charging cutoff.',
          ),
          faq(
            'Why does a laptop charge so slowly?',
            'The phone can consume much of the available input power. Net battery current may be small or negative even while power is connected. Fittery shows battery-side power, which differs from charger or adapter wattage.',
          ),
          faq(
            'Why is time until full unavailable?',
            'The app needs reliable positive charging progress. It can form a provisional estimate from about 30 seconds of recent net-current readings, then prefer charge-counter or battery-level trends. When charge is not increasing, a reliable finish time cannot be calculated. Phone use and charging taper can change the estimate.',
          ),
          faq(
            'How accurate are current, watts, and health?',
            'Current is read from Android’s battery sensor. Auto starts with Android’s signed µA convention and can calibrate units/polarity against sustained charge-counter changes. It never changes units just because one reading gets small. Watts are voltage × net current. Health is an approximate capacity ratio, with a rough gauge fallback clearly labeled. Firmware may omit or misreport readings; Diagnostics shows the source values.',
          ),
          faq(
            'Does history contain example data?',
            'No example records are inserted. Charts and sessions use saved measurements. Missing recordings stay blank. Only the latest 10 sessions are kept, and sessions expire 72 hours after they start. Their readings and daily totals are deleted together during history reads and recording. Network readings are never saved. Background monitoring is needed to keep recording battery data after you leave the app.',
          ),
          faq(
            'Why is a monitoring notification needed?',
            'Android uses a visible foreground service for ongoing background work. Phone-specific battery restrictions can still interrupt it. Battery optimization and autostart settings are linked above.',
          ),
          faq(
            'What does network activity measure?',
            'Enable Network activity on Dashboard to see device-wide download and upload traffic, refreshed every second. It includes other apps and local traffic and is not an internet speed test. VPNs and multiple connections can affect attribution. Network readings are never saved to history. Sampling stops when you leave Dashboard, open a battery graph, or background the app. Android may hide Wi-Fi names; Fittery does not request location permission to reveal them.',
          ),
        ]),
        heading('Developer details'),
        group([
          const ListTile(
            leading: Icon(Icons.code_rounded),
            title: Text(developerName),
            subtitle: Text(developerCredit),
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
