// lib/screens/day_session_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import 'log_exercise_screen.dart';

class DaySessionScreen extends StatefulWidget {
  final DateTime date;
  final Map<String, dynamic> plan;
  final Map<String, dynamic>? initialSessionData;

  const DaySessionScreen({
    super.key,
    required this.date,
    required this.plan,
    this.initialSessionData,
  });

  @override
  State<DaySessionScreen> createState() => _DaySessionScreenState();
}

class _DaySessionScreenState extends State<DaySessionScreen> {
  final supa = Supabase.instance.client;
  late final List<dynamic> _plannedExercises;
  final Set<String> _completedExercises = {};

  // NUEVO: Lista para guardar los sets reales que vienen de la BD
  List<Map<String, dynamic>> _loggedSets = [];
  bool _isLoading = true;

  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    final prescription = widget.plan['prescription'];
    _plannedExercises = prescription?['exercises'] as List? ?? [];
    _setupInitialState();
  }

  Future<void> _setupInitialState() async {
    // Lógica del timer corregida para empezar desde 0 si es una nueva sesión
    final sessionStatus = widget.initialSessionData?['status'];
    if (sessionStatus == 'activa' || sessionStatus == 'pausada') {
      final startTimeStr = widget.initialSessionData?['started_at'] as String?;
      if (startTimeStr != null) {
        try {
          final startTime = DateTime.parse(startTimeStr).toLocal();
          _sessionDuration = DateTime.now().difference(startTime);
        } catch(e) {
          _sessionDuration = Duration.zero;
        }
      }
      _startSessionTimer();
    }
    await _loadSessionData();
  }

  // NUEVO: Carga tanto los sets completados como el estado de finalización
  Future<void> _loadSessionData() async {
    if(!mounted) return;
    setState(() => _isLoading = true);

    try {
      final uid = supa.auth.currentUser!.id;
      final day = yyyymmdd(widget.date);

      // Pedimos todos los sets guardados para este día
      final setsResponse = await supa
          .from('sets')
          .select()
          .eq('user_id', uid)
          .eq('session_date', day)
          .order('exercise_name', ascending: true)
          .order('set_index', ascending: true);

      _loggedSets = List<Map<String, dynamic>>.from(setsResponse);

      // Verificamos qué ejercicios están completos
      await _checkCompletedExercises();

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar datos de sesión: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkCompletedExercises() async {
    _completedExercises.clear();
    for (final exerciseData in _plannedExercises) {
      final title = _buildExerciseTitle(exerciseData);
      final prescriptions = exerciseData['prescriptions'] as List? ?? [];
      if (prescriptions.isEmpty) continue;

      int plannedWorkSetsCount = 0;
      for (var p in prescriptions) {
        plannedWorkSetsCount += (p['sets'] as int? ?? 1);
      }
      if (plannedWorkSetsCount == 0) continue;

      final loggedWorkSetsCount = _loggedSets.where((s) => s['exercise_name'] == title && s['is_warmup'] == false && s['is_completed'] == true).length;

      if (loggedWorkSetsCount >= plannedWorkSetsCount) {
        _completedExercises.add(title);
      }
    }
  }

  String _buildExerciseTitle(Map<String, dynamic> exerciseData) {
    String title = exerciseData['movement'] ?? 'Ejercicio sin nombre';
    final variants = exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      title += ' - ${variants.join(' ')}';
    }
    return title;
  }

  // MODIFICADO: Ahora construye el resumen desde los datos REALES guardados
  String _buildLoggedSummary(String exerciseTitle) {
    final setsForExercise = _loggedSets.where((s) => s['exercise_name'] == exerciseTitle && s['is_warmup'] == false && s['is_completed'] == true);
    if (setsForExercise.isEmpty) return "Sin series registradas.";

    return setsForExercise.map((s) {
      final weight = s['weight'];
      final reps = s['reps'];
      final rpe = s['rpe'] ?? '';
      return "$weight kg x $reps $rpe";
    }).join(' | ');
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _sessionDuration = Duration(seconds: _sessionDuration.inSeconds + 1);
        });
      }
    });
  }

  Future<void> _endSession() async {
    _sessionTimer?.cancel();
    try {
      await supa.from('sessions').upsert({
        'user_id': supa.auth.currentUser!.id,
        'session_date': yyyymmdd(widget.date),
        'status': 'finalizada',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'duration_min': _sessionDuration.inMinutes,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al finalizar sesión: $e')));
      }
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }

  String get _formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(_sessionDuration.inHours);
    final minutes = twoDigits(_sessionDuration.inMinutes.remainder(60));
    final seconds = twoDigits(_sessionDuration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final allExercisesCompleted = _plannedExercises.isNotEmpty && _completedExercises.length == _plannedExercises.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Duración: $_formattedDuration'),
        // El botón de actions se elimina de aquí
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
        itemCount: _plannedExercises.length,
        separatorBuilder: (_, __) => const Divider(height: 1.0),
        itemBuilder: (context, index) {
          // ... El itemBuilder se mantiene exactamente igual que antes
          final exerciseData = _plannedExercises[index] as Map<String, dynamic>;
          final title = _buildExerciseTitle(exerciseData);
          final isCompleted = _completedExercises.contains(title);
          final summary = isCompleted ? _buildLoggedSummary(title) : "Pendiente de registrar...";

          return ListTile(
            tileColor: isCompleted ? Theme.of(context).colorScheme.primary.withOpacity(0.05) : null,
            title: Text(title),
            subtitle: Text(summary, style: TextStyle(color: isCompleted ? Theme.of(context).colorScheme.primary : null)),
            trailing: isCompleted
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : const Icon(Icons.fitness_center),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LogExerciseScreen(
                    date: widget.date,
                    exerciseData: exerciseData,
                  ),
                ),
              );
              _loadSessionData();
            },
          );
        },
      ),

      // --- INICIO DE LA MODIFICACIÓN ---
      // Movemos el botón aquí abajo
      bottomNavigationBar: allExercisesCompleted
          ? Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          onPressed: _endSession,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Finalizar Sesión'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16.0),
            textStyle: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      )
          : null, // Si no están todos completos, no se muestra nada
      // --- FIN DE LA MODIFICACIÓN ---
    );
  }
}