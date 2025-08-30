// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../utils/helpers.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final supa = Supabase.instance.client;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Mapa para guardar los eventos (planes) cargados
  Map<DateTime, List<dynamic>> _events = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadMonthPlans(_focusedDay);
  }

  /// Carga todos los planes de entrenamiento para un mes específico.
  Future<void> _loadMonthPlans(DateTime month) async {
    setState(() => _isLoading = true);

    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);

    final response = await supa
        .from('plan_items')
        .select('planned_date, prescription')
        .eq('user_id', supa.auth.currentUser!.id)
        .gte('planned_date', yyyymmdd(firstDayOfMonth))
        .lte('planned_date', yyyymmdd(lastDayOfMonth));

    final Map<DateTime, List<dynamic>> events = {};
    for (var plan in response) {
      final date = DateTime.parse(plan['planned_date']);
      events[date] = [plan]; // Guardamos el plan como un evento
    }

    setState(() {
      _events = events;
      _isLoading = false;
    });
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    // Función requerida por table_calendar para obtener los eventos de un día
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario de Entrenamiento'),
      ),
      body: Column(
        children: [
          TableCalendar(
            locale: 'es_ES',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            calendarStyle: CalendarStyle(
              // Estilo para los marcadores de eventos
              markerDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
              _loadMonthPlans(focusedDay); // Carga los planes del nuevo mes
            },
          ),
          const Divider(height: 1.0),
          // Lista de ejercicios para el día seleccionado
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildEventList(),
          ),
        ],
      ),
    );
  }

  /// Construye la lista de ejercicios para el día seleccionado.
  Widget _buildEventList() {
    final selectedEvents = _getEventsForDay(_selectedDay!);
    if (selectedEvents.isEmpty) {
      return const Center(child: Text('No hay entrenamiento para este día.'));
    }

    final plan = selectedEvents.first;
    final exercises = plan['prescription']?['exercises'] as List? ?? [];

    return ListView.builder(
      itemCount: exercises.length,
      itemBuilder: (context, index) {
        final exerciseData = exercises[index] as Map<String, dynamic>;

        String title = exerciseData['movement'] ?? 'Ejercicio';
        final variants = exerciseData['variants'] as List? ?? [];
        if (variants.isNotEmpty) {
          title += ' - ${variants.join(' ')}';
        }

        final prescriptions = exerciseData['prescriptions'] as List? ?? [];
        final summary = buildAdvancedPrescriptionSummary(prescriptions);

        return ListTile(
          title: Text(title),
          subtitle: Text(summary),
        );
      },
    );
  }
}