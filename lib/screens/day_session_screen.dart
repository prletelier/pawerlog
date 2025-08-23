// lib/screens/day_session_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import 'log_exercise_screen.dart';

/// Muestra la lista de ejercicios planificados para un día específico.
/// Permite iniciar una sesión de entrenamiento y navegar al registro de cada ejercicio.
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

/// El estado para [DaySessionScreen].
/// Maneja el cronómetro de la sesión, carga los datos de los sets completados
/// y actualiza la UI para reflejar el progreso del entrenamiento.
class _DaySessionScreenState extends State<DaySessionScreen> {
  final supa = Supabase.instance.client;
  late final List<dynamic> _plannedExercises;
  final Set<String> _completedExercises = {};
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

  /// Configura el estado inicial de la pantalla, especialmente el cronómetro,
  /// basándose en si la sesión ya estaba activa.
  Future<void> _setupInitialState() async {
    final sessionStatus = widget.initialSessionData?['status'];
    if (sessionStatus == 'activa' || sessionStatus == 'pausada') {
      final startTimeStr = widget.initialSessionData?['started_at'] as String?;
      if (startTimeStr != null) {
        try {
          final startTime = DateTime.parse(startTimeStr).toLocal();

          // Manejo robusto de 'duration_min' que puede ser int o String
          final dynamic savedDuration = widget.initialSessionData?['duration_min'];
          int? savedDurationMins;
          if (savedDuration is int) {
            savedDurationMins = savedDuration;
          } else if (savedDuration is String) {
            savedDurationMins = int.tryParse(savedDuration);
          }

          if (savedDurationMins != null && savedDurationMins > 0) {
            _sessionDuration = Duration(minutes: savedDurationMins);
          } else {
            _sessionDuration = DateTime.now().difference(startTime);
          }
        } catch(e) {
          _sessionDuration = Duration.zero;
        }
      }
      _startSessionTimer();
    }
    await _loadSessionData();
  }

  /// Carga desde Supabase todos los sets registrados para el día actual y
  /// actualiza el estado de los ejercicios completados.
  Future<void> _loadSessionData() async {
    if(!mounted) return;
    setState(() => _isLoading = true);

    try {
      final uid = supa.auth.currentUser!.id;
      final day = yyyymmdd(widget.date);

      final setsResponse = await supa
          .from('sets')
          .select()
          .eq('user_id', uid)
          .eq('session_date', day)
          .order('exercise_name', ascending: true)
          .order('set_index', ascending: true);

      _loggedSets = List<Map<String, dynamic>>.from(setsResponse);
      await _checkCompletedExercises();

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar datos de sesión: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Compara los sets planeados con los registrados en la BD para determinar
  /// qué ejercicios están completamente finalizados.
  Future<void> _checkCompletedExercises() async {
    _completedExercises.clear();
    for (final exerciseData in _plannedExercises) {
      final title = _buildExerciseTitle(exerciseData);
      final prescriptions = exerciseData['prescriptions'] as List? ?? [];
      if (prescriptions.isEmpty) continue;

      int plannedWorkSetsCount = 0;
      for (var p in prescriptions) {
        // CORREGIDO: Asegura que 'sets' se trate como String antes de parsear
        plannedWorkSetsCount += int.tryParse(p['sets']?.toString() ?? '1') ?? 1;
      }
      if (plannedWorkSetsCount == 0) continue;

      final loggedWorkSetsCount = _loggedSets.where((s) => s['exercise_name'] == title && s['is_warmup'] == false && s['is_completed'] == true).length;

      if (loggedWorkSetsCount >= plannedWorkSetsCount) {
        _completedExercises.add(title);
      }
    }
  }

  /// Construye el título completo de un ejercicio, combinando el movimiento y sus variantes.
  String _buildExerciseTitle(Map<String, dynamic> exerciseData) {
    String title = exerciseData['movement'] ?? 'Ejercicio sin nombre';
    final variants = exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      title += ' - ${variants.join(' ')}';
    }
    return title;
  }

  /// Crea un resumen del trabajo REALIZADO para un ejercicio completado.
  /// Ej: "100.0 kg x 5 @8 | 102.5 kg x 5 @9"
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

  /// Inicia o reanuda el cronómetro principal de la sesión.
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

  /// Finaliza la sesión, detiene el cronómetro y guarda el estado final en Supabase.
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

  /// Formatea la duración de la sesión en un string legible (HH:MM:SS).
  String get _formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(_sessionDuration.inHours);
    final minutes = twoDigits(_sessionDuration.inMinutes.remainder(60));
    final seconds = twoDigits(_sessionDuration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  /// El build es principalmente UI, mostrando la lista de ejercicios
  /// y el estado del cronómetro. Permite navegar a la pantalla de registro
  /// de cada ejercicio y finalizar la sesión cuando todos los ejercicios
  /// están completos.
  @override
  Widget build(BuildContext context) {
    final allExercisesCompleted = _plannedExercises.isNotEmpty && _completedExercises.length == _plannedExercises.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Duración: $_formattedDuration'),
        actions: [
          if (allExercisesCompleted)
            TextButton(
              onPressed: _endSession,
              child: const Text('FINALIZAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
        itemCount: _plannedExercises.length,
        separatorBuilder: (_, __) => const Divider(height: 1.0),
        itemBuilder: (context, index) {
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
          : null,
    );
  }
}