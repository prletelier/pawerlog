// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';

const supabaseUrl = 'https://zyhtrjgaifgcbkmdxnzr.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5aHRyamdhaWZnY2JrbWR4bnpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ3MDM1NTMsImV4cCI6MjA3MDI3OTU1M30.Lvp5A1620LhsiJ6zBNFVlnLyXLnHRZl5-dEG9QS2ID4';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  final client = Supabase.instance.client;
  if (client.auth.currentSession == null) {
    final res = await client.auth.signInAnonymously();
    if (res.user == null) throw Exception('No se pudo crear usuario anónimo');
  }

  // Asegurar que la fila de usuario existe
  final uid = client.auth.currentUser!.id;
  await client.from('users').upsert({'user_id': uid, 'display_name': 'Pablo'});

  runApp(const PowerlogApp());
}

class PowerlogApp extends StatelessWidget {
  const PowerlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Powerlog',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6F56B5),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}