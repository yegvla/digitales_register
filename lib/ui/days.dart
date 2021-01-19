import 'package:badges/badges.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';

import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tuple/tuple.dart';

import '../container/days_container.dart';
import '../container/homework_filter_container.dart';
import '../data.dart';
import '../util.dart';
import 'dialog.dart';
import 'no_internet.dart';

typedef AddReminderCallback = void Function(Day day, String reminder);
typedef RemoveReminderCallback = void Function(Homework hw, Day day);
typedef ToggleDoneCallback = void Function(Homework hw, bool done);
typedef MarkAsNotNewOrChangedCallback = void Function(Homework hw);
typedef MarkDeletedHomeworkAsSeenCallback = void Function(Day day);

class DaysWidget extends StatefulWidget {
  final DaysViewModel vm;

  final MarkAsNotNewOrChangedCallback markAsSeenCallback;
  final MarkDeletedHomeworkAsSeenCallback markDeletedHomeworkAsSeenCallback;
  final VoidCallback markAllAsSeenCallback;
  final AddReminderCallback addReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final VoidCallback onSwitchFuture;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final VoidCallback refresh;
  final VoidCallback refreshNoInternet;
  final AttachmentCallback onDownloadAttachment, onOpenAttachment;

  const DaysWidget({
    Key key,
    this.vm,
    this.markAsSeenCallback,
    this.markDeletedHomeworkAsSeenCallback,
    this.addReminderCallback,
    this.removeReminderCallback,
    this.markAllAsSeenCallback,
    this.onSwitchFuture,
    this.toggleDoneCallback,
    this.setDoNotAskWhenDeleteCallback,
    this.refresh,
    this.refreshNoInternet,
    this.onDownloadAttachment,
    this.onOpenAttachment,
  }) : super(key: key);
  @override
  _DaysWidgetState createState() => _DaysWidgetState();
}

class _DaysWidgetState extends State<DaysWidget> {
  final controller = AutoScrollController();

  bool _showScrollUp = false;
  bool _afterFirstFrame = false;

  List<int> _targets = [];
  List<int> _focused = [];
  Map<int, int> _dayStartIndices = {};
  Map<int, Homework> _homeworkIndexes = {};
  Map<int, Day> _dayIndexes = {};

  void _updateShowScrollUp() {
    final newScrollUp = controller.offset > 250;
    if (_showScrollUp != newScrollUp) {
      setState(() {
        _showScrollUp = newScrollUp;
      });
    }
  }

  double _distanceToItem(int item) {
    final ctx = controller.tagMap[item]?.context;
    if (ctx != null) {
      final renderBox = ctx.findRenderObject() as RenderBox;
      final RenderAbstractViewport viewport =
          RenderAbstractViewport.of(renderBox);
      var offsetToReveal = viewport.getOffsetToReveal(renderBox, 0.5).offset;
      if (offsetToReveal < 0) offsetToReveal = 0;
      final currentOffset = controller.offset;
      return (offsetToReveal - currentOffset).abs();
    }
    return null;
  }

  void _updateReachedHomeworks() {
    for (final target in _targets.toList()) {
      final distance = _distanceToItem(target);
      if (distance != null && distance < 50) {
        _focused.add(target);
        _targets.remove(target);
        controller.highlight(
          target,
          highlightDuration: Duration(milliseconds: 500),
          cancelExistHighlights: false,
        );
        if (_targets.isEmpty) setState(() {});
      }
    }
    for (final focusedItem in _focused.toList()) {
      final distance = _distanceToItem(focusedItem);
      if (distance == null || distance > 50) {
        _focused.remove(focusedItem);
        if (_dayIndexes.containsKey(focusedItem)) {
          widget.markDeletedHomeworkAsSeenCallback(_dayIndexes[focusedItem]);
        } else if (_homeworkIndexes.containsKey(focusedItem)) {
          widget.markAsSeenCallback(_homeworkIndexes[focusedItem]);
        } else {
          assert(
            false,
            "A target index should either be a new/changed homework or a day (deleted homework)",
          );
        }
      }
    }
  }

  void update() {
    _updateShowScrollUp();
    _updateReachedHomeworks();
  }

  void updateValues() {
    _targets.clear();
    _focused.clear();
    var index = 0;
    var dayIndex = 0;
    for (var day in widget.vm.days) {
      _dayStartIndices[dayIndex] = index;
      if (day.deletedHomework.any((h) => h.isChanged)) {
        _targets.add(index);
        _dayIndexes[index] = day;
      }
      index++;
      for (var hw in day.homework) {
        if (hw.isNew || hw.isChanged) {
          _targets.add(index);
        }
        _homeworkIndexes[index] = hw;
        index++;
      }
      dayIndex++;
    }
  }

  @override
  void initState() {
    updateValues();
    controller.addListener(() {
      update();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      update();
      _afterFirstFrame = true;
      setState(() {});
    });
    super.initState();
  }

  @override
  void didUpdateWidget(DaysWidget oldWidget) {
    updateValues();
    update();

    super.didUpdateWidget(oldWidget);
  }

  Widget getItem(int n, bool noEntries, bool noInternet) {
    if (n == 0) {
      return Stack(
        children: [
          HomeworkFilterContainer(),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                Expanded(
                  child: AbsorbPointer(child: Container()),
                ),
                SizedBox(
                  width: 60,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Center(
              child: ElevatedButton(
                child: Text(
                  widget.vm.future ? "Vergangenheit" : "Zukunft",
                ),
                onPressed: widget.onSwitchFuture,
              ),
            ),
          ),
        ],
      );
    }
    if (n == widget.vm.days.length + 1) {
      if (noEntries) {
        if (noInternet) {
          return Column(
            children: <Widget>[
              SizedBox(
                height: 120,
              ),
              NoInternet(),
            ],
          );
        } else {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                "Keine Einträge vorhanden",
                style: Theme.of(context).textTheme.headline4,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
      } else {
        return SizedBox(
          height: 160,
        );
      }
    }
    return DayWidget(
      day: widget.vm.days[n - 1],
      vm: widget.vm,
      controller: controller,
      index: _dayStartIndices[n - 1],
      addReminderCallback: widget.addReminderCallback,
      removeReminderCallback: widget.removeReminderCallback,
      toggleDoneCallback: widget.toggleDoneCallback,
      setDoNotAskWhenDeleteCallback: widget.setDoNotAskWhenDeleteCallback,
      onDownloadAttachment: widget.onDownloadAttachment,
      onOpenAttachment: widget.onOpenAttachment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final noInternet = widget.vm.noInternet;
    final noEntries = widget.vm.days.isEmpty;
    Widget body = ListView.builder(
      physics: AlwaysScrollableScrollPhysics(),
      controller: controller,
      itemCount: widget.vm.days.length + 2,
      itemBuilder: (context, n) {
        return getItem(n, noEntries, noInternet);
      },
    );
    if (!noInternet) {
      body = RefreshIndicator(
          child: body, onRefresh: () async => widget.refresh());
    }
    if (widget.vm.loading) {
      body = Stack(
        children: [
          body,
          LinearProgressIndicator(),
        ],
      );
    }
    return ResponsiveScaffold<Pages>(
      key: scaffoldKey,
      homeBody: body,
      homeFloatingActionButton: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (_showScrollUp)
            FloatingActionButton(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              heroTag: null,
              onPressed: () {
                controller.animateTo(
                  0,
                  duration: Duration(milliseconds: 500),
                  curve: Curves.decelerate,
                );
              },
              child: Icon(
                Icons.arrow_drop_up,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
              mini: true,
            ),
          if (_targets.isNotEmpty || _focused.isNotEmpty)
            FloatingActionButton(
              backgroundColor: Colors.red,
              heroTag: null,
              onPressed: () {
                widget.markAllAsSeenCallback();
              },
              child: Icon(Icons.close),
              mini: true,
            ),
          if (_targets.isNotEmpty && _afterFirstFrame)
            FloatingActionButton.extended(
              backgroundColor: Colors.red,
              icon: Icon(Icons.arrow_drop_down),
              label: Text("Neue Einträge"),
              onPressed: () async {
                await controller.scrollToIndex(
                  _targets.first,
                  preferPosition: AutoScrollPosition.middle,
                );
              },
            ),
        ],
      ),
      homeAppBar: ResponsiveAppBar(
        title: Text("Register"),
        actions: <Widget>[
          if (widget.vm.noInternet)
            TextButton(
              style: TextButton.styleFrom(
                primary: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Row(
                children: <Widget>[
                  Text("Keine Verbindung"),
                  SizedBox(width: 8),
                  Icon(Icons.refresh),
                ],
              ),
              onPressed: widget.refreshNoInternet,
            ),
          if (widget.vm.showNotifications) NotificationIconContainer(),
        ],
      ),
      drawerBuilder: (_widgetSelected, goHome, currentSelected, tabletMode) {
        // _widgetSelected is not passed down because routing is done by
        // accessing the ResponsiveScaffoldState via the GlobalKey and calling
        // selectContentWidget on it.
        return SidebarContainer(
          currentSelected: currentSelected,
          goHome: goHome,
          tabletMode: tabletMode,
        );
      },
      homeId: Pages.Homework,
      navKey: nestedNavKey,
    );
  }
}

class DayWidget extends StatelessWidget {
  final DaysViewModel vm;

  final AddReminderCallback addReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final AttachmentCallback onDownloadAttachment, onOpenAttachment;

  final Day day;

  final AutoScrollController controller;
  final int index;

  const DayWidget({
    Key key,
    this.day,
    this.vm,
    this.controller,
    this.index,
    this.addReminderCallback,
    this.removeReminderCallback,
    this.toggleDoneCallback,
    this.setDoNotAskWhenDeleteCallback,
    this.onDownloadAttachment,
    this.onOpenAttachment,
  }) : super(key: key);

  Future<String> showEnterReminderDialog(BuildContext context) async {
    return await showDialog(
      context: context,
      builder: (context) {
        String message = "";
        return StatefulBuilder(
          builder: (context, setState) => InfoDialog(
            title: Text("Erinnerung"),
            content: TextField(
              maxLines: null,
              onChanged: (msg) {
                setState(() => message = msg);
              },
              decoration: InputDecoration(hintText: 'zB. Hausaufgabe'),
            ),
            actions: <Widget>[
              TextButton(
                child: Text("Abbrechen"),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              ElevatedButton(
                child: Text(
                  "Speichern",
                ),
                onPressed: message.isNullOrEmpty
                    ? null
                    : () {
                        Navigator.pop(context, message);
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var i = index;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    day.displayName,
                    style: Theme.of(context).textTheme.headline6,
                  ),
                ),
              ),
              if (day.deletedHomework.isNotEmpty)
                AutoScrollTag(
                  child: IconButton(
                    icon: Badge(
                      child: Icon(Icons.info_outline),
                      badgeContent: Icon(
                        Icons.delete,
                        size: 15,
                        color: day.deletedHomework.any((h) => h.isChanged)
                            ? Colors.white
                            : null,
                      ),
                      badgeColor: day.deletedHomework.any((h) => h.isChanged)
                          ? Colors.red
                          : Theme.of(context).scaffoldBackgroundColor,
                      toAnimate: day.deletedHomework.any((h) => h.isChanged),
                      padding: EdgeInsets.zero,
                      position: BadgePosition.topStart(),
                      elevation: 0,
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_context) {
                          return InfoDialog(
                            title: Text("Gelöschte Einträge"),
                            content: ListView(
                              shrinkWrap: true,
                              children: day.deletedHomework
                                  .map(
                                    (i) => ItemWidget(
                                      item: i,
                                      isDeletedView: true,
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  controller: controller,
                  index: index,
                  key: ValueKey(index),
                  highlightColor: Colors.grey.withOpacity(0.5),
                ),
              Spacer(),
              if (vm.showAddReminder)
                IconButton(
                  icon: Icon(Icons.add),
                  onPressed: vm.noInternet
                      ? null
                      : () async {
                          final message =
                              await showEnterReminderDialog(context);
                          if (message != null) {
                            addReminderCallback(day, message);
                          }
                        },
                ),
            ],
          ),
        ),
        for (final hw in day.homework)
          ItemWidget(
            item: hw,
            toggleDone: () => toggleDoneCallback(hw, !hw.checked),
            removeThis: () => removeReminderCallback(hw, day),
            setDoNotAskWhenDelete: setDoNotAskWhenDeleteCallback,
            askWhenDelete: vm.askWhenDelete,
            noInternet: vm.noInternet,
            controller: controller,
            index: ++i,
            onDownloadAttachment: onDownloadAttachment,
            onOpenAttachment: onOpenAttachment,
          ),
        Divider(),
      ],
    );
  }
}

class ItemWidget extends StatelessWidget {
  final Homework item;
  final VoidCallback removeThis;
  final VoidCallback toggleDone;
  final VoidCallback setDoNotAskWhenDelete;
  final bool askWhenDelete, isHistory, isDeletedView, noInternet, isCurrent;
  final AttachmentCallback onDownloadAttachment, onOpenAttachment;

  final AutoScrollController controller;
  final int index;

  const ItemWidget({
    Key key,
    this.item,
    this.removeThis,
    this.toggleDone,
    this.askWhenDelete,
    this.setDoNotAskWhenDelete,
    this.isHistory = false,
    this.controller,
    this.index,
    this.isDeletedView = false,
    this.noInternet,
    this.isCurrent = true,
    this.onDownloadAttachment,
    this.onOpenAttachment,
  }) : super(key: key);

  Future<Tuple2<bool, bool>> _showConfirmDelete(BuildContext context) async {
    var ask = true;
    final delete = await showDialog(
      context: context,
      builder: (context) {
        return InfoDialog(
          content: StatefulBuilder(
            builder: (context, setState) => SwitchListTile.adaptive(
              title: Text("Nie fragen"),
              onChanged: (bool value) {
                setState(() => ask = !value);
              },
              value: !ask,
            ),
          ),
          title: Text("Erinnerung löschen?"),
          actions: <Widget>[
            TextButton(
              child: Text("Abbrechen"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: Text(
                "Löschen",
              ),
              onPressed: () => Navigator.pop(context, true),
            )
          ],
        );
      },
    );
    return Tuple2(delete, ask);
  }

  void _showHistory(BuildContext context) {
    // if we are in the deleted view, show the history for the previous item
    final historyItem = isDeletedView ? item.previousVersion : item;
    showDialog(
      context: context,
      builder: (_context) {
        return InfoDialog(
          title: Text(historyItem.title),
          content: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Text(formatChanged(historyItem)),
              if (historyItem.previousVersion != null)
                ExpansionTile(
                  title: Text("Versionen"),
                  children: <Widget>[
                    ItemWidget(
                      item: historyItem,
                      isHistory: true,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: item.warning
            ? BorderSide(color: Colors.red, width: 1)
            : item.type == HomeworkType.grade || item.checked
                ? BorderSide(color: Colors.green, width: 0)
                : BorderSide(color: Colors.grey, width: 0),
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.transparent,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 8,
                    top: 8,
                    bottom: 6,
                  ),
                  child: Column(
                    children: <Widget>[
                      if (item.label != null)
                        Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Center(
                              child: Text(
                                item.label,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if ((!isHistory &&
                                    (item.isNew || item.isChanged)) ||
                                (isHistory && isCurrent))
                              Positioned(
                                right: 0,
                                child: Badge(
                                  shape: BadgeShape.square,
                                  borderRadius: BorderRadius.circular(20),
                                  badgeContent: Text(
                                    isHistory && isCurrent
                                        ? "aktuell"
                                        : item.isNew
                                            ? "neu"
                                            : item.deleted
                                                ? "gelöscht"
                                                : "geändert",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                          ],
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.title),
                        subtitle: item.subtitle.isNullOrEmpty
                            ? null
                            : Text(item.subtitle),
                        leading: !isHistory && !isDeletedView && item.deleteable
                            ? IconButton(
                                icon: Icon(Icons.close),
                                onPressed: noInternet
                                    ? null
                                    : () async {
                                        if (askWhenDelete) {
                                          final confirmationResult =
                                              await _showConfirmDelete(context);
                                          final delete =
                                              confirmationResult.item1;
                                          final ask = confirmationResult.item2;
                                          if (delete == true) {
                                            if (!ask) setDoNotAskWhenDelete();
                                            removeThis();
                                          }
                                        } else {
                                          removeThis();
                                        }
                                      },
                                padding: EdgeInsets.all(0),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (!isHistory && item.label != null)
                    IconButton(
                      icon: (isDeletedView
                                  ? item.previousVersion.previousVersion
                                  : item.previousVersion) !=
                              null
                          ? Badge(
                              child: Icon(
                                Icons.info_outline,
                              ),
                              badgeContent: Icon(Icons.edit, size: 15),
                              padding: EdgeInsets.zero,
                              badgeColor: isDeletedView
                                  ? Theme.of(context).dialogBackgroundColor
                                  : Theme.of(context).scaffoldBackgroundColor,
                              toAnimate: false,
                              elevation: 0,
                            )
                          : Icon(
                              Icons.info_outline,
                            ),
                      onPressed: () {
                        _showHistory(context);
                      },
                    ),
                  if (item.warning)
                    Padding(
                      // make this exactly as big as the (i) icon above, so
                      // [CrossAxisAlignment.end] will not move this to the end
                      padding: const EdgeInsets.symmetric(horizontal: 19),
                      child: Text(
                        "!",
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 30,
                        ),
                      ),
                    )
                  else if (item.type == HomeworkType.grade)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        item.gradeFormatted,
                        style: TextStyle(color: Colors.green, fontSize: 30),
                      ),
                    )
                  else if (!isHistory && !isDeletedView && item.checkable)
                    Checkbox(
                      activeColor: Colors.green,
                      value: item.checked,
                      onChanged: noInternet
                          ? null
                          : (done) {
                              toggleDone();
                            },
                    ),
                ],
              ),
            ],
          ),
          if (isHistory || isDeletedView) ...[
            Divider(height: 0),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                formatChanged(item),
                style: Theme.of(context).textTheme.caption,
              ),
            ),
          ],
          if (item.gradeGroupSubmissions?.isNotEmpty == true) ...[
            Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("Anhang",
                    style: Theme.of(context).textTheme.subtitle1),
              ),
            ),
            for (final attachment in item.gradeGroupSubmissions)
              AttachmentWidget(
                ggs: attachment,
                noInternet: noInternet,
                downloadCallback: onDownloadAttachment,
                openCallback: onOpenAttachment,
              )
          ]
        ],
      ),
    );
    if (!isHistory && !isDeletedView) {
      child = AutoScrollTag(
        index: index,
        key: ValueKey(index),
        controller: controller,
        child: child,
        highlightColor: Colors.grey.withOpacity(0.5),
      );
    }
    return Column(
      children: <Widget>[
        child,
        if (isHistory && item.previousVersion != null)
          ItemWidget(
            isHistory: true,
            isCurrent: false,
            item: item.previousVersion,
          ),
      ],
    );
  }
}

String formatChanged(Homework hw) {
  String date;
  if (hw.lastNotSeen == null) {
    date =
        "Vor ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)} ";
  } else if (toDate(hw.firstSeen) == toDate(hw.lastNotSeen)) {
    date = "Am ${DateFormat("EEEE, dd.MM,", "de").format(hw.firstSeen)}"
        " zwischen ${DateFormat("HH:mm", "de").format(hw.lastNotSeen)} und ${DateFormat("HH:mm", "de").format(hw.firstSeen)}";
  } else {
    date =
        "Zwischen ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.lastNotSeen)} "
        "und ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)}";
  }
  if (hw.deleted) {
    return "$date gelöscht.";
  } else if (hw.previousVersion == null) {
    return "$date eingetragen.";
  } else if (hw.previousVersion.deleted) {
    return "$date wiederhergestellt.";
  } else {
    return "$date geändert.";
  }
}

DateTime toDate(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}

class AttachmentWidget extends StatelessWidget {
  final GradeGroupSubmission ggs;
  final AttachmentCallback downloadCallback;
  final AttachmentCallback openCallback;
  final bool noInternet;

  const AttachmentWidget(
      {Key key,
      this.ggs,
      this.downloadCallback,
      this.noInternet,
      this.openCallback})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Divider(
            indent: 16,
            height: 0,
          ),
          ListTile(title: Text(ggs.originalName)),
          if (ggs.downloading) LinearProgressIndicator(),
          if (!ggs.fileAvailable)
            TextButton(
              child: Text("Herunterladen"),
              onPressed: noInternet
                  ? null
                  : () {
                      downloadCallback(ggs);
                    },
            )
          else
            IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                      child: Text("Erneut herunterladen"),
                      onPressed: noInternet
                          ? null
                          : () {
                              downloadCallback(ggs);
                            },
                    ),
                  ),
                  VerticalDivider(
                    indent: 8,
                    endIndent: 8,
                  ),
                  Expanded(
                    child: TextButton(
                      child: Text("Öffnen"),
                      onPressed: () {
                        openCallback(ggs);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
