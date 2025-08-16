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
  final supa = Supabase.instance.client;
  late final List<dynamic> _exercises;
  final Set<String> _completedExercises = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final prescription = widget.plan['prescription'];
    if (prescription != null && prescription['exercises'] is List) {
      _exercises = prescription['exercises'];
    } else {
      _exercises = [];
    }
    _loadCompletedExercises();
  }

  // CORREGIDO: Ahora reconstruye el título del ejercicio a partir de la nueva estructura
  String _buildExerciseTitle(Map<String, dynamic> exerciseData) {
    String title = exerciseData['movement'] ?? 'Ejercicio sin nombre';
    // Leemos la nueva lista 'variants' en lugar del antiguo 'variant'
    final variants = exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      title += ' - ${variants.join(' ')}'; // Une las variantes con un espacio
    }
    return title;
  }

  Future<void> _loadCompletedExercises() async {
    for (final exerciseData in _exercises) {
      // Usamos la nueva función para obtener el título correcto
      final title = _buildExerciseTitle(exerciseData);
      final prescriptions = exerciseData['prescriptions'] as List? ?? [];
      if (prescriptions.isEmpty) continue;

      int plannedWorkSetsCount = 0;
      for (var p in prescriptions) {
        plannedWorkSetsCount += (p['sets'] as int? ?? 1);
      }

      // Si no hay series efectivas planeadas, no puede estar "completo" en este sentido
      if (plannedWorkSetsCount == 0) continue;

      final loggedWorkSetsCount = await supa
          .from('sets')
          .count(CountOption.exact)
          .eq('user_id', supa.auth.currentUser!.id)
          .eq('session_date', yyyymmdd(widget.date))
          .eq('exercise_name', title) // Busca con el título correcto
          .eq('is_warmup', false)
          .eq('is_completed', true); // Contamos solo los sets marcados como completos

      if (loggedWorkSetsCount >= plannedWorkSetsCount) {
        _completedExercises.add(title);
      }
    }

    if(mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _buildPrescriptionSummary(Map<String, dynamic> exerciseData) {
    if (exerciseData['prescriptions'] is! List) return "Prescripción no definida.";
    final prescriptions = (exerciseData['prescriptions'] as List);
    if (prescriptions.isEmpty) return "Sin series definidas.";
    return prescriptions.map((p) {
      final setData = p as Map<String, dynamic>;
      final sets = setData['sets'] ?? 1;
      final reps = setData['reps'] ?? 'N/A';
      final effort = setData['effort'] ?? '';
      return "$sets x $reps $effort";
    }).join('  |  ');
  }

  @override
  Widget build(BuildContext context) {
    final dayStr = yyyymmdd(widget.date);

    return Scaffold(
      appBar: AppBar(
        title: Text('Sesión del $dayStr'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _exercises.isEmpty
          ? const Center(
        child: Text('No hay ejercicios definidos para este día.'),
      )
          : ListView.separated(
        itemCount: _exercises.length,
        separatorBuilder: (_, __) => const Divider(height: 1.0),
        itemBuilder: (context, index) {
          final exerciseData = _exercises[index] as Map<String, dynamic>;
          // Usamos la nueva función para el título
          final title = _buildExerciseTitle(exerciseData);
          final summary = _buildPrescriptionSummary(exerciseData);
          final bool isCompleted = _completedExercises.contains(title);

          return ListTile(
            tileColor: isCompleted ? Theme.of(context).colorScheme.primary.withOpacity(0.05) : null,
            title: Text(title),
            subtitle: Text(summary),
            trailing: isCompleted
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : const Icon(Icons.fitness_center),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LogExerciseScreen(
                    date: widget.date,
                    exerciseData: exerciseData,
                  ),
                ),
              ).then((result) {
                if (result == true) {
                  setState(() { _isLoading = true; });
                  _loadCompletedExercises();
                }
              });
            },
          );
        },
      ),
      floatingActionButton: !_isLoading && _exercises.isNotEmpty && _completedExercises.length == _exercises.length
          ? FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ ¡Sesión Finalizada!')),
          );
          Navigator.of(context).pop();
        },
        label: const Text('Finalizar Sesión'),
        icon: const Icon(Icons.check),
      )
          : null,
    );
  }
}