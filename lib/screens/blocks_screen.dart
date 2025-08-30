// lib/screens/blocks_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../utils/helpers.dart';
import 'day_session_screen.dart';
import 'home_screen.dart';

class BlocksScreen extends StatefulWidget {
  const BlocksScreen({super.key});

  @override
  State<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends State<BlocksScreen> {
  final _future = Supabase.instance.client
      .from('blocks')
      .select('*, plan_items(*, blocks(*))')
      .order('start_date', ascending: true);

  PageController? _pageController;
  double _page = 0;

  @override
  void dispose() {
    _pageController?.removeListener(_onScroll);
    _pageController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (mounted && _pageController!.hasClients) {
      setState(() {
        _page = _pageController!.page ?? 0;
      });
    }
  }

  void _navigateToDay(BuildContext context, DateTime targetDate, Map<String, dynamic> plan) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeScreen(initialDate: targetDate)),
          (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bloques de Entrenamiento'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Aún no has generado ningún bloque.'));
          }
          final blocks = snapshot.data!;
          final today = DateTime.now();

          int initialPage = blocks.indexWhere((block) {
            final startDate = DateTime.parse(block['start_date']);
            final endDate = DateTime.parse(block['end_date']);
            return today.isAfter(startDate.subtract(const Duration(days: 1))) &&
                today.isBefore(endDate.add(const Duration(days: 1)));
          });
          if (initialPage == -1) initialPage = 0;

          if (_pageController == null) {
            _pageController = PageController(
              initialPage: initialPage,
              viewportFraction: 0.85,
            )..addListener(_onScroll);
            _page = initialPage.toDouble();
          }

          return PageView.builder(
            controller: _pageController,
            itemCount: blocks.length,
            itemBuilder: (context, index) {
              final block = blocks[index];
              final distortion = (_page - index).abs().clamp(0.0, 1.0);
              final scale = 1.0 - (distortion * 0.1);

              final planItems = block['plan_items'] as List<dynamic>? ?? [];
              final Map<int, Map<String, dynamic>> dayTemplates = {};
              for (final item in planItems) {
                final date = DateTime.parse(item['planned_date']);
                if (!dayTemplates.containsKey(date.weekday)) {
                  dayTemplates[date.weekday] = item;
                }
              }
              final sortedDayTemplates = dayTemplates.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));

              return Transform.scale(
                scale: scale,
                child: Card(
                  elevation: 4.0,
                  margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                  child: ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      Text(block['name'] ?? 'Sin nombre', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text('Inicio: ${block['start_date']} | Fin: ${block['end_date']}'),
                      const Divider(height: 24),

                      ...sortedDayTemplates.map((entry) {
                        final dayOfWeek = entry.key;
                        final plan = entry.value;
                        final exercises = plan['prescription']?['exercises'] as List? ?? [];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${DateFormat('EEEE', 'es').format(findNextWeekday(DateTime.now(), dayOfWeek))} (Día ${sortedDayTemplates.indexOf(entry) + 1})'),
                              trailing: const Icon(Icons.arrow_forward),
                              onTap: () {
                                final targetDate = findNextWeekday(DateTime.now(), dayOfWeek);
                                _navigateToDay(context, targetDate, plan);
                              },
                            ),
                            ...exercises.map((exData) {
                              final title = '${exData['movement'] ?? ''} - ${ (exData['variants'] as List? ?? []).join(' ')}';
                              final summary = buildAdvancedPrescriptionSummary(exData['prescriptions'] ?? []);
                              return Padding(
                                padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
                                child: Text("• $title: $summary", style: Theme.of(context).textTheme.bodySmall),
                              );
                            }).toList(),
                            const SizedBox(height: 12),
                          ],
                        );
                      })
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}