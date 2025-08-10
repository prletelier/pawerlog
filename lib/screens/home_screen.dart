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

  Future<Map<String, dynamic>?> _loadDayPlan(DateTime date) async {
    final uid = supa.auth.currentUser!.id;
    final day = yyyymmdd(date);
    final response = await supa
        .from('plan_items')
        .select('planned_date, prescription')
        .eq('user_id', uid)
        .eq('planned_date', day)
        .maybeSingle();
    return response;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(yyyymmdd(_cursorDate)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => _cursorDate = _cursorDate.subtract(const Duration(days: 1))),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _cursorDate = _cursorDate.add(const Duration(days: 1))),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _loadDayPlan(_cursorDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('No hay entrenamiento planificado para este día.'));
          }
          final plan = snapshot.data!;
          final dateStr = plan['planned_date'] ?? 'Día sin nombre';
          return ListTile(
            title: Text('Entrenamiento del $dateStr'),
            subtitle: const Text('Toca para ver los ejercicios'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DaySessionScreen(date: _cursorDate, plan: plan)),
            ).then((_) => setState(() {})),
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