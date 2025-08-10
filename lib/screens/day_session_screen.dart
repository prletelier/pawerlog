// lib/screens/day_session_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import 'log_exercise_screen.dart';

class DaySessionScreen extends StatefulWidget {
  final DateTime date;
  final Map<String, dynamic> plan;

  const DaySessionScreen({super.key, required this.date, required this.plan});

  @override
  State<DaySessionScreen> createState() => _DaySessionScreenState();
}

class _DaySessionScreenState extends State<DaySessionScreen> {
  // El JSON de la prescripción contiene la lista de ejercicios
  late final List<dynamic> _exercises;

  @override
  void initState() {
    super.initState();
    // Extraemos la lista de ejercicios del campo 'prescription'
    final prescription = widget.plan['prescription'];
    if (prescription != null && prescription['exercises'] is List) {
      _exercises = prescription['exercises'];
    } else {
      _exercises = [];
    }
  }

  // Función para crear un resumen legible de la prescripción
  String _buildPrescriptionSummary(Map<String, dynamic> exerciseData) {
    if (exerciseData['prescriptions'] is! List) return "Prescripción no definida.";

    final prescriptions = (exerciseData['prescriptions'] as List);
    if (prescriptions.isEmpty) return "Sin series definidas.";

    // Mapea cada bloque de series a un string (ej: "2x5 @8", "4x10-12 RIR2")
    return prescriptions.map((p) {
      final setData = p as Map<String, dynamic>;
      final sets = setData['sets'] ?? 1;
      final reps = setData['reps'] ?? 'N/A';
      final effort = setData['effort'] ?? '';
      return "$sets x $reps $effort";
    }).join('  |  '); // Une múltiples prescripciones con un separador
  }

  @override
  Widget build(BuildContext context) {
    final dayStr = yyyymmdd(widget.date);

    return Scaffold(
      appBar: AppBar(
        title: Text('Sesión del $dayStr'),
      ),
      body: _exercises.isEmpty
          ? const Center(
        child: Text('No hay ejercicios definidos para este día.'),
      )
          : ListView.separated(
        itemCount: _exercises.length,
        separatorBuilder: (_, __) => const Divider(height: 1.0),
        itemBuilder: (context, index) {
          final exerciseData = _exercises[index] as Map<String, dynamic>;
          final title =
              '${exerciseData['movement']} - ${exerciseData['variant']}';
          final summary = _buildPrescriptionSummary(exerciseData);

          return ListTile(
            title: Text(title),
            subtitle: Text(summary),
            trailing: const Icon(Icons.fitness_center),
            onTap: () {
              // Navega a la pantalla de registro de series para este ejercicio
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LogExerciseScreen(
                    date: widget.date,
                    exerciseData: exerciseData,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}