// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Configuración de Supabase
const supabaseUrl = 'https://zyhtrjgaifgcbkmdxnzr.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5aHRyamdhaWZnY2JrbWR4bnpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ3MDM1NTMsImV4cCI6MjA3MDI3OTU1M30.Lvp5A1620LhsiJ6zBNFVlnLyXLnHRZl5-dEG9QS2ID4';

/// Punto de entrada principal de la aplicación Flutter.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  final client = Supabase.instance.client; // Obtener el cliente Supabase
  if (client.auth.currentSession == null) {
    final res = await client.auth.signInAnonymously();
    if (res.user == null) throw Exception('No se pudo crear usuario anónimo');
  }

  // Asegurar que la fila de usuario existe
  final uid = client.auth.currentUser!.id;
  await client.from('users').upsert({'user_id': uid, 'display_name': 'Pablo'});

  runApp(const PowerlogApp());
}

/// La clase principal de la aplicación Powerlog.
class PowerlogApp extends StatelessWidget {
  const PowerlogApp({super.key});

  /// Construye el widget de la aplicación.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Powerlog',
      // TEMA CLARO (se mantiene por si en el futuro cambiamos la opción)
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6F56B5),
        useMaterial3: true,
        brightness: Brightness.light,
      ),

      // TEMA OSCURO (el que usaremos)
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6F56B5),
        useMaterial3: true,
        brightness: Brightness.dark, // <-- Le decimos que es un tema oscuro
      ),

      // MODO A USAR
      themeMode: ThemeMode.dark, // <-- Forzamos el modo oscuro por defecto

      home: const HomeScreen(),
    );
  }
}