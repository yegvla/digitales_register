import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../container/sorted_grades_container.dart';
import '../data.dart';
import '../util.dart';

class SortedGradesWidget extends StatelessWidget {
  final SortedGradesViewModel vm;

  const SortedGradesWidget({Key key, @required this.vm}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SwitchListTile(
          title: Text("Noten nach Art sortieren"),
          onChanged: vm.sortByTypeCallback,
          value: vm.sortByType,
        ),
        SwitchListTile(
          title: Text("Gelöschte Noten anzeigen"),
          onChanged: vm.showCancelledCallback,
          value: vm.showCancelled,
        ),
        Divider(
          height: 0,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: vm.subjects
              .map((s) => SubjectWidget(
                    subject: vm.semester == null ? s : s.subjects[vm.semester],
                    sortByType: vm.sortByType,
                    viewSubjectDetail: () => vm.viewSubjectDetail(s),
                    showCancelled: vm.showCancelled,
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class SubjectWidget extends StatefulWidget {
  final bool sortByType, showCancelled;
  final Subject subject;
  final VoidCallback viewSubjectDetail;

  const SubjectWidget(
      {Key key,
      this.sortByType,
      this.subject,
      this.viewSubjectDetail,
      this.showCancelled})
      : super(key: key);

  @override
  _SubjectWidgetState createState() => _SubjectWidgetState();
}

class _SubjectWidgetState extends State<SubjectWidget> {
  bool closed = true;
  @override
  void didUpdateWidget(SubjectWidget oldWidget) {
    closed = true;
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: ObjectKey(widget.subject),
      title: Text(widget.subject.name),
      leading: widget.subject is AllSemesterSubject
          ? null
          : Text.rich(
              TextSpan(
                text: 'Ø ',
                children: <TextSpan>[
                  TextSpan(
                    text: widget.subject.averageFormatted,
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
      children: widget.subject.hasSpecificGrades
          ? widget.sortByType
              ? widget.subject.typeSortedEntries.data.entries
                  .map(
                    (entry) => GradeTypeWidget(
                      typeName: entry.key,
                      grades: entry.value
                          .where((g) => widget.showCancelled || !g.cancelled)
                          .toList(),
                    ),
                  )
                  .toList()
              : widget.subject.entries
                  .where((g) => widget.showCancelled || !g.cancelled)
                  .map((g) => g is Grade
                      ? GradeWidget(grade: g)
                      : ObservationWidget(
                          observation: g,
                        ))
                  .toList()
          : [
              LinearProgressIndicator(),
            ],
      onExpansionChanged: (expansion) {
        closed = !expansion;
        if (expansion) {
          widget.viewSubjectDetail();
        }
      },
      initiallyExpanded: !closed,
    );
  }
}

const lineThrough = const TextStyle(decoration: TextDecoration.lineThrough);

class GradeWidget extends StatelessWidget {
  final Grade grade;

  const GradeWidget({Key key, this.grade}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
                ListTile(
                  title: Text(
                    grade.name,
                    style: grade.cancelled ? lineThrough : null,
                  ),
                  subtitle: Text(
                    "${DateFormat("dd/MM/yy").format(grade.date)}:\n${grade.type} - ${grade.weightPercentage} %",
                    style: grade.cancelled ? lineThrough : null,
                  ),
                  trailing: Text(
                    grade.gradeFormatted,
                    style: grade.cancelled ? lineThrough : null,
                  ),
                  isThreeLine: true,
                ),
                Wrap(
                  children: <Widget>[],
                )
              ] +
              grade.competences
                  ?.map((c) => CompetenceWidget(
                        competence: c,
                        cancelled: grade.cancelled,
                      ))
                  ?.toList() ??
          [],
    );
  }
}

class ObservationWidget extends StatelessWidget {
  final Observation observation;

  const ObservationWidget({Key key, this.observation}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        observation.typeName,
        style: observation.cancelled ? lineThrough : null,
      ),
      subtitle: Text(
        "${DateFormat("dd/MM/yy").format(observation.date)}${isNullOrEmpty(observation.note) ? "" : ":\n${observation.note}"}",
        style: observation.cancelled ? lineThrough : null,
      ),
    );
  }
}

class CompetenceWidget extends StatelessWidget {
  final Competence competence;
  final bool cancelled;

  const CompetenceWidget({Key key, this.competence, this.cancelled})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 32, bottom: 16, right: 8),
      child: Wrap(
        children: <Widget>[
          Text(
            competence.typeName,
            style: cancelled ? lineThrough : null,
          ),
          Row(
            children: List.generate(
              5,
              (n) => Star(
                filled: n < competence.grade,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Star extends StatelessWidget {
  final bool filled;

  const Star({Key key, this.filled}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Icon(filled ? Icons.star : Icons.star_border);
  }
}

class GradeTypeWidget extends StatelessWidget {
  final String typeName;
  final List<GradeEntry> grades;

  const GradeTypeWidget({Key key, this.typeName, this.grades})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final displayGrades = grades
        .map((g) => g is Grade
            ? GradeWidget(grade: g)
            : ObservationWidget(
                observation: g,
              ))
        .toList();
    return displayGrades.isEmpty
        ? SizedBox()
        : ExpansionTile(
            title: Text(typeName),
            children: displayGrades,
            initiallyExpanded: true,
          );
  }
}
