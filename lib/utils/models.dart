// lib/utils/models.dart
import 'package:flutter/material.dart';

/// Representa una línea de prescripción de entrenamiento.
/// Ej: "3 series x 5 reps @8 RPE" o "1 serie x 10-12 reps RIR 2"
class PrescribedSet {
  String sets; // Puede ser un número o un rango
  String reps; // Puede ser un número o un rango
  String effort; // Puede ser RPE, RIR, o un porcentaje
  bool isRampUp; // Indica si es una serie de aproximación (rampa)

  PrescribedSet({
    this.sets = "1",
    this.reps = "5",
    this.effort = "@8",
    this.isRampUp = false, // <-- Por defecto, no es una rampa
  });
}

/// Representa un único ejercicio planificado dentro de un día de entrenamiento.
/// Contiene el movimiento, sus variantes y la lista de prescripciones.
class PlannedExercise {
  String movement; // Nombre del movimiento
  List<String> selectedVariants; // Para guardar las variantes seleccionadas
  String tempoDigits; // Para los dígitos del tempo
  bool isAccessory; // Si es accesorio o no
  List<PrescribedSet> prescriptions; // Lista de prescripciones
  String notes; // Notas adicionales

  PlannedExercise({
    this.movement = '', // Cambiamos el valor por defecto
    List<String>? selectedVariants,
    this.tempoDigits = '',
    this.isAccessory = false,
    List<PrescribedSet>? prescriptions,
    this.notes = '',
  }) : this.selectedVariants = selectedVariants ?? ['Competición'],
        this.prescriptions = prescriptions ?? []; // <-- Crea una lista vacía
}

/// Representa una serie individual que ha sido o será registrada por el usuario.
/// Maneja el estado de la UI (los controladores de texto) y su conexión con la BD.
class LoggedSet {
  String? db_id; // El ID único (UUID) de la fila correspondiente en la tabla 'sets' de Supabase.
  int seriesIndex; // Índice de la serie dentro del ejercicio (0-based)
  bool isWarmup; // Indica si es una serie de calentamiento
  TextEditingController weightCtrl = TextEditingController(); // Controlador para el campo de peso
  TextEditingController repsCtrl = TextEditingController(); // Controlador para el campo de repeticiones
  TextEditingController rpeCtrl = TextEditingController(); // Controlador para el campo de RPE/RIR
  bool isCompleted = false;
  LoggedSet(
      {this.db_id, required this.seriesIndex, required this.isWarmup});

  void dispose() {
    weightCtrl.dispose();
    repsCtrl.dispose();
    rpeCtrl.dispose();
  }
}