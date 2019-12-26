part of 'middleware.dart';

final _calendarMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(CalendarActionsNames.load, _loadCalendar);

void _loadCalendar(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<DateTime> action) async {
  if (api.state.noInternet) return;

  next(action);
  final data = await _wrapper.post("/api/calendar/student",
      {"startDate": DateFormat("yyyy-MM-dd").format(action.payload)});

  if (data != null) {
    api.actions.calendarActions.loaded(data);
  } else {
    api.actions.refreshNoInternet();
  }
}
