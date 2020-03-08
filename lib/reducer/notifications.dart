import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/messages_actions.dart';

import '../actions/notifications_actions.dart';
import '../app_state.dart';
import '../data.dart';

final notificationsReducerBuilder = NestedReducerBuilder<AppState,
    AppStateBuilder, NotificationState, NotificationStateBuilder>(
  (s) => s.notificationState,
  (b) => b.notificationState,
)
  ..add(NotificationsActionsNames.loaded, _loaded)
  ..add(NotificationsActionsNames.delete, _delete)
  ..add(NotificationsActionsNames.deleteAll, _deleteAll)
  ..add(MessagesActionsNames.markAsRead, _markMessageAsRead);

void _loaded(NotificationState state, Action<Object> action,
    NotificationStateBuilder builder) {
  builder.notifications = _parseNotifications(action.payload);
}

ListBuilder<Notification> _parseNotifications(data) {
  return ListBuilder(
    data.map(
      (n) => Notification(
        (b) => b
          ..id = n["id"]
          ..title = n["title"]
          ..type = n["type"]
          ..objectId = n["objectId"]
          ..subTitle = n["subTitle"]
          ..timeSent = DateTime.parse(
            n["timeSent"],
          ),
      ),
    ),
  );
}

void _markMessageAsRead(NotificationState state, Action<int> action,
    NotificationStateBuilder builder) {
  builder.notifications.removeWhere((n) => n.objectId == action.payload);
}

void _delete(NotificationState state, Action<Notification> action,
    NotificationStateBuilder builder) {
  builder.notifications.remove(action.payload);
}

void _deleteAll(NotificationState state, Action<void> action,
    NotificationStateBuilder builder) {
  builder.notifications.removeWhere((n) => n.type != "message");
}
