import '../../models/alert_event.dart';
import 'alert_notifier_impl_stub.dart'
    if (dart.library.io) 'alert_notifier_impl_io.dart'
    if (dart.library.html) 'alert_notifier_impl_web.dart';

abstract class AlertNotifierImpl {
  Future<void> init();

  Future<void> showAlert({
    required AlertEvent alert,
    required String title,
    required String body,
  });
}

AlertNotifierImpl createAlertNotifierImpl() => createAlertNotifierImplPlatform();
