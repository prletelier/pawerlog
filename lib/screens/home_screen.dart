// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import 'day_session_screen.dart';
import 'generate_block_screen.dart';
import 'blocks_screen.dart';
import 'calendar_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';

/// La pantalla principal de la aplicación.
/// Muestra el plan de entrenamiento para un día seleccionado y permite navegar entre días.
class HomeScreen extends StatefulWidget {
  final DateTime? initialDate;
  const HomeScreen({super.key, this.initialDate});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// El estado para [HomeScreen].
/// Maneja la fecha actual visible, carga los datos del plan y la sesión,
/// y construye la interfaz de usuario correspondiente.
class _HomeScreenState extends State<HomeScreen> {
  final supa = Supabase.instance.client;
  DateTime _cursorDate = DateTime.now();

  /// Carga todos los datos necesarios para un día específico desde Supabase.
  /// Realiza tres consultas en paralelo:
  /// 1. El 'plan_item' del día, que contiene la prescripción.
  /// 2. La 'session' del día, que contiene el estado del entrenamiento (planificado, activo, etc.).
  /// 3. Todos los 'sets' completados para ese día, para mostrar el resumen real.
  /// Devuelve un mapa con toda esta información.
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

  /// Muestra un selector de fecha emergente y actualiza la fecha visible.
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

  /// Construye un resumen legible de una prescripción planeada.
  /// Ej: "2x5 @8 | 4x10-12 RIR2"
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

  /// Construye el título completo de un ejercicio, combinando movimiento y variantes.
  /// Ej: "Sentadillas - Pausa Tempo"
  String _buildExerciseTitle(Map<String, dynamic> exerciseData) {
    String title = exerciseData['movement'] ?? 'Ejercicio sin nombre';
    final variants = exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      title += ' - ${variants.join(' ')}';
    }
    return title;
  }

  @override
  void initState() {
    super.initState();
    _cursorDate = widget.initialDate ?? DateTime.now();
  }

  /// Construye la interfaz de usuario.
  /// Usa un [FutureBuilder] para cargar y mostrar los datos del día seleccionado.
  /// Permite navegar entre días y comenzar o continuar una sesión.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Mantenemos esto para control total
        title: Row(
          // No cambiamos el layout, solo añadimos un botón al principio
          children: [
            // Builder es necesario para darle al IconButton el 'context' correcto para encontrar el Drawer
            Builder(
                builder: (context) {
                  return IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () {
                      // Este comando abre el menú lateral
                      Scaffold.of(context).openDrawer();
                    },
                  );
                }
            ),
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
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Color(0xFF6F56B5), // Tu color principal
              ),
              child: Text(
                'Powerlog',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Sesión del Día'),
              onTap: () {
                // Cierra el menú y no hace nada más porque ya estamos aquí
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.view_quilt_outlined),
              title: const Text('Bloques'),
              onTap: () {
                Navigator.pop(context); // Cierra el menú
                Navigator.push(context, MaterialPageRoute(builder: (_) => const BlocksScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Calendario'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: const Text('Registro Histórico'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Estadísticas'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));
              },
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

          // Botón principal que cambia según si la sesión ha comenzado o no.
          Widget mainButton = ElevatedButton.icon(
            icon: Icon(sessionStatus == 'planificada' ? Icons.play_arrow : Icons.directions_run),
            label: Text(sessionStatus == 'planificada' ? 'Comenzar Sesión' : 'Continuar Sesión'),
            // EN home_screen.dart, en el onPressed del mainButton
            onPressed: () async {
              try {
                Map<String, dynamic>? updatedSession = session;
                if (sessionStatus == 'planificada') {
                  // Si la sesión no ha empezado, la marca como 'activa' en la BD.
                  updatedSession = await supa.from('sessions').upsert({
                    'user_id': supa.auth.currentUser!.id,
                    'session_date': yyyymmdd(_cursorDate),
                    'status': 'activa',
                    'started_at': DateTime.now().toUtc().toIso8601String(),
                  }).select().single();
                }

                // Navega a la pantalla de la sesión y espera a que el usuario vuelva.
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DaySessionScreen(
                        date: _cursorDate,
                        plan: plan,
                        initialSessionData: updatedSession,
                      )),
                );
                // Refresca la pantalla principal para reflejar cualquier cambio.
                // Se ejecutará DESPUÉS de que vuelvas.
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

          // Agrupa los sets registrados por nombre de ejercicio para mostrarlos.
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
                // FutureBuilder anidado para construir el título del bloque/día.
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

                      // Si la sesión ya empezó y hay datos, muestra el resumen real.
                      // Si no, muestra el plan.
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
                        })
                      else
                      // Mostramos el PLAN
                        ...plannedExercises.map((exerciseData) {
                          final title = _buildExerciseTitle(exerciseData);
                          final summary = _buildPrescriptionSummary(exerciseData);
                          return ListTile(dense: true, title: Text(title), subtitle: Text(summary));
                        }),
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