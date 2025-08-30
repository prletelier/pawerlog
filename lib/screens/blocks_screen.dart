import 'package:flutter/material.dart';

class BlocksScreen extends StatelessWidget {
  const BlocksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bloques'),
      ),
      body: const Center(
        child: Text('Vista de Bloques - Próximamente'),
      ),
    );
  }
}