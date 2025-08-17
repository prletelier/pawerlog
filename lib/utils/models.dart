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
  List<String> selectedVariants; // Para guardar las variantes seleccionadas
  String tempoDigits; // Para los dígitos del tempo
  bool isAccessory;
  List<PrescribedSet> prescriptions;
  String notes;

  PlannedExercise({
    this.movement = '', // Cambiamos el valor por defecto
    List<String>? selectedVariants,
    this.tempoDigits = '',
    this.isAccessory = false,
    List<PrescribedSet>? prescriptions,
    this.notes = '', // <-- AÑADE ESTA LÍNEA
  })  : this.selectedVariants = selectedVariants ?? ['Competición'],
        this.prescriptions = prescriptions ?? [PrescribedSet()];
}

class LoggedSet {
  String? db_id; // <-- NUEVO: Para guardar el UUID de la fila en Supabase
  int seriesIndex;
  bool isWarmup;
  TextEditingController weightCtrl = TextEditingController();
  TextEditingController repsCtrl = TextEditingController();
  TextEditingController rpeCtrl = TextEditingController();
  bool isCompleted = false;
  LoggedSet(
      {this.db_id, required this.seriesIndex, required this.isWarmup});

  void dispose() {
    weightCtrl.dispose();
    repsCtrl.dispose();
    rpeCtrl.dispose();
  }
}