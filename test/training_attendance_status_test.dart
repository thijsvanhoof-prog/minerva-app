import 'package:flutter_test/flutter_test.dart';
import 'package:minerva_app/ui/trainingen_wedstrijden/training_attendance_status.dart';

void main() {
  group('training attendance status', () {
    test('normaliseert alle spelend-varianten', () {
      for (final value in ['playing', 'aanwezig', 'present']) {
        expect(
          parseTrainingAttendanceKind(value),
          TrainingAttendanceKind.playing,
        );
      }
    });

    test('normaliseert trainer en coach', () {
      expect(
        parseTrainingAttendanceKind('coach'),
        TrainingAttendanceKind.coach,
      );
      expect(
        parseTrainingAttendanceKind('trainer'),
        TrainingAttendanceKind.coach,
      );
    });

    test('normaliseert alle niet-spelend-varianten', () {
      for (final value in ['niet_spelend', 'nietspelend', 'not_playing']) {
        expect(
          parseTrainingAttendanceKind(value),
          TrainingAttendanceKind.notPlaying,
        );
      }
    });

    test('normaliseert alle afmeldvarianten', () {
      for (final value in ['afgemeld', 'afwezig', 'absent', 'declined']) {
        expect(
          parseTrainingAttendanceKind(value),
          TrainingAttendanceKind.declined,
        );
      }
    });

    test('profile ids worden consistent vergeleken', () {
      expect(normalizeProfileId('  ABC-123 '), 'abc-123');
      expect(normalizeProfileId(null), isEmpty);
    });
  });
}
