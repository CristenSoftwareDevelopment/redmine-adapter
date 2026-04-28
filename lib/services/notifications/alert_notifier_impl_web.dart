// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../../models/alert_event.dart';
import 'alert_notifier_impl.dart';

class _WebAlertNotifierImpl implements AlertNotifierImpl {
  bool _permissionRequested = false;

  @override
  Future<void> init() async {
    await _ensurePermission();
  }

  @override
  Future<void> showAlert({
    required AlertEvent alert,
    required String title,
    required String body,
  }) async {
    final granted = await _ensurePermission();
    if (!granted) {
      return;
    }

    html.Notification(
      title,
      body: body,
      tag: 'redmine-monitor-${alert.queryId}',
    );
  }

  Future<bool> _ensurePermission() async {
    final current = html.Notification.permission;
    if (current == 'granted') {
      return true;
    }

    if (current == 'denied') {
      return false;
    }

    if (_permissionRequested) {
      return false;
    }

    _permissionRequested = true;
    final next = await html.Notification.requestPermission();
    return next == 'granted';
  }
}

AlertNotifierImpl createAlertNotifierImplPlatform() => _WebAlertNotifierImpl();
