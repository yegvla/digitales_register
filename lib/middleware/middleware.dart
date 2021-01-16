import 'dart:convert';
import 'dart:io';

import 'package:built_redux/built_redux.dart';
import 'package:dio/dio.dart' as dio;
import 'package:dr/actions/messages_actions.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/certificate_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:flutter/material.dart' hide Action, Notification;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:mutex/mutex.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../actions/absences_actions.dart';
import '../actions/app_actions.dart';
import '../actions/calendar_actions.dart';
import '../actions/certificate_actions.dart';
import '../actions/dashboard_actions.dart';
import '../actions/grades_actions.dart';
import '../actions/login_actions.dart';
import '../actions/notifications_actions.dart';
import '../actions/profile_actions.dart';
import '../actions/routing_actions.dart';
import '../actions/save_pass_actions.dart';
import '../actions/settings_actions.dart';
import '../app_state.dart';
import '../data.dart';
import '../desktop.dart';
import '../main.dart';
import '../serializers.dart';
import '../util.dart';
import '../wrapper.dart';

part 'absences.dart';
part 'calendar.dart';
part 'certificate.dart';
part 'dashboard.dart';
part 'grades.dart';
part 'login.dart';
part 'notifications.dart';
part 'pass.dart';
part 'profile.dart';
part 'routing.dart';
part 'messages.dart';

final FlutterSecureStorage _secureStorage = getFlutterSecureStorage();
var _wrapper = Wrapper();

final middleware = [
  _errorMiddleware,
  _saveStateMiddleware,
  (MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
        ..add(LoginActionsNames.updateLogout, _tap)
        ..add(SettingsActionsNames.saveNoData, _saveNoData)
        ..add(AppActionsNames.deleteData, _deleteData)
        ..add(AppActionsNames.load, _load)
        ..add(AppActionsNames.start, _start)
        ..add(DashboardActionsNames.refresh, _refresh)
        ..add(AppActionsNames.refreshNoInternet, _refreshNoInternet)
        ..add(LoginActionsNames.loggedIn, _loggedIn)
        ..add(AppActionsNames.restarted, _restarted)
        ..combine(_absencesMiddleware)
        ..combine(_calendarMiddleware)
        ..combine(_dashboardMiddleware)
        ..combine(_gradesMiddleware)
        ..combine(_loginMiddleware)
        ..combine(_notificationsMiddleware)
        ..combine(_passMiddleware)
        ..combine(_routingMiddleware)
        ..combine(_certificateMiddleware)
        ..combine(_messagesMiddleware)
        ..combine(_profileMiddleware))
      .build(),
];

NextActionHandler _errorMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) {
          void handleError(e) {
            print(e);
            var stackTrace = "";
            try {
              stackTrace = e.stackTrace.toString();
            } catch (e) {}
            navigatorKey.currentState.push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) {
                  return Scaffold(
                    appBar: AppBar(
                      backgroundColor: Colors.red,
                      title: Text("Fehler!"),
                    ),
                    body: SingleChildScrollView(
                      child: Column(
                        children: <Widget>[
                          ElevatedButton(
                            child: Text("In die Zwischenablage kopieren"),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: "$e\n\n$stackTrace",
                                ),
                              );
                              showSnackBar(
                                "In die Zwischenablage kopiert",
                              );
                            },
                          ),
                          Text(
                              "Ein unvorhergesehener Fehler ist aufgetreten:\n\n$e\n\n$stackTrace"),
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
  final noInternet = await _wrapper.noInternet;
  final prevNoInternet = api.state.noInternet;
  if (prevNoInternet != noInternet) {
    if (noInternet) {
      showSnackBar("Kein Internet");
      _wrapper.logout(
        hard: false,
        logoutForcedByServer: true,
      );
    }
    api.actions.noInternet(noInternet);
    api.actions.load();
  }
}

void _load(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) async {
  next(action);
  if (!api.state.noInternet) _popAll();
  final login = json.decode(await _secureStorage.read(key: "login") ?? "{}");
  final user = login["user"];
  final pass = login["pass"];
  final url = login["url"] ??
      "https://vinzentinum.digitalesregister.it"; // be backwards compatible
  final offlineEnabled = login["offlineEnabled"];
  if ((api.state.url != null && api.state.url != url) ||
      (api.state.loginState.username != null &&
          api.state.loginState.username != user)) {
    api.actions.savePassActions.delete();
    api.actions.routingActions.showLogin();
  } else {
    api.actions.setUrl(url);
    if (user != null && pass != null) {
      api.actions.loginActions.login(
        LoginPayload(
          (b) => b
            ..user = user
            ..pass = pass
            ..url = url
            ..fromStorage = true
            ..offlineEnabled = offlineEnabled,
        ),
      );
    } else {
      api.actions.routingActions.showLogin();
    }
  }
}

void _refresh(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) {
  next(action);
  api.actions.dashboardActions.load(api.state.dashboardState.future);
  api.actions.notificationsActions.load();
}

void _loggedIn(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<LoggedInPayload> action) async {
  if (!api.state.settingsState.noPasswordSaving &&
      !action.payload.fromStorage) {
    api.actions.savePassActions.save();
  }
  _deletedData = false;
  final key = getStorageKey(action.payload.username, _wrapper.loginAddress);
  if (!api.state.loginState.loggedIn) {
    final state = await _readFromStorage(key);
    if (state != null) {
      try {
        final serializedState = serializers.deserialize(json.decode(state));
        if (serializedState is SettingsState) {
          api.actions.mountAppState(
            api.state.rebuild(
              (b) => b
                ..settingsState.replace(
                  serializedState,
                ),
            ),
          );
        } else if (serializedState is AppState) {
          final currentState = api.state;
          api.actions.mountAppState(
            serializedState.rebuild(
              (b) => b
                ..loginState.replace(currentState.loginState)
                ..noInternet = currentState.noInternet
                ..config = currentState.config?.toBuilder()
                ..dashboardState.future = true
                ..gradesState.semester.replace(
                      currentState.gradesState.semester == Semester.all
                          ? serializedState.gradesState.semester
                          : currentState.gradesState.semester,
                    ),
            ),
          );
        }

        // next not at the beginning: bug fix (serialization)
        next(action);

        api.actions.settingsActions
            .saveNoPass(api.state.settingsState.noPasswordSaving);
      } catch (e) {
        showSnackBar("Fehler beim Laden der gespeicherten Daten");
        print(e);
        next(action);
      }
    } else {
      next(action);
    }

    _popAll();
  } else {
    next(action);
  }
  api.state.loginState.callAfterLogin.forEach((f) => f());
  api.actions.dashboardActions.load(api.state.dashboardState.future);
  api.actions.notificationsActions.load();
}

var _saveUnderway = false;

var _lastSave = "";
String _lastUsernameSaved;
AppState _stateToSave;
// This is to avoid saving data in an action right after deleting data,
// which would restore it.
bool _deletedData = false;

NextActionHandler _saveStateMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) {
          next(action);
          if (api.state.loginState.loggedIn &&
              api.state.loginState.username != null) {
            _stateToSave = api.state;
            final bool immediately =
                action.name == AppActionsNames.saveState.name;
            if (_saveUnderway && !immediately) {
              return;
            }
            final user = getStorageKey(
                _stateToSave.loginState.username, _wrapper.loginAddress);
            _saveUnderway = true;

            void save() {
              _saveUnderway = false;
              String toSave;
              if (!_stateToSave.settingsState.noDataSaving && !_deletedData) {
                toSave = json.encode(
                  serializers.serialize(_stateToSave),
                );
              } else {
                toSave = json.encode(
                  serializers.serialize(_stateToSave.settingsState),
                );
              }
              if (_lastSave == toSave && _lastUsernameSaved == user) return;
              _lastSave = toSave;
              _lastUsernameSaved = user;
              _writeToStorage(
                user,
                toSave,
              );
            }

            if (immediately)
              save();
            else
              Future.delayed(Duration(seconds: 5), save);
          }
        };

String getStorageKey(String user, String server) {
  return json.encode({"username": user, "server_url": server});
}

void _writeToStorage(String key, String txt) async {
  await _secureStorage.write(key: key, value: txt);
}

Future<String> _readFromStorage(String key) async {
  return await _secureStorage.read(key: key);
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
  _deletedData = true;
  api.actions.saveState();
}

void _restarted(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) {
  next(action);
  if (DateTime.now().difference(_wrapper.lastInteraction).inMinutes > 3) {
    _popAll();
    api.actions.loginActions.clearAfterLoginCallbacks();
    api.actions.load();
  }
}

void _start(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<Uri> action,
) {
  api.actions.loginActions.clearAfterLoginCallbacks();
  if (action.payload != null) {
    api.actions.setUrl(action.payload.origin);
    final parameters = action.payload.queryParameters;
    switch (parameters["semesterWechsel"]) {
      case "1":
        api.actions.loginActions.addAfterLoginCallback(
          () => api.actions.gradesActions.setSemester(Semester.first),
        );
        break;
      case "2":
        api.actions.loginActions.addAfterLoginCallback(
          () => api.actions.gradesActions.setSemester(Semester.second),
        );
    }
    switch (action.payload.path) {
      case "":
      case "/v2/":
        break;
      case "/v2/login":
        if (parameters["resetmail"] == "true") {
          final email = parameters["email"];
          final token = parameters["token"];
          api.actions.routingActions.showPassReset(
            ShowPassResetPayload(
              (b) => b
                ..token = token
                ..email = email,
            ),
          );
          return;
        }
        if (parameters["username"] != null) {
          api.actions.loginActions.setUsername(parameters["username"]);
        }
        if (parameters["redirect"] != null) {
          redirectAfterLogin(parameters["redirect"].replaceFirst("#", ""), api);
        }
        break;
      default:
        showSnackBar("Dieser Link konnte nicht geöffnet werden");
    }
    redirectAfterLogin(action.payload.fragment, api);
  }
  api.actions.load();
}

void redirectAfterLogin(
    String location, MiddlewareApi<AppState, AppStateBuilder, AppActions> api) {
  switch (location) {
    case "":
    case "dashboard/student":
      break;
    case "student/absences":
      api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showAbsences,
      );
      break;
    case "calendar/student":
      api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showCalendar,
      );
      break;
    case "student/subjects":
      api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showGrades,
      );
      break;
    case "student/certificate":
      api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showCertificate,
      );
      break;
    case "message/list":
      api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showMessages,
      );
      break;
    default:
      showSnackBar("Dieser Link konnte nicht geöffnet werden");
  }
}

void _popAll() {
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
  nestedNavKey.currentState?.popUntil((route) => route.isFirst);
}
