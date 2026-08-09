import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Notification types supported by the global notification center.
enum GlobalNotificationType { info, success, error }

/// Immutable data holder for a global notification.
class GlobalNotificationData {
  final String id;
  final String message;
  final String? title;
  final Uint8List? imageBytes;
  final IconData? icon;
  final GlobalNotificationType type;
  final double? progress;

  const GlobalNotificationData({
    required this.id,
    required this.message,
    this.title,
    this.imageBytes,
    this.icon,
    required this.type,
    this.progress,
  });
}

/// Application-wide notification center.
///
/// Notifications are kept in an ordered list exposed through [notifier]. The
/// header notification bell renders the list in a dropdown, including progress
/// bars. There is no floating overlay; every notification lives in the dropdown.
///
/// Notifications never auto-dismiss: they stay listed until the user dismisses
/// them, either individually or with the "Clear all" action in the dropdown.
class GlobalNotificationService {
  static final GlobalNotificationService _instance =
      GlobalNotificationService._internal();
  factory GlobalNotificationService() => _instance;
  GlobalNotificationService._internal();

  final ValueNotifier<List<GlobalNotificationData>> notifier = ValueNotifier(
    [],
  );

  /// Displays a notification. If a notification with the same [id] is already
  /// active, it is updated in place and moved to the end (most recent).
  void show({
    required String id,
    required String message,
    String? title,
    Uint8List? imageBytes,
    IconData? icon,
    GlobalNotificationType type = GlobalNotificationType.info,
    double? progress,
  }) {
    final current = notifier.value;
    final existingIndex = current.indexWhere((n) => n.id == id);
    final updated = GlobalNotificationData(
      id: id,
      message: message,
      title: title,
      imageBytes: imageBytes,
      icon: icon,
      type: type,
      progress: progress,
    );

    if (existingIndex == -1) {
      notifier.value = [...current, updated];
    } else {
      final copy = List<GlobalNotificationData>.from(current);
      copy.removeAt(existingIndex);
      copy.add(updated);
      notifier.value = copy;
    }
  }

  /// Updates an active notification only if its [id] exists.
  void update({
    required String id,
    required String message,
    String? title,
    Uint8List? imageBytes,
    IconData? icon,
    GlobalNotificationType? type,
    double? progress,
  }) {
    final current = notifier.value;
    final index = current.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final existing = current[index];

    notifier.value = [
      ...current.sublist(0, index),
      GlobalNotificationData(
        id: id,
        message: message,
        title: title ?? existing.title,
        imageBytes: imageBytes ?? existing.imageBytes,
        icon: icon ?? existing.icon,
        type: type ?? existing.type,
        progress: progress ?? existing.progress,
      ),
      ...current.sublist(index + 1),
    ];
  }

  /// Removes the notification with the given [id], or clears all notifications
  /// when no [id] is provided.
  void dismiss([String? id]) {
    if (id == null) {
      notifier.value = [];
      return;
    }

    notifier.value = notifier.value.where((n) => n.id != id).toList();
  }
}
