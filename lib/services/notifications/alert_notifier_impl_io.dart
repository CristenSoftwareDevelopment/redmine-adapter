import 'package:local_notifier/local_notifier.dart';

import '../../models/alert_event.dart';
import 'alert_notifier_impl.dart';

class _DesktopAlertNotifierImpl implements AlertNotifierImpl {
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    await localNotifier.setup(
      appName: 'Redmine Monitor',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );

    _initialized = true;
  }

  @override
  Future<void> showAlert({
    required AlertEvent alert,
    required String title,
    required String body,
  }) async {
    await init();

    final notification = LocalNotification(
      title: title,
      body: body,
    );

    await notification.show();
  }
}

AlertNotifierImpl createAlertNotifierImplPlatform() => _DesktopAlertNotifierImpl();
