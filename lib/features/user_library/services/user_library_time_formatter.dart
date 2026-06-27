String formatUserLibraryActivityTime(DateTime occurredAt, {DateTime? now}) {
  final currentTime = (now ?? DateTime.now()).toLocal();
  final localOccurredAt = occurredAt.toLocal();
  final difference = currentTime.difference(localOccurredAt);

  if (difference.inMinutes < 1) {
    return 'Az önce';
  }

  if (difference.inHours < 1) {
    return '${difference.inMinutes} dk önce';
  }

  if (_isSameDay(localOccurredAt, currentTime)) {
    return 'Bugün ${_formatTwoDigits(localOccurredAt.hour)}:'
        '${_formatTwoDigits(localOccurredAt.minute)}';
  }

  final yesterday = currentTime.subtract(const Duration(days: 1));
  if (_isSameDay(localOccurredAt, yesterday)) {
    return 'Dün';
  }

  final monthName = _monthShortNames[localOccurredAt.month - 1];
  if (localOccurredAt.year == currentTime.year) {
    return '${localOccurredAt.day} $monthName';
  }

  return '${localOccurredAt.day} $monthName ${localOccurredAt.year}';
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _formatTwoDigits(int value) => value.toString().padLeft(2, '0');

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
