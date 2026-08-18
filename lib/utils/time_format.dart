/// Formats the [time] for the header clock, honoring the user's
/// 12/24-hour clock preference.
///
/// When [use12Hour] is false (default), returns 24-hour format (e.g. `14:09`).
/// When true, returns 12-hour format with an AM/PM suffix (e.g. `2:09 PM`),
/// mapping midnight to `12:00 AM` and noon to `12:00 PM`.
String formatClockTime(DateTime time, {required bool use12Hour}) {
  final minute = time.minute.toString().padLeft(2, '0');
  if (!use12Hour) {
    return '${time.hour}:$minute';
  }
  final period = time.hour < 12 ? 'AM' : 'PM';
  int hour12 = time.hour % 12;
  if (hour12 == 0) hour12 = 12;
  return '$hour12:$minute $period';
}

/// The widest string [formatClockTime] can return for this setting.
///
/// Header geometry is sized off this rather than the current time, so the
/// layout cannot shift as the clock ticks: 24-hour hours are not zero-padded,
/// so a two-digit hour is the widest, and the 12-hour form adds the period
/// suffix. 'AM' and 'PM' are treated as equally wide.
String widestClockText({required bool use12Hour}) =>
    use12Hour ? '12:59 PM' : '23:59';
