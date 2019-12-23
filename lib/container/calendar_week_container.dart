import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

import '../actions/app_actions.dart';
import '../app_state.dart';
import '../data.dart';
import '../ui/calendar_week.dart';

class CalendarWeekContainer extends StatelessWidget {
  final DateTime monday;

  const CalendarWeekContainer({Key key, this.monday}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, CalendarWeekViewModel>(
      builder: (context, vm, actions) {
        return CalendarWeek(vm: vm, key: key);
      },
      connect: (state) {
        return CalendarWeekViewModel(state, monday);
      },
    );
  }
}

typedef void DayCallback(DateTime day);

class CalendarWeekViewModel {
  final List<CalendarDay> days;
  final Map<String, String> subjectNicks;

  CalendarWeekViewModel(AppState state, DateTime monday)
      : days = state.calendarState.daysForWeek(monday),
        subjectNicks = state.settingsState.subjectNicks.toMap();
}
