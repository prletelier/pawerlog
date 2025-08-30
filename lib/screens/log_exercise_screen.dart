// lib/screens/log_exercise_screen.dart
import '../utils/helpers.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/models.dart';
import '../widgets/series_row_widget.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// Pantalla para registrar los sets de un ejercicio específico en una fecha dada.
/// Permite al usuario introducir peso, reps y RPE para cada serie, tanto de
/// calentamiento como efectivas.
/// Permite marcar sets como completados, agregar nuevos sets, y manejar tiempos de descanso.
class LogExerciseScreen extends StatefulWidget {
  final DateTime date;
  final Map<String, dynamic> exerciseData;

  const LogExerciseScreen(
      {super.key, required this.date, required this.exerciseData});

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
    _title = _buildExerciseTitle(widget.exerciseData);
    _loadAndBuildState();
  }

  String _buildExerciseTitle(Map<String, dynamic> exerciseData) {
    String title = exerciseData['movement'] ?? 'Ejercicio sin nombre';
    final variants = exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      title += ' - ${variants.join(' ')}';
    }
    return title;
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

      for (var s in _warmupSets) {
        s.dispose();
      }
      for (var s in _workSets) {
        s.dispose();
      }
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
          set.isCompleted = data['is_completed'] ?? false;
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
    _workSets = [];
    final prescriptions = List<Map<String, dynamic>>.from(
        widget.exerciseData['prescriptions'] ?? []);
    int seriesCounter = 1;

    for (var p in prescriptions) {
      final isRampUp = p['isRampUp'] as bool? ?? false;
      final setCount = int.tryParse(p['sets']?.toString() ?? '1') ?? 1;
      final reps = p['reps']?.toString() ?? '';
      String currentEffort = p['effort']?.toString() ?? '';

      if (isRampUp && setCount > 1) {
        for (int i = 0; i < setCount; i++) {
          final set = LoggedSet(seriesIndex: seriesCounter++, isWarmup: false);
          set.repsCtrl.text = reps;
          set.rpeCtrl.text = currentEffort;
          _workSets.add(set);
          currentEffort = incrementEffort(currentEffort);
        }
      } else {
        for (int i = 0; i < setCount; i++) {
          final set = LoggedSet(seriesIndex: seriesCounter++, isWarmup: false);
          set.repsCtrl.text = reps;
          set.rpeCtrl.text = currentEffort;
          _workSets.add(set);
        }
      }
    }
  }

  Future<void> _handleSetCompletion(LoggedSet set) async {
    try {
      if (set.isCompleted) {
        await _handleSetRemoval(set);
        return;
      }
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
        'session_id': sessionId,
        'user_id': uid,
        'session_date': day,
        'exercise_name': _title,
        'is_warmup': set.isWarmup,
        'set_index': set.seriesIndex,
        'weight': weight,
        'reps': reps,
        'rpe': set.rpeCtrl.text,
        'is_completed': true,
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
      _recalculateBackOffs();
      _startRestTimer(isWarmup: set.isWarmup);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Recalcula los pesos sugeridos para las series de trabajo no completadas
  /// basándose en la primera serie completada (top set) y los porcentajes de
  /// reducción de esfuerzo indicados en el campo de esfuerzo (RPE/RIR).
  void _recalculateBackOffs() {
    LoggedSet? topSet;

    // 1. Buscamos la PRIMERA serie de trabajo (work set) completada.
    //    Esta será nuestra única referencia (la top set).
    try {
      topSet = _workSets.firstWhere(
              (s) => s.isCompleted && !s.rpeCtrl.text.startsWith('-'));
    } catch (e) {
      // Si no se encuentra ninguna, no hacemos nada.
      return;
    }

    final topSetWeight = double.tryParse(topSet.weightCtrl.text);
    if (topSetWeight == null) return;

    // 2. Ahora, recorremos TODAS las series de trabajo.
    for (final s in _workSets) {
      // Solo modificamos las que AÚN NO han sido completadas.
      if (!s.isCompleted) {
        final effort = s.rpeCtrl.text;
        if (effort.startsWith('-') && effort.endsWith('%')) {
          final percentageString =
          effort.replaceAll('-', '').replaceAll('%', '').trim();
          final percentage = double.tryParse(percentageString);
          if (percentage != null) {
            final backOffWeight = topSetWeight * (1 - (percentage / 100));
            // Rellenamos el campo de peso con el valor calculado.
            s.weightCtrl.text = backOffWeight.toStringAsFixed(1);
          }
        }
      }
    }

    // 3. Forzamos un redibujado de la UI para mostrar los nuevos pesos sugeridos.
    setState(() {});
  }

  /// Maneja el evento de eliminar una serie de la lista, tanto de la UI
  /// como de la base de datos (si ya estaba guardada).
  Future<void> _handleSetRemoval(LoggedSet setToRemove) async {
    _restTimer?.cancel();
    if(mounted) setState(() => _restSecondsRemaining = 0);

    if (setToRemove.db_id != null) {
      try {
        await supa.from('sets').delete().eq('set_id', setToRemove.db_id!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error al borrar el set: $e')));
        }
        return;
      }
    }
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

  /// Inicia el temporizador de descanso con la duración apropiada.
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
    // Libera todos los recursos para evitar fugas de memoria.
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

  /// Formatea los segundos restantes en un string MM:SS.
  String get _timerDisplay {
    if (_restSecondsRemaining <= 0) return '';
    final minutes = (_restSecondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_restSecondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Se ejecuta al presionar el botón "Ejercicio Completado".
  /// Vuelve a la pantalla anterior devolviendo 'true' para indicar que hubo cambios.
  void _completeExercise() {
    Navigator.of(context).pop(true);
  }

  /// Añade una nueva serie de calentamiento a la lista.
  void _addWarmupSet() {
    setState(() {
      final nextIndex = _warmupSets.isEmpty ? 1 : (_warmupSets.map((s) => s.seriesIndex).reduce(max)) + 1;
      _warmupSets.add(LoggedSet(seriesIndex: nextIndex, isWarmup: true));
    });
  }

  /// Añade una nueva serie efectiva a la lista.
  void _addWorkSet() {
    setState(() {
      final nextIndex = _workSets.isEmpty ? 1 : (_workSets.map((s) => s.seriesIndex).reduce(max)) + 1;
      _workSets.add(LoggedSet(seriesIndex: nextIndex, isWarmup: false));
    });
  }

  /// Incrementa el esfuerzo (RPE o RIR) de una serie de acuerdo a las reglas definidas.
  /// Si es RPE, se incrementa el valor; si es RIR, se decrementa.
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
                Builder(
                    builder: (context) {
                      final notes = widget.exerciseData['notes'] as String? ?? '';
                      // Si la nota no está vacía, mostramos el recuadro
                      if (notes.isNotEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12.0),
                          margin: const EdgeInsets.only(bottom: 16.0),
                          decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3))
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text(notes)),
                            ],
                          ),
                        );
                      }
                      // Si no hay nota, no mostramos nada
                      return const SizedBox.shrink();
                    }
                ),
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
                }),
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
                }),
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