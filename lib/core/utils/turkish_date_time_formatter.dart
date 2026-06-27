String formatTurkishRelativeDateTime(DateTime dateTime, {DateTime? now}) {
  final currentTime = (now ?? DateTime.now()).toLocal();
  final localDateTime = dateTime.toLocal();
  final difference = currentTime.difference(localDateTime);

  if (difference.inMinutes < 1) {
    return 'Az önce';
  }

  if (difference.inHours < 1) {
    return '${difference.inMinutes} dk önce';
  }

  if (_isSameDay(localDateTime, currentTime)) {
    return 'Bugün ${_twoDigits(localDateTime.hour)}:'
        '${_twoDigits(localDateTime.minute)}';
  }

  final yesterday = currentTime.subtract(const Duration(days: 1));
  if (_isSameDay(localDateTime, yesterday)) {
    return 'Dün ${_twoDigits(localDateTime.hour)}:'
        '${_twoDigits(localDateTime.minute)}';
  }

  return '${localDateTime.day} ${_monthShortNames[localDateTime.month - 1]} '
      '${localDateTime.year}';
}

String formatTurkishDateTime(DateTime dateTime) {
  final localDateTime = dateTime.toLocal();
  return '${localDateTime.day} ${_monthShortNames[localDateTime.month - 1]} '
      '${localDateTime.year} '
      '${_twoDigits(localDateTime.hour)}:${_twoDigits(localDateTime.minute)}';
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

const _monthShortNames = <String>[
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];
