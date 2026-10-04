class DurationFormatter {
  DurationFormatter._();

  /// Formata uma [Duration] como `m:ss` ou `h:mm:ss` quando aplicável.
  static String format(Duration duration) {
    if (duration.isNegative || duration == Duration.zero) return '0:00';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final secondsStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final minutesStr = minutes.toString().padLeft(2, '0');
      return '$hours:$minutesStr:$secondsStr';
    }
    return '$minutes:$secondsStr';
  }

  static String formatMs(int milliseconds) {
    return format(Duration(milliseconds: milliseconds));
  }
}
