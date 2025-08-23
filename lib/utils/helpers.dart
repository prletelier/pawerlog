// lib/utils/helpers.dart
import 'package:intl/intl.dart';
import 'models.dart';

/// Formatea un objeto [DateTime] a un string con formato 'yyyy-MM-dd'.
/// Útil para consistencia al interactuar con la base de datos.
String yyyymmdd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Parsea un string de RPE/RIR (ej. "@8", "RIR 2", "8.5") y devuelve solo el número.
/// Devuelve `null` si no se encuentra ningún número en el string.
double? parseRpe(String rpeString) {
  if (rpeString.isEmpty) return null;

  // Usa una expresión regular para buscar cualquier número, incluyendo decimales.
  final RegExp numberRegex = RegExp(r'(\d+(\.\d+)?)');
  final Match? match = numberRegex.firstMatch(rpeString);

  if (match != null) {
    // Si encuentra un número, lo convierte a double y lo devuelve.
    return double.tryParse(match.group(0)!);
  }

  // Si no encuentra ningún número, devuelve null.
  return null;
}

/// Combina una variante con sus dígitos de tempo si es necesario.
/// Por ejemplo, si [selected] es 'Tempo' y [tempoDigits] es '420',
/// devuelve 'Tempo 420'.
String effectiveVariant(String selected, String? tempoDigits) {
  if (selected.toLowerCase() == 'tempo' &&
      tempoDigits != null &&
      tempoDigits.trim().isNotEmpty) {
    return 'Tempo ${tempoDigits.trim()}';
  }
  return selected;
}

/// Fórmula interna para calcular el porcentaje de 1RM basado en reps y RPE.
/// No se debe llamar directamente.
double _percentage(int reps, double rpe) {
  if (rpe > 10) rpe = 10.0;
  if (reps < 1 || rpe < 4) return 0.0;
  if (reps == 1 && rpe == 10.0) return 100.0;
  final x = (10.0 - rpe) + (reps - 1);
  if (x >= 16) return 0.0;
  const intersection = 2.92;
  if (x <= intersection) {
    const a = 0.347619, b = -4.60714, c = 99.9667;
    return a * x * x + b * x + c;
  }
  const m = -2.64249, b = 97.0955;
  return m * x + b;
}

/// Calcula el 1RM Estimado (e1RM) a partir de un peso, repeticiones y RPE.
/// Devuelve `null` si el cálculo no es posible.
double? calcE1RM(double weightKg, int reps, double rpe) {
  final p = _percentage(reps, rpe);
  if (p <= 0) return null;
  return weightKg / p * 100.0;
}

/// Formatea un objeto [DateTime] a un string largo y legible en español.
/// Ejemplo de formato: "lunes, 11 de agosto de 2025".
String formatFullDate(DateTime d) {
  // Formato: Lunes, 11 de agosto de 2025
  return DateFormat('EEEE, d \'de\' MMMM \'de\' y', 'es').format(d);
}

/// Crea un objeto [PrescribedSet] a partir de los datos introducidos por el usuario.
PrescribedSet parsePrescriptionLine({
  required String setsStr,
  required String repsStr,
  required String effortStr,
  required bool isRampUp,
}) {
  return PrescribedSet(
    sets: setsStr,
    reps: repsStr,
    effort: effortStr,
    isRampUp: isRampUp,
  );
}

/// Incrementa un string de esfuerzo al siguiente nivel de intensidad.
/// Si el esfuerzo es RPE (ej. "@7"), devuelve "@8".
/// Si el esfuerzo es RIR (ej. "RIR 2"), devuelve "RIR 1".
String incrementEffort(String effort) {
  final number = parseRpe(effort); // Usa la función que ya teníamos
  if (number == null) return effort;

  if (effort.toLowerCase().contains('rir')) {
    // Si es RIR, el esfuerzo aumenta al DISMINUIR el número
    final newRir = (number - 1).clamp(0, 10);
    return 'RIR $newRir';
  } else {
    // Si es RPE, el esfuerzo aumenta al AUMENTAR el número
    final newRpe = (number + 1).clamp(0, 10);
    return '@$newRpe';
  }
}