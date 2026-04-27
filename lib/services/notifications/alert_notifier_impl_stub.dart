import '../../models/alert_event.dart';
import 'alert_notifier_impl.dart';

class _NoopAlertNotifierImpl implements AlertNotifierImpl {
  @override
  Future<void> init() async {}

  @override
  Future<void> showAlert({
    required AlertEvent alert,
    required String title,
    required String body,
  }) async {}
}

AlertNotifierImpl createAlertNotifierImplPlatform() => _NoopAlertNotifierImpl();
