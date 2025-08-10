// lib/utils/models.dart
import 'package:flutter/material.dart';

class PrescribedSet {
  int sets;
  String reps; // "5" o "10-12"
  String effort; // "@8", "RIR2", "-15%"
  PrescribedSet({this.sets = 1, this.reps = "5", this.effort = "@8"});
}

class PlannedExercise {
  String movement;
  String variant;
  String? tempoDigits;
  bool isAccessory;
  List<PrescribedSet> prescriptions;
  PlannedExercise({
    this.movement = 'SQ',
    this.variant = 'Competición',
    this.tempoDigits,
    this.isAccessory = false,
    List<PrescribedSet>? prescriptions,
  }) : prescriptions = prescriptions ?? [PrescribedSet()];
}

class LoggedSet {
  int seriesIndex;
  bool isWarmup;
  TextEditingController weightCtrl = TextEditingController();
  TextEditingController repsCtrl = TextEditingController();
  TextEditingController rpeCtrl = TextEditingController();
  bool isCompleted = false;
  LoggedSet({required this.seriesIndex, required this.isWarmup});
}