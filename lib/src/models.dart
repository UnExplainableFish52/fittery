import 'package:flutter/material.dart';

const mint = Color(0xFF35D0BD);
const coral = Color(0xFFF58C87);

class Reading {
  Reading(this.data);
  final Map<String, dynamic> data;
  num? number(String key) => data[key] is num ? data[key] as num : null;
  String text(String key, [String fallback = 'Unavailable']) =>
      data[key]?.toString() ?? fallback;
  int? get level => number('level')?.toInt();
  bool get charging => data['status'] == 'Charging';
  bool get plugged => (number('plugged') ?? 0) > 0;
  double? get current => number('currentMa')?.toDouble();
  double? voltage(bool dual) => number('voltageMv')?.toDouble() == null
      ? null
      : number('voltageMv')!.toDouble() * (dual ? 2 : 1);
  double? power(bool dual) => voltage(dual) == null || current == null
      ? null
      : voltage(dual)! * current! / 1000000;
}

String metric(
  num? value,
  String unit, {
  int decimals = 0,
  bool signed = false,
}) {
  if (value == null || !value.isFinite) return '—';
  return '${signed && value > 0 ? '+' : ''}${value.toStringAsFixed(decimals)} $unit';
}

String durationLabel(num? millis) {
  if (millis == null || millis < 0) return 'Unavailable';
  if (millis == 0) return '0 min';
  final minutes = (millis / 60000).round();
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String networkRate(num? bytesPerSecond) {
  if (bytesPerSecond == null ||
      !bytesPerSecond.isFinite ||
      bytesPerSecond < 0) {
    return '—';
  }
  final bits = bytesPerSecond * 8;
  return bits >= 1000000
      ? '${(bits / 1000000).toStringAsFixed(2)} Mbps'
      : '${(bits / 1000).toStringAsFixed(1)} Kbps';
}

String memorySize(num? bytes) => bytes == null || bytes <= 0
    ? 'Unavailable'
    : '${(bytes / 1073741824).toStringAsFixed(1)} GiB';

const defaults = <String, dynamic>{
  'theme': 'Dark',
  'fahrenheit': false,
  'millivolts': false,
  'dualCell': false,
  'currentUnit': 'Auto',
  'currentPolarity': 'Auto',
  'chargeAlert': false,
  'chargeLimit': 80,
  'lowAlert': false,
  'lowLimit': 20,
  'heatAlert': false,
  'heatLimit': 40,
  'sound': true,
  'lockScreen': true,
  'notificationFormat': 'All metrics',
  'networkEnabled': false,
};
