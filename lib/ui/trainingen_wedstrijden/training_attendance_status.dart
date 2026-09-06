enum TrainingAttendanceKind { playing, coach, notPlaying, declined }

String normalizeProfileId(Object? value) =>
    (value ?? '').toString().trim().toLowerCase();

TrainingAttendanceKind? parseTrainingAttendanceKind(Object? value) {
  final status = (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  switch (status) {
    case 'playing':
    case 'aanwezig':
    case 'present':
      return TrainingAttendanceKind.playing;
    case 'coach':
    case 'trainer':
      return TrainingAttendanceKind.coach;
    case 'niet_spelend':
    case 'nietspelend':
    case 'not_playing':
      return TrainingAttendanceKind.notPlaying;
    case 'afgemeld':
    case 'afwezig':
    case 'absent':
    case 'declined':
      return TrainingAttendanceKind.declined;
    default:
      return null;
  }
}
