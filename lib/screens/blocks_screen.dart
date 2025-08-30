// lib/screens/blocks_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

class BlocksScreen extends StatefulWidget {
  const BlocksScreen({super.key});

  @override
  State<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends State<BlocksScreen> {
  final _future = Supabase.instance.client
      .from('blocks')
      .select()
      .order('start_date', ascending: false);

  late final PageController _pageController;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.8) // Cada tarjeta ocupa el 80% del ancho
      ..addListener(_onScroll);
  }

  void _onScroll() {
    setState(() {
      _page = _pageController.page ?? 0;
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final blocks = snapshot.data!;
          if (blocks.isEmpty) {
            return const Center(child: Text('Aún no has generado ningún bloque.'));
          }

          return PageView.builder(
            controller: _pageController,
            itemCount: blocks.length,
            itemBuilder: (context, index) {
              final block = blocks[index];
              // Efecto de perspectiva 3D
              final distortion = (_page - index).abs().clamp(0.0, 1.0);
              final scale = 1.0 - (distortion * 0.1);

              return Transform.scale(
                scale: scale,
                child: Card(
                  elevation: 4.0,
                  margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          block['name'] ?? 'Sin nombre',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Chip(label: Text('${block['days_per_week']} días/semana')),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Inicio: ${block['start_date']}'),
                            Text('Fin: ${block['end_date']}'),
                          ],
                        ),
                      ],
                    ),
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