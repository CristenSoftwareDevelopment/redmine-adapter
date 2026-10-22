import '../../models/alert_event.dart';
import 'alert_notifier_impl.dart';

class AlertNotifier {
  AlertNotifier._(this._impl);

  static final AlertNotifier instance = AlertNotifier._(createAlertNotifierImpl());

  final AlertNotifierImpl _impl;

  /// Called with the alert's query id when its OS notification is clicked.
  void Function(int queryId)? onClick;

  Future<void> init() => _impl.init();

  Future<void> showAlert({
    required AlertEvent alert,
    required String title,
    required String body,
  }) =>
      _impl.showAlert(
        alert: alert,
        title: title,
        body: body,
        onClick: () => onClick?.call(alert.queryId),
      );
}
