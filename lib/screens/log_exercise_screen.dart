// lib/screens/log_exercise_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import '../utils/models.dart';
import '../widgets/series_row_widget.dart';

class LogExerciseScreen extends StatefulWidget {
  final DateTime date;
  final Map<String, dynamic> exerciseData;

  const LogExerciseScreen({
    super.key,
    required this.date,
    required this.exerciseData,
  });

  @override
  State<LogExerciseScreen> createState() => _LogExerciseScreenState();
}

class _LogExerciseScreenState extends State<LogExerciseScreen> {
  final supa = Supabase.instance.client;

  late final String _title;
  late final List<LoggedSet> _warmupSets;
  late final List<LoggedSet> _workSets;

  Timer? _restTimer;
  int _restSecondsRemaining = 0;
  final _restDurations = {
    'warmup': const Duration(minutes: 1),
    'basic': const Duration(minutes: 3, seconds: 30),
    'accessory': const Duration(minutes: 3),
  };

  @override
  void initState() {
    super.initState();
    _title = '${widget.exerciseData['movement']} - ${widget.exerciseData['variant']}';

    _warmupSets = [LoggedSet(seriesIndex: 1, isWarmup: true)];
    _workSets = [];
    final prescriptions = widget.exerciseData['prescriptions'] as List? ?? [];
    int seriesCounter = 1;
    for (var p in prescriptions) {
      final setData = p as Map<String, dynamic>;
      final setCount = setData['sets'] as int? ?? 1;
      for (int i = 0; i < setCount; i++) {
        final set = LoggedSet(seriesIndex: seriesCounter++, isWarmup: false);
        set.repsCtrl.text = setData['reps'] ?? '';
        set.rpeCtrl.text = setData['effort'] ?? '';
        _workSets.add(set);
      }
    }
  }

  Future<void> _handleSetCompletion(LoggedSet set) async {
    // Si se desmarca, por ahora solo lo actualiza visualmente
    if (set.isCompleted) {
      setState(() => set.isCompleted = false);
      // Aquí podrías añadir lógica para borrar el set de la BD si es necesario
      return;
    }

    // Asegurar que los datos mínimos están
    final weight = double.tryParse(set.weightCtrl.text);
    final reps = int.tryParse(set.repsCtrl.text);
    if (weight == null || reps == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa peso y reps.')),
      );
      return;
    }

    final rpe = double.tryParse(set.rpeCtrl.text);

    // 1. Asegurar que la sesión del día existe
    final uid = supa.auth.currentUser!.id;
    final day = yyyymmdd(widget.date);
    final sessionRes = await supa.from('sessions').select('id').eq('user_id', uid).eq('session_date', day).maybeSingle();

    String sessionId;
    if (sessionRes == null) {
      final newSession = await supa.from('sessions').insert({'user_id': uid, 'session_date': day}).select().single();
      sessionId = newSession['id'];
    } else {
      sessionId = sessionRes['id'];
    }

    // 2. Guardar el set
    await supa.from('sets').insert({
      'session_id': sessionId,
      'user_id': uid,
      'exercise_name': _title, // Guardamos el nombre completo para simplicidad
      'is_warmup': set.isWarmup,
      'set_index': set.seriesIndex,
      'weight_kg': weight,
      'reps': reps,
      'rpe': rpe,
    });

    setState(() => set.isCompleted = true);
    _startRestTimer(isWarmup: set.isWarmup);
  }

  void _startRestTimer({required bool isWarmup}) {
    _restTimer?.cancel();
    final type = isWarmup ? 'warmup' : (widget.exerciseData['isAccessory'] ?? false) ? 'accessory' : 'basic';

    setState(() {
      _restSecondsRemaining = _restDurations[type]!.inSeconds;
    });

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_restSecondsRemaining > 0) {
        setState(() => _restSecondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _warmupSets.forEach((s) {
      s.weightCtrl.dispose();
      s.repsCtrl.dispose();
      s.rpeCtrl.dispose();
    });
    _workSets.forEach((s) {
      s.weightCtrl.dispose();
      s.repsCtrl.dispose();
      s.rpeCtrl.dispose();
    });
    super.dispose();
  }

  String get _timerDisplay {
    if (_restSecondsRemaining <= 0) return '';
    final minutes = (_restSecondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_restSecondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_restSecondsRemaining > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(_timerDisplay, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('Series de Calentamiento', style: Theme.of(context).textTheme.titleMedium),
          ..._warmupSets.asMap().entries.map((entry) {
            return SeriesRowWidget(
              seriesLabel: 'Warm-up ${entry.key + 1}',
              loggedSet: entry.value,
              repsHint: '',
              effortHint: '',
              onCheckChanged: () => _handleSetCompletion(entry.value),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _warmupSets.add(LoggedSet(seriesIndex: _warmupSets.length + 1, isWarmup: true))),
              icon: const Icon(Icons.add),
              label: const Text('Añadir Calentamiento'),
            ),
          ),

          const Divider(height: 32),

          Text('Series Efectivas', style: Theme.of(context).textTheme.titleMedium),
          ..._workSets.asMap().entries.map((entry) {
            return SeriesRowWidget(
              seriesLabel: 'Serie ${entry.key + 1}',
              loggedSet: entry.value,
              repsHint: entry.value.repsCtrl.text,
              effortHint: entry.value.rpeCtrl.text,
              onCheckChanged: () => _handleSetCompletion(entry.value),
            );
          }),
        ],
      ),
    );
  }
}