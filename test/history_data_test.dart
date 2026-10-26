import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/history_data.dart';

void main() {
  final now = DateTime(2026, 10, 26, 12);
  test(
    'Unrecorded days are unknown rather than invented zero observations',
    () {
      final history = HistoryWindow(daily: [], sessions: [], days: 7, now: now);
      expect(history.chargedPerDay, List<double?>.filled(7, null));
      expect(history.hasObservations, isFalse);
      expect(history.sessions, isEmpty);
    },
  );
  test(
    'Recorded zero days differ from unrecorded days and totals respect the range',
    () {
      final daily = <Map<String, dynamic>>[
        {'day': '2026-10-18', 'charged': 5.0, 'pluggedMs': 600000},
        {'day': '2026-10-20', 'charged': 0.0, 'pluggedMs': 0},
        {'day': '2026-10-25', 'charged': 30.0, 'pluggedMs': 1800000},
        {'day': '2026-10-27', 'charged': 100.0, 'pluggedMs': 600000},
      ];
      final week = HistoryWindow(daily: daily, sessions: [], days: 7, now: now);
      expect(week.chargedPerDay[0], 0.0);
      expect(week.chargedPerDay[1], isNull);
      expect(week.chargedPercent, 30.0);
      expect(week.pluggedMs, 1800000);
      final month = HistoryWindow(
        daily: daily,
        sessions: [],
        days: 30,
        now: now,
      );
      expect(month.chargedPercent, 35.0);
      expect(month.pluggedMs, 2400000);
    },
  );
  test('The session list follows the selected calendar window', () {
    Map<String, dynamic> session(int day, int endDay) => {
      'startTime': DateTime(2026, 10, day).millisecondsSinceEpoch,
      'endTime': DateTime(2026, 10, endDay, 1).millisecondsSinceEpoch,
    };
    final sessions = [
      session(18, 18),
      session(19, 20),
      session(25, 25),
      session(27, 27),
    ];
    final week = HistoryWindow(
      daily: [],
      sessions: sessions,
      days: 7,
      now: now,
    );
    expect(week.sessions, [sessions[1], sessions[2]]);
    final month = HistoryWindow(
      daily: [],
      sessions: sessions,
      days: 30,
      now: now,
    );
    expect(month.sessions, sessions.take(3).toList());
  });
  test('Malformed summaries cannot produce artificial chart values', () {
    final history = HistoryWindow(
      daily: [
        {'day': 'invalid', 'charged': 100.0, 'pluggedMs': 60000},
        {'day': '2026-10-25', 'charged': double.nan, 'pluggedMs': 60000},
        {'day': '2026-10-25', 'charged': -1, 'pluggedMs': 60000},
      ],
      sessions: [],
      days: 7,
      now: now,
    );
    expect(history.hasObservations, isFalse);
  });

  test('Three-day history includes the earliest partial calendar day', () {
    final since = now.subtract(const Duration(days: 3));
    final history = HistoryWindow(
      daily: [
        {'day': '2026-10-23', 'charged': 10.0, 'pluggedMs': 60000},
        {'day': '2026-10-26', 'charged': 5.0, 'pluggedMs': 30000},
      ],
      sessions: [
        {
          'startTime': since.millisecondsSinceEpoch + 1000,
          'endTime': since.millisecondsSinceEpoch + 30000,
        },
        {
          'startTime': since.millisecondsSinceEpoch - 60000,
          'endTime': since.millisecondsSinceEpoch - 1000,
        },
      ],
      days: 4,
      now: now,
      since: since,
    );
    expect(history.chargedPerDay, [10.0, null, null, 5.0]);
    expect(history.chargedPercent, 15);
    expect(history.sessions.length, 1);
  });
}
