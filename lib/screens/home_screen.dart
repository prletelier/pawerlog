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

  String _buildPrescriptionSummary(Map<String, dynamic> exerciseData) {
    if (exerciseData['prescriptions'] is! List) {
      return "Prescripción no definida.";
    }

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

  // --- NUEVA FUNCIÓN DE AYUDA ---
  // Reutilizamos la lógica para construir el título correctamente
  String _buildExerciseTitle(Map<String, dynamic> exerciseData) {
    String title = exerciseData['movement'] ?? 'Ejercicio sin nombre';
    // Leemos la nueva lista 'variants' en lugar del antiguo 'variant'
    final variants = exerciseData['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      title += ' - ${variants.join(' ')}'; // Une las variantes con un espacio
    }
    return title;
  }
  // --------------------------------

  Future<Map<String, dynamic>?> _loadDayPlan(DateTime date) async {
    final uid = supa.auth.currentUser!.id;
    final day = yyyymmdd(date);
    final response = await supa
        .from('plan_items')
        .select(
        'planned_date, prescription, block_id, blocks(name, start_date, days_per_week)')
        .eq('user_id', uid)
        .eq('planned_date', day)
        .maybeSingle();
    return response;
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
            Text(yyyymmdd(_cursorDate)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                      () => _cursorDate = _cursorDate.add(const Duration(days: 1))),
            ),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _loadDayPlan(_cursorDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(
                child: Text('No hay entrenamiento planificado para este día.'));
          }

          final plan = snapshot.data!;
          final plannedDateStr = plan['planned_date'] as String?;
          final blockId = plan['block_id'];
          final blockData = plan['blocks'] as Map<String, dynamic>?;

          if (plannedDateStr == null || blockId == null || blockData == null) {
            return const Center(child: Text('Datos del plan incompletos.'));
          }

          final blockName = blockData['name'] as String? ?? 'Bloque';
          final daysPerWeek = blockData['days_per_week'] as int?;
          final plannedDate = DateTime.parse(plannedDateStr);

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: supa
                .from('plan_items')
                .select('planned_date')
                .eq('block_id', blockId)
                .order('planned_date', ascending: true),
            builder: (context, planItemsSnapshot) {
              if (!planItemsSnapshot.hasData ||
                  planItemsSnapshot.data == null) {
                return ListTile(
                    title: Text(blockName),
                    subtitle: Text(formatFullDate(plannedDate)));
              }

              final trainingDays = planItemsSnapshot.data!
                  .map((item) => item['planned_date'] as String)
                  .toList();
              final overallDayNumber =
                  trainingDays.indexOf(plannedDateStr) + 1;

              final dayDisplayNumber = (daysPerWeek != null && daysPerWeek > 0)
                  ? (overallDayNumber - 1) % daysPerWeek + 1
                  : overallDayNumber;

              final fullDateString = formatFullDate(plannedDate);
              final newTitle = '$blockName - Día $dayDisplayNumber';

              final prescription =
              plan['prescription'] as Map<String, dynamic>?;
              final exercises = prescription?['exercises'] as List? ?? [];

              return Column(
                children: [
                  ListTile(
                    title: Text(newTitle),
                    subtitle: Text(fullDateString),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DaySessionScreen(
                              date: _cursorDate, plan: plan)),
                    ).then((_) => setState(() {})),
                  ),
                  const Divider(height: 1),

                  // La lista de ejercicios mostrada directamente
                  if (exercises.isNotEmpty)
                  // Usamos un ListView para que sea scrollable si la lista es muy larga
                    Expanded(
                      child: ListView.builder(
                        itemCount: exercises.length,
                        itemBuilder: (context, index) {
                          final exerciseData =
                          exercises[index] as Map<String, dynamic>;

                          // --- LÍNEA CORREGIDA ---
                          // Usamos la nueva función de ayuda para construir el título
                          final title = _buildExerciseTitle(exerciseData);
                          // -------------------------

                          final summary =
                          _buildPrescriptionSummary(exerciseData);
                          return ListTile(
                            dense: true,
                            title: Text(title),
                            subtitle: Text(summary),
                          );
                        },
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No hay ejercicios definidos para este día.'),
                    )
                ],
              );
            },
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