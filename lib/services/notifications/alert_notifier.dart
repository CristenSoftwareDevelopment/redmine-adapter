import '../../models/alert_event.dart';
import 'alert_notifier_impl.dart';

class AlertNotifier {
  AlertNotifier._(this._impl);

  static final AlertNotifier instance = AlertNotifier._(createAlertNotifierImpl());

  final AlertNotifierImpl _impl;

  Future<void> init() => _impl.init();

  Future<void> showAlert({
    required AlertEvent alert,
    required String title,
    required String body,
  }) =>
      _impl.showAlert(alert: alert, title: title, body: body);
}
