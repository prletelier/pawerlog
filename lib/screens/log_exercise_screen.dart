// lib/screens/log_exercise_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import '../utils/models.dart';
import '../widgets/series_row_widget.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

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
  final _audioPlayer = AudioPlayer();

  late final String _title;
  List<LoggedSet> _warmupSets = [];
  List<LoggedSet> _workSets = [];
  bool _isLoading = true;

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
    String tempTitle = widget.exerciseData['movement'] ?? 'Ejercicio';
    final variants = widget.exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      tempTitle += ' - ${variants.join(' ')}';
    }
    _title = tempTitle;
    _loadAndBuildState();
  }

  Future<void> _loadAndBuildState() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final uid = supa.auth.currentUser!.id;
      final day = yyyymmdd(widget.date);

      final response = await supa
          .from('sets')
          .select()
          .eq('user_id', uid)
          .eq('session_date', day)
          .eq('exercise_name', _title)
          .order('is_warmup', ascending: false)
          .order('set_index', ascending: true);

      _warmupSets.forEach((s) => s.dispose());
      _workSets.forEach((s) => s.dispose());
      _warmupSets.clear();
      _workSets.clear();

      if (response.isNotEmpty) {
        final loggedSetsData = response as List<dynamic>;
        for (var data in loggedSetsData) {
          final set = LoggedSet(
              db_id: data['set_id'],
              seriesIndex: data['set_index'],
              isWarmup: data['is_warmup']);
          set.weightCtrl.text = data['weight']?.toString() ?? '';
          set.repsCtrl.text = data['reps']?.toString() ?? '';
          set.rpeCtrl.text = data['rpe']?.toString() ?? '';
          set.isCompleted = data['is_completed'] ?? false; // Leemos el nuevo estado

          if (set.isWarmup) {
            _warmupSets.add(set);
          } else {
            _workSets.add(set);
          }
        }
      } else {
        _initializeSetsFromPlan();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initializeSetsFromPlan() {
    _warmupSets = [LoggedSet(seriesIndex: 1, isWarmup: true)];
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
    // Si la serie ya está completa, la desmarcamos y borramos.
    if (set.isCompleted) {
      await _handleSetRemoval(set);
      return;
    }

    // Si no está completa, la guardamos.
    final weight = double.tryParse(set.weightCtrl.text);
    final reps = int.tryParse(set.repsCtrl.text);
    if (weight == null || reps == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, ingresa peso y reps.')),
        );
      }
      return;
    }

    final uid = supa.auth.currentUser!.id;
    final day = yyyymmdd(widget.date);

    final sessionRes = await supa
        .from('sessions')
        .upsert({'user_id': uid, 'session_date': day}).select().single();
    final sessionId = sessionRes['session_id'];

    final Map<String, dynamic> setData = {
      'session_id': sessionId, 'user_id': uid, 'session_date': day,
      'exercise_name': _title, 'is_warmup': set.isWarmup,
      'set_index': set.seriesIndex, 'weight': weight,
      'reps': reps,
      'rpe': set.rpeCtrl.text,
      'is_completed': true, // Al marcarla, siempre la ponemos como completa.
    };

    if (set.db_id != null) {
      setData['set_id'] = set.db_id;
    }

    final savedSetData =
    await supa.from('sets').upsert(setData).select().single();

    setState(() {
      set.isCompleted = true;
      set.db_id = savedSetData['set_id'];
    });

    _startRestTimer(isWarmup: set.isWarmup);
  }

  // La función de borrado se mantiene para los botones de eliminar
  Future<void> _handleSetRemoval(LoggedSet setToRemove) async {
    // 1. Detenemos cualquier timer activo.
    _restTimer?.cancel();
    if (mounted) setState(() => _restSecondsRemaining = 0);

    // 2. Si la serie existe en la base de datos (tiene un db_id), la borramos.
    if (setToRemove.db_id != null) {
      try {
        await supa.from('sets').delete().eq('set_id', setToRemove.db_id!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al borrar el set en la BD: $e')));
        }
        return; // Importante: si falla el borrado, no continuamos.
      }
    }

    // 3. Solo si el borrado en la BD fue exitoso (o no fue necesario),
    //    la quitamos de la lista local y actualizamos la UI.
    if (mounted) {
      setState(() {
        if (setToRemove.isWarmup) {
          _warmupSets.remove(setToRemove);
        } else {
          _workSets.remove(setToRemove);
        }
        setToRemove.dispose();
      });
    }
  }

  void _startRestTimer({required bool isWarmup}) {
    _restTimer?.cancel();
    final type = isWarmup ? 'warmup' : (widget.exerciseData['isAccessory'] ?? false) ? 'accessory' : 'basic';
    if(mounted) setState(() => _restSecondsRemaining = _restDurations[type]!.inSeconds);

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_restSecondsRemaining > 0) {
        if(mounted) setState(() => _restSecondsRemaining--);
      } else {
        timer.cancel();
        if (mounted) setState((){});
        await _audioPlayer.play(AssetSource('audio/notification.mp3'));
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 500);
        }
      }
    });
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _audioPlayer.dispose();
    for (var s in _warmupSets) {
      s.dispose();
    }
    for (var s in _workSets) {
      s.dispose();
    }
    super.dispose();
  }

  String get _timerDisplay {
    if (_restSecondsRemaining <= 0) return '';
    final minutes = (_restSecondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_restSecondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _completeExercise() {
    Navigator.of(context).pop(true);
  }

  void _addWarmupSet() {
    setState(() {
      final nextIndex = _warmupSets.isEmpty ? 1 : (_warmupSets.map((s) => s.seriesIndex).reduce(max)) + 1;
      _warmupSets.add(LoggedSet(seriesIndex: nextIndex, isWarmup: true));
    });
  }

  void _addWorkSet() {
    setState(() {
      final nextIndex = _workSets.isEmpty ? 1 : (_workSets.map((s) => s.seriesIndex).reduce(max)) + 1;
      _workSets.add(LoggedSet(seriesIndex: nextIndex, isWarmup: false));
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool areAllSetsCompleted =
        _workSets.isNotEmpty && _workSets.every((set) => set.isCompleted);
    return Scaffold(
      appBar: AppBar(title: Text(_title),),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (_restSecondsRemaining > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(children: [
                Text(_timerDisplay, style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary,),),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(onPressed: () {if(mounted) setState(() {_restSecondsRemaining = (_restSecondsRemaining - 15).clamp(0, 999);});}, child: const Text('-15s'),),
                    const SizedBox(width: 24),
                    OutlinedButton(onPressed: () {if(mounted) setState(() {_restSecondsRemaining += 15;});}, child: const Text('+15s'),),
                  ],
                )
              ],),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text('Series de Calentamiento', style: Theme.of(context).textTheme.titleMedium),
                if (_warmupSets.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('No hay series de calentamiento.', style: TextStyle(fontStyle: FontStyle.italic))),
                ..._warmupSets.map((set) {
                  return SeriesRowWidget(
                    seriesLabel: 'Warm-up',
                    loggedSet: set,
                    repsHint: '',
                    effortHint: '',
                    onCheckChanged: () => _handleSetCompletion(set),
                    onRemove: () => _handleSetRemoval(set),
                  );
                }).toList(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: _addWarmupSet, icon: const Icon(Icons.add), label: const Text('Añadir Calentamiento'),),
                ),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Series Efectivas', style: Theme.of(context).textTheme.titleMedium),
                    IconButton(onPressed: _addWorkSet, icon: const Icon(Icons.add_circle),),
                  ],
                ),
                if (_workSets.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('No hay series efectivas.', style: TextStyle(fontStyle: FontStyle.italic))),
                ..._workSets.map((set) {
                  return SeriesRowWidget(
                    seriesLabel: 'Serie ${set.seriesIndex}',
                    loggedSet: set,
                    repsHint: set.repsCtrl.text,
                    effortHint: set.rpeCtrl.text,
                    onCheckChanged: () => _handleSetCompletion(set),
                    onRemove: () => _handleSetRemoval(set),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: areAllSetsCompleted ? _completeExercise : null,
          child: const Text('Ejercicio Completado'),
        ),
      ),
    );
  }
}