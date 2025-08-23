// lib/screens/generate_block_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import '../utils/models.dart';
import 'home_screen.dart';
import 'dart:math';

/// Una pantalla Stateful que permite al usuario configurar y generar un nuevo
/// bloque de entrenamiento completo.
class GenerateBlockScreen extends StatefulWidget {
  const GenerateBlockScreen({super.key});

  @override
  State<GenerateBlockScreen> createState() => _GenerateBlockScreenState();
}

/// El estado asociado a [GenerateBlockScreen].
/// Maneja la lógica de carga de datos, la interacción del usuario con el formulario
/// y el guardado final del bloque en Supabase.
class _GenerateBlockScreenState extends State<GenerateBlockScreen> {
  final supa = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Controladores y variables para la configuración del bloque.
  final _blockNameCtrl = TextEditingController(text: 'Bloque 1');
  int _weeks = 4;
  final Set<int> _activeDays = {1, 2, 4, 5}; // L, M, J, V por defecto
  late DateTime _startDate;

  // Variables de estado para los datos cargados desde la BD.
  bool _isLoading = true;
  List<Map<String, dynamic>> _basicMovements = [];
  List<Map<String, dynamic>> _accessoryMovements = [];
  List<Map<String, dynamic>> _variants = [];

  // Mapa que almacena la lista de ejercicios planificados para cada día de la semana.
  final Map<int, List<PlannedExercise>> _exercisesPerDay = {};

  @override
  void initState() {
    super.initState();
    _startDate = _getNextMonday(DateTime.now());
    // Inicializa cada día activo con un ejercicio por defecto vacío.
    for (var day in _activeDays) {
      _exercisesPerDay[day] = [PlannedExercise()];
    }
    _loadInitialData();
  }

  /// Carga los datos iniciales (movimientos y variantes) desde Supabase.
  /// Se ejecuta una sola vez al iniciar la pantalla.
  Future<void> _loadInitialData() async {
    try {
      final responses = await Future.wait([
        supa.from('movements').select().order('name', ascending: true),
        supa.from('variants').select().order('name', ascending: true),
      ]);

      final movementsRes = responses[0] as List<dynamic>;
      final variantsRes = responses[1] as List<dynamic>;

      if (mounted) {
        setState(() {
          _variants = List<Map<String, dynamic>>.from(variantsRes);
          // Filtra los movimientos en dos listas para facilitar su uso en la UI.
          _basicMovements = List<Map<String, dynamic>>.from(
              movementsRes.where((m) => m['type'] == 'Básico'));
          _accessoryMovements = List<Map<String, dynamic>>.from(
              movementsRes.where((m) => m['type'] == 'Accesorio'));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos iniciales: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  /// Muestra un calendario emergente para que el usuario seleccione la fecha de inicio del bloque.
  Future<void> _selectStartDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate != null && pickedDate != _startDate) {
      setState(() => _startDate = pickedDate);
    }
  }

  /// Valida el formulario, construye los objetos de datos y los sube a Supabase.
  /// Crea un registro en la tabla 'blocks' y múltiples registros en 'plan_items'.
  Future<void> _generateBlock() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = supa.auth.currentUser!.id;
    final startDate = _startDate;

    // 1. Crea el registro principal del bloque.
    final blockResponse = await supa.from('blocks').insert({
      'user_id': uid,
      'name': _blockNameCtrl.text,
      'start_date': yyyymmdd(startDate),
      'end_date': yyyymmdd(startDate.add(Duration(days: _weeks * 7 - 1))),
      'days_per_week': _activeDays.length,
    }).select('block_id').single();
    final blockId = blockResponse['block_id'];

    // 2. Prepara todos los 'plan_items' (un registro por cada día de entrenamiento).
    final List<Map<String, dynamic>> planItemsToInsert = [];
    for (int week = 0; week < _weeks; week++) {
      for (int dayOfWeek in _activeDays.toList()..sort()) {
        final date =
        startDate.add(Duration(days: (week * 7) + (dayOfWeek - 1)));
        final exercisesForThisDay = _exercisesPerDay[dayOfWeek] ?? [];
        if (exercisesForThisDay.isNotEmpty) {
          planItemsToInsert.add({
            'user_id': uid,
            'block_id': blockId,
            'planned_date': yyyymmdd(date),
            // La prescripción completa del día se guarda como un objeto JSON.
            'prescription': {
              'exercises': exercisesForThisDay.map((ex) {
                // Preparamos las prescripciones para ser guardadas
                final prescriptionsToSave = ex.prescriptions.map((p) {
                  return {
                    'sets': p.sets,
                    'reps': p.reps,
                    'effort': p.effort,
                    'isRampUp': p.isRampUp
                  };
                }).toList();

                return {
                  'movement': ex.movement,
                  'variants': ex.selectedVariants,
                  'tempo_digits': ex.tempoDigits,
                  'isAccessory': ex.isAccessory,
                  'notes': ex.notes,
                  'prescriptions': prescriptionsToSave,
                };
              }).toList(),
            },
          });
        }
      }
    }

    // 3. Sube todos los planes a la base de datos en una sola operación.
    if (planItemsToInsert.isNotEmpty) {
      await supa.from('plan_items').insert(planItemsToInsert);
    }

    // 4. Muestra confirmación y vuelve a la pantalla principal.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Bloque generado correctamente.')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
      );
    }
  }

  /// Calcula la fecha del próximo lunes a partir de una fecha dada.
  DateTime _getNextMonday(DateTime date) {
    var checkDate = DateTime(date.year, date.month, date.day);
    if (checkDate.weekday == DateTime.monday) return checkDate;
    return checkDate
        .add(Duration(days: (DateTime.monday - checkDate.weekday + 7) % 7));
  }

  /// El metodo build es principalmente UI
  @override
  Widget build(BuildContext context) {
    final dayLabels = { 1: 'Lunes', 2: 'Martes', 3: 'Miércoles', 4: 'Jueves', 5: 'Viernes', 6: 'Sábado', 7: 'Domingo' };
    final sortedActiveDays = _activeDays.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Generador de Bloque')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _blockNameCtrl,
              decoration:
              const InputDecoration(labelText: 'Nombre del Bloque'),
              validator: (val) =>
              (val?.isEmpty ?? true) ? 'Ingresa un nombre' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Semanas:'),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: _weeks,
                  items: List.generate(10, (index) => index + 1)
                      .map((w) => DropdownMenuItem(
                      value: w, child: Text('$w')))
                      .toList(),
                  onChanged: (val) => setState(() => _weeks = val ?? 4),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha de Inicio'),
              subtitle: Text(yyyymmdd(_startDate)),
              onTap: _selectStartDate,
            ),
            const SizedBox(height: 16),
            const Text('Días de entrenamiento:'),
            Wrap(
              spacing: 8.0,
              children: dayLabels.entries.map((entry) {
                final isSelected = _activeDays.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value.substring(0, 3)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _activeDays.add(entry.key);
                        _exercisesPerDay.putIfAbsent(
                            entry.key, () => [PlannedExercise()]);
                      } else {
                        _activeDays.remove(entry.key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const Divider(height: 32),
            for (final dayOfWeek in sortedActiveDays)
              _DayEditor(
                key: ValueKey('day_editor_$dayOfWeek'),
                dayTitle: dayLabels[dayOfWeek]!,
                exercises: _exercisesPerDay[dayOfWeek]!,
                basicMovements: _basicMovements,
                accessoryMovements: _accessoryMovements,
                variants: _variants,
                onChanged: () => setState(() {}),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generateBlock,
        label: const Text('Generar Bloque'),
        icon: const Icon(Icons.check),
      ),
    );
  }
}

/// Un widget que representa la sección de un día de entrenamiento completo (ej. Lunes).
/// Contiene una lista de [_ExerciseEditor]s.
class _DayEditor extends StatelessWidget {
  final String dayTitle;
  final List<PlannedExercise> exercises;
  final List<Map<String, dynamic>> basicMovements;
  final List<Map<String, dynamic>> accessoryMovements;
  final List<Map<String, dynamic>> variants;
  final VoidCallback onChanged;

  const _DayEditor({
    super.key,
    required this.dayTitle,
    required this.exercises,
    required this.basicMovements,
    required this.accessoryMovements,
    required this.variants,
    required this.onChanged,
  });

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
                key: ValueKey(entry.value),
                exercise: entry.value,
                basicMovements: basicMovements,
                accessoryMovements: accessoryMovements,
                variants: variants,
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

/// Un widget para configurar un único ejercicio, sus variantes y sus prescripciones.
class _ExerciseEditor extends StatelessWidget {
  final PlannedExercise exercise;
  final List<Map<String, dynamic>> basicMovements;
  final List<Map<String, dynamic>> accessoryMovements;
  final List<Map<String, dynamic>> variants;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ExerciseEditor({
    super.key,
    required this.exercise,
    required this.basicMovements,
    required this.accessoryMovements,
    required this.variants,
    required this.onRemove,
    required this.onChanged,
  });

  /// Muestra un Dialog emergente para que el usuario introduzca una nueva línea
  /// de prescripción, con la opción de marcarla como 'Ramp Up'.
  Future<void> _showAddPrescriptionDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final setsCtrl = TextEditingController();
    final repsCtrl = TextEditingController();
    final effortCtrl = TextEditingController();
    final isRampUpNotifier = ValueNotifier<bool>(false);

    final PrescribedSet? newSet = await showDialog<PrescribedSet>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Añadir Prescripción'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: setsCtrl, decoration: const InputDecoration(labelText: 'Series', hintText: 'ej. 1, 3, 4')),
                TextFormField(controller: repsCtrl, decoration: const InputDecoration(labelText: 'Reps', hintText: 'ej. 5, 8-10')),
                TextFormField(controller: effortCtrl, decoration: const InputDecoration(labelText: 'Esfuerzo', hintText: 'ej. @8, RIR2, -15%')),
                ValueListenableBuilder<bool>(
                  valueListenable: isRampUpNotifier,
                  builder: (context, isRampUp, child) {
                    return CheckboxListTile(
                      title: const Text('Ramp Up'),
                      value: isRampUp,
                      onChanged: (val) {
                        isRampUpNotifier.value = val ?? false;
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final set = parsePrescriptionLine(
                    setsStr: setsCtrl.text,
                    repsStr: repsCtrl.text,
                    effortStr: effortCtrl.text,
                    isRampUp: isRampUpNotifier.value,
                  );
                  Navigator.of(context).pop(set);
                }
              },
              child: const Text('Añadir'),
            ),
          ],
        );
      },
    );

    if (newSet != null) {
      exercise.prescriptions.add(newSet);
      onChanged();
    }
  }

  /// El metodo build es principalmente UI
  /// Muestra dropdowns para seleccionar el movimiento y las variantes,
  /// así como la lista de prescripciones y un botón para añadir nuevas.
  /// También incluye un switch para marcar el ejercicio como accesorio.
  /// Las variantes y campos adicionales se muestran/ocultan según el estado.
  /// Utiliza [onChanged] para notificar cambios al padre.
  /// Utiliza [onRemove] para notificar que este ejercicio debe ser eliminado.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Acc.'),
                  Switch(
                    value: exercise.isAccessory,
                    onChanged: (val) {
                      exercise.isAccessory = val;
                      if (val) {
                        exercise.movement = '';
                        exercise.selectedVariants = [];
                      } else {
                        exercise.movement = '';
                        exercise.selectedVariants = ['Competición'];
                      }
                      onChanged();
                    },
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: exercise.isAccessory
                    ? DropdownButtonFormField<String>(
                  value: accessoryMovements.any((m) => m['name'] == exercise.movement) ? exercise.movement : null,
                  hint: const Text('Selecciona un accesorio'),
                  decoration: const InputDecoration(labelText: 'Accesorio'),
                  items: accessoryMovements.map((m) => DropdownMenuItem<String>(value: m['name'] as String, child: Text(m['name'] as String))).toList(),
                  onChanged: (val) {
                    exercise.movement = val ?? '';
                    onChanged();
                  },
                )
                    : DropdownButtonFormField<String>(
                  value: basicMovements.any((m) => m['name'] == exercise.movement) ? exercise.movement : null,
                  hint: const Text('Selecciona un movimiento'),
                  decoration: const InputDecoration(labelText: 'Movimiento'),
                  items: basicMovements.map((m) => DropdownMenuItem<String>(value: m['name'] as String, child: Text(m['name'] as String))).toList(),
                  onChanged: (val) {
                    exercise.movement = val ?? '';
                    onChanged();
                  },
                ),
              ),
              IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline))
            ],
          ),

          if (!exercise.isAccessory) ...[
            const SizedBox(height: 16),
            Text('Variantes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                // Botón para "Competición"
                FilterChip(
                  label: const Text('Competición'),
                  selected: exercise.selectedVariants.contains('Competición'),
                  onSelected: (selected) {
                    if (selected) {
                      exercise.selectedVariants.clear();
                      exercise.selectedVariants.add('Competición');
                    } else {
                      // Opcional: no permitir deseleccionar competición, solo cambiar a otra variante
                      exercise.selectedVariants.remove('Competición');
                    }
                    onChanged();
                  },
                ),
                const SizedBox(width: 8),
                // Botón que despliega el resto de las variantes
                PopupMenuButton<String>(
                  onSelected: (String variantName) {
                    // Lógica para añadir/quitar la variante seleccionada
                    if (exercise.selectedVariants.contains(variantName)) {
                      exercise.selectedVariants.remove(variantName);
                    } else {
                      // Al seleccionar una variante, se quita "Competición"
                      exercise.selectedVariants.remove('Competición');
                      exercise.selectedVariants.add(variantName);
                    }
                    onChanged();
                  },
                  itemBuilder: (BuildContext context) {
                    // Filtramos para no mostrar "Competición" en el menú
                    return variants
                        .where((v) => v['name'] != 'Competición')
                        .map((variant) {
                      final vName = variant['name'] as String;
                      return CheckedPopupMenuItem<String>(
                        value: vName,
                        checked: exercise.selectedVariants.contains(vName),
                        child: Text(vName),
                      );
                    }).toList();
                  },
                  child: const Chip(
                    label: Text('Variantes'),
                    avatar: Icon(Icons.arrow_drop_down, size: 18),
                  ),
                ),
              ],
            ),
            // Mostramos las variantes seleccionadas (que no son "Competición")
            if (exercise.selectedVariants.any((v) => v != 'Competición'))
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Wrap(
                  spacing: 6.0,
                  runSpacing: 4.0,
                  children: exercise.selectedVariants
                      .where((v) => v != 'Competición')
                      .map((variantName) => Chip(label: Text(variantName)))
                      .toList(),
                ),
              ),
          ],

          if (exercise.selectedVariants.contains('Tempo'))
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextFormField(
                initialValue: exercise.tempoDigits,
                decoration: const InputDecoration(labelText: 'Dígitos Tempo (ej. 420)'),
                keyboardType: TextInputType.number,
                onChanged: (val) => exercise.tempoDigits = val,
              ),
            ),

          if (exercise.selectedVariants.contains('Cluster'))
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextFormField(
                initialValue: exercise.tempoDigits,
                decoration: const InputDecoration(labelText: 'Tiempo Cluster (en segundos)'),
                keyboardType: TextInputType.number,
                onChanged: (val) => exercise.tempoDigits = val,
              ),
            ),

          const SizedBox(height: 12),
          Text('Prescripciones', style: Theme.of(context).textTheme.labelLarge),

          // --- SECCIÓN DE PRESCRIPCIONES CORREGIDA ---
          if (exercise.prescriptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Añade una línea de prescripción.', style: TextStyle(fontStyle: FontStyle.italic)),
            )
          else
            ...exercise.prescriptions.asMap().entries.map((entry) {
              final p = entry.value;
              final title = p.isRampUp
                  ? '${p.sets} x ${p.reps} ${p.effort} (Ramp Up)'
                  : '${p.sets} x ${p.reps} ${p.effort}';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(title),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () {
                    exercise.prescriptions.removeAt(entry.key);
                    onChanged();
                  },
                ),
              );
            }),

          TextButton.icon(
            onPressed: () => _showAddPrescriptionDialog(context),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Añadir Prescripción'),
          ),

          const SizedBox(height: 8),
          TextFormField(
            initialValue: exercise.notes,
            decoration: const InputDecoration(labelText: 'Notas (Opcional)'),
            onChanged: (val) => exercise.notes = val,
          ),
        ],
      ),
    );
  }
}