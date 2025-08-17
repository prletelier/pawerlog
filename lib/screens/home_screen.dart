// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import 'day_session_screen.dart';
import 'generate_block_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supa = Supabase.instance.client;
  DateTime _cursorDate = DateTime.now();

  // MODIFICADO: Ahora carga el plan, la sesión Y los sets completados
  Future<Map<String, dynamic>> _loadDayData(DateTime date) async {
    final uid = supa.auth.currentUser!.id;
    final day = yyyymmdd(date);

    final responses = await Future.wait([
      supa
          .from('plan_items')
          .select(
          'planned_date, prescription, block_id, blocks(name, start_date, days_per_week)')
          .eq('user_id', uid)
          .eq('planned_date', day)
          .maybeSingle(),
      supa
          .from('sessions')
          .select('status, started_at, duration_min')
          .eq('user_id', uid)
          .eq('session_date', day)
          .limit(1)
          .maybeSingle(),
      // NUEVA CONSULTA: Traemos los sets guardados para este día
      supa
          .from('sets')
          .select('exercise_name, weight, reps, rpe, is_warmup, is_completed')
          .eq('user_id', uid)
          .eq('session_date', day)
          .eq('is_completed', true)
          .order('created_at', ascending: true),
    ]);

    return {
      'plan': responses[0],
      'session': responses[1],
      'logged_sets': responses[2], // Añadimos los sets al resultado
    };
  }

  Future<void> _selectDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _cursorDate,
      // Permitimos navegar un año hacia atrás y hacia adelante
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    // Si el usuario selecciona una fecha, actualizamos el estado
    if (pickedDate != null && pickedDate != _cursorDate) {
      setState(() {
        _cursorDate = pickedDate;
      });
    }
  }

  String _buildPrescriptionSummary(Map<String, dynamic> exerciseData) {
    final prescriptions = (exerciseData['prescriptions'] as List? ?? []);
    if (prescriptions.isEmpty) return "Sin series definidas.";
    return prescriptions.map((p) {
      final setData = p as Map<String, dynamic>;
      final sets = setData['sets'] ?? 1;
      final reps = setData['reps'] ?? 'N/A';
      final effort = setData['effort'] ?? '';
      return "$sets x $reps $effort";
    }).join('  |  ');
  }

  String _buildExerciseTitle(Map<String, dynamic> exerciseData) {
    String title = exerciseData['movement'] ?? 'Ejercicio sin nombre';
    final variants = exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      title += ' - ${variants.join(' ')}';
    }
    return title;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() =>
                  _cursorDate = _cursorDate.subtract(const Duration(days: 1))),
                ),
                TextButton(
                  onPressed: () => setState(() => _cursorDate = DateTime.now()),
                  child: const Text('HOY'),
                ),
              ],
            ),
            TextButton(
              onPressed: _selectDate,
              // Le damos estilo al botón para que su texto sea del color correcto
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              child: Text(
                yyyymmdd(_cursorDate),
                // El estilo del texto ya no necesita definir el color
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                      () => _cursorDate = _cursorDate.add(const Duration(days: 1))),
            ),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadDayData(_cursorDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final plan = snapshot.data?['plan'];
          final session = snapshot.data?['session'];
          // Extraemos los nuevos datos
          final loggedSets = snapshot.data?['logged_sets'] as List<dynamic>? ?? [];
          final sessionStatus = session?['status'] ?? 'planificada';

          if (plan == null) {
            return const Center(
                child: Text('No hay entrenamiento planificado para este día.'));
          }

          Widget mainButton = ElevatedButton.icon(
            icon: Icon(sessionStatus == 'planificada' ? Icons.play_arrow : Icons.directions_run),
            label: Text(sessionStatus == 'planificada' ? 'Comenzar Sesión' : 'Continuar Sesión'),
            // EN home_screen.dart, en el onPressed del mainButton
            onPressed: () async {
              try {
                Map<String, dynamic>? updatedSession = session;
                if (sessionStatus == 'planificada') {
                  updatedSession = await supa.from('sessions').upsert({
                    'user_id': supa.auth.currentUser!.id,
                    'session_date': yyyymmdd(_cursorDate),
                    'status': 'activa',
                    'started_at': DateTime.now().toUtc().toIso8601String(),
                  }).select().single();
                }

                // El 'await' es clave para esperar a que vuelvas de la pantalla
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DaySessionScreen(
                        date: _cursorDate,
                        plan: plan,
                        initialSessionData: updatedSession,
                      )),
                );
                // Este setState se ejecutará DESPUÉS de que vuelvas.
                setState(() {});

              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}', style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          );

          final plannedDateStr = plan['planned_date'] as String?;
          final blockId = plan['block_id'];
          final blockData = plan['blocks'] as Map<String, dynamic>?;
          final prescription = plan['prescription'] as Map<String, dynamic>?;
          // Obtenemos los ejercicios planeados como antes
          final plannedExercises = prescription?['exercises'] as List? ?? [];

          // --- INICIO DE LA LÓGICA MODIFICADA ---
          // Agrupamos los sets guardados por nombre de ejercicio
          final Map<String, List<dynamic>> groupedLoggedSets = {};
          for (var set in loggedSets) {
            final exerciseName = set['exercise_name'];
            if (exerciseName != null) {
              groupedLoggedSets.putIfAbsent(exerciseName, () => []).add(set);
            }
          }

          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Card(
                  child: Column(
                    children: [
                      // El FutureBuilder para el título se mantiene igual
                      if (plannedDateStr != null && blockId != null && blockData != null)
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: supa.from('plan_items').select('planned_date').eq('block_id', blockId).order('planned_date', ascending: true),
                          builder: (context, planItemsSnapshot) {
                            if (!planItemsSnapshot.hasData) return ListTile(title: Text(blockData['name'] ?? 'Bloque'), subtitle: Text(formatFullDate(DateTime.parse(plannedDateStr))));

                            final trainingDays = planItemsSnapshot.data!.map((item) => item['planned_date'] as String).toList();
                            final overallDayNumber = trainingDays.indexOf(plannedDateStr) + 1;
                            final daysPerWeek = blockData['days_per_week'] as int?;
                            final dayDisplayNumber = (daysPerWeek != null && daysPerWeek > 0) ? (overallDayNumber - 1) % daysPerWeek + 1 : overallDayNumber;
                            final newTitle = '${blockData['name'] ?? 'Bloque'} - Día $dayDisplayNumber';

                            return ListTile(title: Text(newTitle), subtitle: Text(formatFullDate(DateTime.parse(plannedDateStr))));
                          },
                        )
                      else
                        const ListTile(title: Text("Resumen del día"), subtitle: Text("Toca comenzar para ver los ejercicios")),

                      // --- UI MODIFICADA ---
                      // Si la sesión NO está planificada (ya empezó o terminó) Y hay sets guardados,
                      // mostramos los datos reales. Si no, mostramos el plan.
                      if (sessionStatus != 'planificada' && loggedSets.isNotEmpty)
                      // Mostramos los datos REALES
                        ...groupedLoggedSets.entries.map((entry) {
                          final exerciseTitle = entry.key;
                          final sets = entry.value;
                          final summary = sets
                              .where((s) => s['is_warmup'] == false)
                              .map((s) => "${s['weight']}kg x ${s['reps']} ${s['rpe'] ?? ''}")
                              .join(' | ');

                          return ListTile(
                            dense: true,
                            title: Text(exerciseTitle),
                            subtitle: Text(summary, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                          );
                        }).toList()
                      else
                      // Mostramos el PLAN
                        ...plannedExercises.map((exerciseData) {
                          final title = _buildExerciseTitle(exerciseData);
                          final summary = _buildPrescriptionSummary(exerciseData);
                          return ListTile(dense: true, title: Text(title), subtitle: Text(summary));
                        }).toList(),
                      // --- FIN UI MODIFICADA ---
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                mainButton,
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GenerateBlockScreen()),
        ).then((_) => setState(() {})),
        label: const Text('Generar Bloque'),
        icon: const Icon(Icons.auto_awesome),
      ),
    );
  }
}