/// A selected calendar window containing only observations returned by storage.
/// Null daily values mean no recording; zero means a recorded day with no gain.
class HistoryWindow {
  HistoryWindow({
    required List<Map<String, dynamic>> daily,
    required List<Map<String, dynamic>> sessions,
    required this.days,
    required this.now,
    this.since,
  }) {
    firstDay = since == null
        ? DateTime(now.year, now.month, now.day - days + 1)
        : DateTime(since!.year, since!.month, since!.day);
    final firstOrdinal = DateTime.utc(
      firstDay.year,
      firstDay.month,
      firstDay.day,
    );
    chargedPerDay = List<double?>.filled(days, null);
    for (final entry in daily) {
      final date = DateTime.tryParse(entry['day']?.toString() ?? '');
      final gain = entry['charged'];
      final plugged = entry['pluggedMs'];
      if (date == null ||
          gain is! num ||
          !gain.isFinite ||
          gain < 0 ||
          plugged is! num ||
          !plugged.isFinite ||
          plugged < 0) {
        continue;
      }
      final index = DateTime.utc(
        date.year,
        date.month,
        date.day,
      ).difference(firstOrdinal).inDays;
      if (index < 0 || index >= days) continue;
      chargedPerDay[index] = (chargedPerDay[index] ?? 0) + gain.toDouble();
      chargedPercent += gain.toDouble();
      pluggedMs += plugged.toInt();
    }
    this.sessions = sessions.where((s) {
      final start = s['startTime'], end = s['endTime'];
      return start is num &&
          end is num &&
          start.isFinite &&
          end.isFinite &&
          end >= start &&
          end >= (since ?? firstDay).millisecondsSinceEpoch &&
          start <= now.millisecondsSinceEpoch;
    }).toList();
  }
  final int days;
  final DateTime now;
  final DateTime? since;
  late final DateTime firstDay;
  late final List<double?> chargedPerDay;
  late final List<Map<String, dynamic>> sessions;
  double chargedPercent = 0;
  int pluggedMs = 0;
  bool get hasObservations => chargedPerDay.any((v) => v != null);
}
