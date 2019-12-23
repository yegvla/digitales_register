import 'dart:convert';
import 'dart:io';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:flutter/material.dart' hide Action, Notification;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:mutex/mutex.dart';
import 'package:requests/requests.dart';

import '../actions/absences_actions.dart';
import '../actions/app_actions.dart';
import '../actions/calendar_actions.dart';
import '../actions/dashboard_actions.dart';
import '../actions/grades_actions.dart';
import '../actions/login_actions.dart';
import '../actions/notifications_actions.dart';
import '../actions/routing_actions.dart';
import '../actions/save_pass_actions.dart';
import '../actions/settings_actions.dart';
import '../app_state.dart';
import '../data.dart';
import '../linux.dart';
import '../main.dart';
import '../serializers.dart';
import '../util.dart';
import '../wrapper.dart';

part 'absences.dart';
part 'calendar.dart';
part 'dashboard.dart';
part 'grades.dart';
part 'login.dart';
part 'notifications.dart';
part 'pass.dart';
part 'routing.dart';

final FlutterSecureStorage _secureStorage = getFlutterSecureStorage();
final _wrapper = Wrapper();

final middleware = [
  _errorMiddleware,
  _saveStateMiddleware,
  (MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
        ..add(LoginActionsNames.updateLogout, _tap)
        ..add(SettingsActionsNames.saveNoData, _saveNoData)
        ..add(AppActionsNames.deleteData, _deleteData)
        ..add(AppActionsNames.load, _load)
        ..add(DashboardActionsNames.refresh, _refresh)
        ..add(AppActionsNames.noInternet, _noInternet)
        ..add(AppActionsNames.refreshNoInternet, _refreshNoInternet)
        ..add(LoginActionsNames.loggedIn, _loggedIn)
        ..combine(_absencesMiddleware)
        ..combine(_calendarMiddleware)
        ..combine(_dashboardMiddleware)
        ..combine(_gradesMiddleware)
        ..combine(_loginMiddleware)
        ..combine(_notificationsMiddleware)
        ..combine(_passMiddleware)
        ..combine(_routingMiddleware))
      .build(),
];

NextActionHandler _errorMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) {
          void handleError(e) {
            print(e);
            navigatorKey.currentState.push(
              MaterialPageRoute(
                builder: (context) {
                  return Scaffold(
                    appBar: AppBar(
                      backgroundColor: Colors.red,
                      title: Text("Fehler!"),
                    ),
                    body: SingleChildScrollView(
                      child: Column(
                        children: <Widget>[
                          RaisedButton(
                            child: Text("In die Zwischenablage kopieren"),
                            onPressed: () => Clipboard.setData(
                                new ClipboardData(text: e.stackTrace)),
                          ),
                          Text(
                              "Ein unvorhergesehener Fehler ist aufgetreten:\n\n$e\n${e.stackTrace}"),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }

          if (action.name == AppActionsNames.error.name) {
            handleError(action.payload);
          } else {
            try {
              next(action);
            } catch (e) {
              handleError(e);
            }
          }
        };

void _tap(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) {
  _wrapper.interaction();
  // do not call next: this action is only to update the logout time
}

void _refreshNoInternet(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  next(action);
  if (await _wrapper.noInternet) {
    api.actions.noInternet(true);
  } else {
    api.actions.noInternet(false);

    api.actions.load();
  }
}

void _load(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) async {
  next(action);

  final login = json.decode(await _secureStorage.read(key: "login") ?? "{}");
  final user = login["user"];
  final pass = login["pass"];
  final url = login["url"] ??
      "https://vinzentinum.digitalesregister.it"; // be backwards compatible
  final offlineEnabled = login["offlineEnabled"];
  if (user != null && pass != null) {
    api.actions.loginActions.login(
      LoginAction(
        (b) => b
          ..user = user
          ..pass = pass
          ..url = url
          ..fromStorage = true
          ..offlineEnabled = offlineEnabled,
      ),
    );
  } else
    api.actions.routingActions.showLogin();
}

void _refresh(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) {
  next(action);
  api.actions.dashboardActions.load(api.state.dashboardState.future);
  api.actions.notificationsActions.load();
}

void _noInternet(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<bool> action) {
  if (action.payload) showToast(msg: "Kein Internet");
  next(action);
}

var _saveUnderway = false;

SettingsState _lastSettingsState;

void _loggedIn(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<LoggedInPayload> action) async {
  if (!api.state.settingsState.noPasswordSaving &&
      !action.payload.fromStorage) {
    api.actions.savePassActions.save();
  }

  if (!api.state.loginState.loggedIn) {
    final user = action.payload.username.hashCode;
    final file = File(
        "${(await getApplicationDocumentsDirectory()).path}/app_state_$user.json");
    final vals = json.decode(
      await file.exists() && await file.length() > 0
          ? await file.readAsString()
          : await _secureStorage.read(key: user.toString()) ?? "{}",
    );
    final dayState = vals["homework"] != null
        ? serializers.deserialize(vals["homework"]) as DashboardState
        : api.state.dashboardState;
    final gradesState = vals["grades"] != null
        ? serializers.deserialize(vals["grades"]) as GradesState
        : api.state.gradesState;
    final notificationState = vals["notifications"] != null
        ? serializers.deserialize(vals["notifications"]) as NotificationState
        : api.state.notificationState;
    final absenceState = vals["absences"] != null
        ? serializers.deserialize(vals["absences"]) as AbsencesState
        : api.state.absencesState;
    final calendarState = vals["calendar"] != null
        ? serializers.deserialize(vals["calendar"]) as CalendarState
        : api.state.calendarState;
    final settingsState = _lastSettingsState = vals["settings"] != null
        ? serializers.deserialize(vals["settings"]) as SettingsState
        : api.state.settingsState;
    api.actions.mountAppState(
      api.state.rebuild((b) => b
        ..dashboardState = (dayState.toBuilder()
          ..future = true
          ..blacklist ??= ListBuilder([]))
        ..gradesState = (gradesState.toBuilder()
          ..semester = gradesState.semester.toBuilder())
        ..notificationState = notificationState.toBuilder()
        ..absencesState = absenceState?.toBuilder()
        ..calendarState = calendarState.toBuilder()
        ..settingsState = settingsState.toBuilder()),
    );

    // next not at the beginning: bug fix (serialization)
    next(action);

    api.actions.settingsActions.saveNoPass(settingsState.noPasswordSaving);

    if (api.state.currentRouteIsLogin) {
      navigatorKey.currentState.pop();
      api.actions.isLoginRoute(false);
    }
  } else {
    next(action);
  }
  api.actions.dashboardActions.load(api.state.dashboardState.future);
  api.actions.notificationsActions.load();
}

var _lastSave = "";

NextActionHandler _saveStateMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) {
          next(action);
          if (!_saveUnderway &&
              api.state.loginState.loggedIn &&
              api.state.loginState.userName != null) {
            final user = api.state.loginState.userName.hashCode;
            final delay = action.name == AppActionsNames.saveState.name
                ? Duration.zero
                : Duration(seconds: 5);
            _saveUnderway = true;
            Future.delayed(delay, () async {
              _saveUnderway = false;
              if (!api.state.settingsState.noDataSaving) {
                final save = json.encode({
                  "grades": serializers.serialize(api.state.gradesState),
                  "homework": serializers.serialize(api.state.dashboardState),
                  "calendar": serializers.serialize(api.state.calendarState),
                  "absences": api.state.absencesState != null
                      ? serializers.serialize(api.state.absencesState)
                      : null,
                  "notifications":
                      serializers.serialize(api.state.notificationState),
                  "settings": serializers.serialize(api.state.settingsState),
                });
                if (_lastSave == save) return;
                _writeToStorage(
                  user.toString(),
                  save,
                );
              } else {
                if (_lastSettingsState != api.state.settingsState)
                  _writeToStorage(
                    user.toString(),
                    json.encode(
                      {
                        "settings":
                            serializers.serialize(api.state.settingsState),
                      },
                    ),
                  );
                _lastSettingsState = api.state.settingsState;
              }
            });
          }
        };

Future<File> _storageFile(String key) async {
  return File(
      "${(await getApplicationDocumentsDirectory()).path}/app_state_$key.json");
}

void _writeToStorage(String key, String txt) async {
  (await _storageFile(key)).writeAsString(txt, flush: true);
}

void _saveNoData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) {
  next(action);
  api.actions.saveState();
}

void _deleteData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  next(action);
  final file = await _storageFile(
    api.state.loginState.userName.hashCode.toString(),
  );
  file.delete();
}
