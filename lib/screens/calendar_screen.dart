// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../utils/helpers.dart';
import 'home_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final supa = Supabase.instance.client;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<dynamic>> _events = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadMonthPlans(_focusedDay);
  }

  Future<void> _loadMonthPlans(DateTime month) async {
    if (mounted) setState(() => _isLoading = true);
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);

    final response = await supa
        .from('plan_items')
        .select('*, blocks(*)')
        .eq('user_id', supa.auth.currentUser!.id)
        .gte('planned_date', yyyymmdd(firstDayOfMonth))
        .lte('planned_date', yyyymmdd(lastDayOfMonth));

    final Map<DateTime, List<dynamic>> events = {};
    for (var plan in response) {
      final date = DateTime.parse(plan['planned_date']);
      final dayWithoutTime = DateTime(date.year, date.month, date.day);
      events[dayWithoutTime] = [plan];
    }

    if(mounted) setState(() {
      _events = events;
      _isLoading = false;
    });
  }

  List<dynamic> _getEventsForDay(DateTime day) {
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
          if(_isLoading) const LinearProgressIndicator(),
          TableCalendar(
            locale: 'es_ES',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            calendarStyle: CalendarStyle(
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

              final events = _getEventsForDay(selectedDay);
              if (events.isNotEmpty) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => HomeScreen(initialDate: selectedDay)),
                      (route) => route.isFirst,
                );
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
              _loadMonthPlans(focusedDay);
            },
          ),
        ],
      ),
    );
  }
}