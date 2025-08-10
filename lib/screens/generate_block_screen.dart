// lib/screens/generate_block_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import '../utils/models.dart';
import 'home_screen.dart';

class GenerateBlockScreen extends StatefulWidget {
  const GenerateBlockScreen({super.key});

  @override
  State<GenerateBlockScreen> createState() => _GenerateBlockScreenState();
}

class _GenerateBlockScreenState extends State<GenerateBlockScreen> {
  final supa = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Configuración del bloque
  final _blockNameCtrl = TextEditingController(text: 'Bloque 8');
  int _weeks = 4;
  final Set<int> _activeDays = {1, 2, 4, 5}; // L, M, J, V por defecto

  // Datos para los formularios de cada día
  final Map<int, List<PlannedExercise>> _exercisesPerDay = {};

  @override
  void initState() {
    super.initState();
    // Inicializa con un ejercicio por defecto para los días activos
    for (var day in _activeDays) {
      _exercisesPerDay[day] = [PlannedExercise()];
    }
  }

  Future<void> _generateBlock() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = supa.auth.currentUser!.id;
    final startDate = _getNextMonday(DateTime.now());

    // 1. Crear el registro del bloque
    final blockResponse = await supa.from('blocks').insert({
      'user_id': uid,
      'name': _blockNameCtrl.text,
      'start_date': yyyymmdd(startDate),
      'end_date': yyyymmdd(startDate.add(Duration(days: _weeks * 7 - 1))),
      'days_per_week': _activeDays.length,
    }).select().single();

    final blockId = blockResponse['block_id'];

    // 2. Crear todos los plan_items para el bloque
    final List<Map<String, dynamic>> planItemsToInsert = [];
    for (int week = 0; week < _weeks; week++) {
      for (int dayOfWeek in _activeDays.toList()..sort()) {
        final date = startDate.add(Duration(days: (week * 7) + (dayOfWeek - 1)));
        final exercisesForThisDay = _exercisesPerDay[dayOfWeek] ?? [];

        if (exercisesForThisDay.isNotEmpty) {
          planItemsToInsert.add({
            'user_id': uid, // Asegúrate de que esta columna exista en tu tabla
            'block_id': blockId,
            'planned_date': yyyymmdd(date),
            // El campo 'prescription' guardará toda la rutina del día
            'prescription': {
              'exercises': exercisesForThisDay.map((ex) {
                // Combina variante y tempo si es necesario
                final finalVariant = effectiveVariant(ex.variant, ex.tempoDigits);
                return {
                  'movement': ex.movement,
                  'variant': finalVariant,
                  'isAccessory': ex.isAccessory,
                  'prescriptions': ex.prescriptions.map((p) => {
                    'sets': p.sets,
                    'reps': p.reps,
                    'effort': p.effort,
                  }).toList(),
                };
              }).toList(),
            },
          });
        }
      }
    }

    if (planItemsToInsert.isNotEmpty) {
      await supa.from('plan_items').insert(planItemsToInsert);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Bloque generado correctamente.')),
      );
      // Vuelve a la pantalla de inicio y la refresca
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
      );
    }
  }

  DateTime _getNextMonday(DateTime date) {
    var checkDate = DateTime(date.year, date.month, date.day);
    if (checkDate.weekday == DateTime.monday) return checkDate;
    return checkDate.add(Duration(days: (DateTime.monday - checkDate.weekday + 7) % 7));
  }

  @override
  Widget build(BuildContext context) {
    final dayLabels = {1: 'Lunes', 2: 'Martes', 3: 'Miércoles', 4: 'Jueves', 5: 'Viernes', 6: 'Sábado', 7: 'Domingo'};

    // 1. CREAR UNA LISTA ORDENADA PRIMERO
    final sortedActiveDays = _activeDays.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Generador de Bloque')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _blockNameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre del Bloque'),
              validator: (val) => (val?.isEmpty ?? true) ? 'Ingresa un nombre' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Semanas:'),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: _weeks,
                  items: [3, 4, 5, 6].map((w) => DropdownMenuItem(value: w, child: Text('$w'))).toList(),
                  onChanged: (val) => setState(() => _weeks = val ?? 4),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Días de entrenamiento:'),
            Wrap(
              spacing: 8.0,
              children: dayLabels.entries.map((entry) {
                final isSelected = _activeDays.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value.substring(0, 3)), // "Lun", "Mar", etc.
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _activeDays.add(entry.key);
                        _exercisesPerDay.putIfAbsent(entry.key, () => [PlannedExercise()]);
                      } else {
                        _activeDays.remove(entry.key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const Divider(height: 32),

            // 2. USAR LA LISTA YA ORDENADA PARA CREAR LOS WIDGETS
            for (final dayOfWeek in sortedActiveDays)
              _DayEditor(
                dayTitle: dayLabels[dayOfWeek]!,
                exercises: _exercisesPerDay[dayOfWeek]!,
                onChanged: () => setState(() {}),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generateBlock,
        label: const Text('Generar'),
        icon: const Icon(Icons.check),
      ),
    );
  }
}

// Widget para editar un día completo
class _DayEditor extends StatelessWidget {
  final String dayTitle;
  final List<PlannedExercise> exercises;
  final VoidCallback onChanged;

  const _DayEditor({ required this.dayTitle, required this.exercises, required this.onChanged });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dayTitle, style: Theme.of(context).textTheme.titleLarge),
            ...exercises.asMap().entries.map((entry) {
              return _ExerciseEditor(
                exercise: entry.value,
                onRemove: () {
                  exercises.removeAt(entry.key);
                  onChanged();
                },
                onChanged: onChanged,
              );
            }),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                exercises.add(PlannedExercise());
                onChanged();
              },
              icon: const Icon(Icons.add),
              label: const Text('Añadir Ejercicio'),
            )
          ],
        ),
      ),
    );
  }
}

// Widget para editar un solo ejercicio y sus prescripciones
class _ExerciseEditor extends StatelessWidget {
  final PlannedExercise exercise;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ExerciseEditor({ required this.exercise, required this.onRemove, required this.onChanged });

  @override
  Widget build(BuildContext context) {
    // Listas para los dropdowns
    final movements = ['SQ', 'BP', 'DL'];
    final variants = ['Competición', 'Tempo', 'Paused', 'Larsen', 'Spoto', 'Custom'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end, // 'end' alinea mejor los TextFields
            children: [
              Expanded(
                child: exercise.isAccessory
                    ? TextFormField(
                  initialValue: exercise.movement,
                  decoration: const InputDecoration(labelText: 'Nombre del Accesorio'),
                  onChanged: (val) => exercise.movement = val,
                )
                    : DropdownButtonFormField<String>(
                  value: exercise.movement,
                  decoration: const InputDecoration(labelText: 'Movimiento'),
                  items: movements.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) {
                    exercise.movement = val ?? 'SQ';
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8), // Un poco de espacio
              const Text('Acc.'),
              Switch(
                value: exercise.isAccessory,
                onChanged: (val) {
                  exercise.isAccessory = val;
                  if (val) {
                    exercise.movement = 'Accesorio';
                  } else {
                    exercise.movement = 'SQ';
                  }
                  onChanged();
                },
              ),
              IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline))
            ],
          ),
          if (!exercise.isAccessory)
            TextFormField(
                initialValue: exercise.variant,
                decoration: const InputDecoration(labelText: 'Variante'),
                onChanged: (val) {
                  exercise.variant = val;
                  onChanged();
                }
            ),
          if (exercise.variant.toLowerCase() == 'tempo' && !exercise.isAccessory)
            TextFormField(
              decoration: const InputDecoration(labelText: 'Dígitos Tempo (ej. 420)'),
              keyboardType: TextInputType.number,
              onChanged: (val) => exercise.tempoDigits = val,
            ),
          const SizedBox(height: 12),
          Text('Prescripciones', style: Theme.of(context).textTheme.labelLarge),
          ...exercise.prescriptions.asMap().entries.map((entry) {
            return _PrescriptionEditor(
              key: UniqueKey(),
              prescription: entry.value,
              onRemove: () {
                exercise.prescriptions.removeAt(entry.key);
                onChanged();
              },
            );
          }),
          TextButton.icon(
            onPressed: () {
              // Comprueba si ya existe al menos una prescripción
              if (exercise.prescriptions.isNotEmpty) {
                // Si existe, toma la última
                final lastPrescription = exercise.prescriptions.last;
                // Añade una nueva, copiando los valores de la anterior
                exercise.prescriptions.add(PrescribedSet(
                  sets: lastPrescription.sets,
                  reps: lastPrescription.reps,
                  effort: lastPrescription.effort,
                ));
              } else {
                // Si no hay ninguna, añade una por defecto
                exercise.prescriptions.add(PrescribedSet());
              }
              onChanged();
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Añadir línea de prescripción'),
          )
        ],
      ),
    );
  }
}

// Widget para editar una línea de prescripción (Sets x Reps @Esfuerzo)
class _PrescriptionEditor extends StatelessWidget {
  final PrescribedSet prescription;
  final VoidCallback onRemove;

  const _PrescriptionEditor({super.key, required this.prescription, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: '${prescription.sets}',
            decoration: const InputDecoration(labelText: 'Sets'),
            keyboardType: TextInputType.number,
            onChanged: (val) => prescription.sets = int.tryParse(val) ?? 1,
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('x')),
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: prescription.reps,
            decoration: const InputDecoration(labelText: 'Reps', hintText: '5 o 10-12'),
            onChanged: (val) => prescription.reps = val,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: prescription.effort,
            decoration: const InputDecoration(labelText: 'Esfuerzo', hintText: '@8, RIR2'),
            onChanged: (val) => prescription.effort = val,
          ),
        ),
        IconButton(onPressed: onRemove, icon: const Icon(Icons.remove_circle_outline, size: 20))
      ],
    );
  }
}