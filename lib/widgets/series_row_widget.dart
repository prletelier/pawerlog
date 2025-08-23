// lib/widgets/series_row_widget.dart
import 'package:flutter/material.dart';
import '../utils/models.dart';

/// Un widget que representa una fila para registrar una serie de un ejercicio.
/// Incluye campos para peso, repeticiones, RPE/RIR, un checkbox de completado,
/// y un botón opcional para eliminar la serie.
class SeriesRowWidget extends StatelessWidget {
  final LoggedSet loggedSet;
  final String seriesLabel;
  final String repsHint;
  final String effortHint;
  final VoidCallback onCheckChanged;
  final VoidCallback? onRemove;

  const SeriesRowWidget({
    super.key,
    required this.loggedSet,
    required this.seriesLabel,
    required this.repsHint,
    required this.effortHint,
    required this.onCheckChanged,
    this.onRemove,
  });

  /// Construye el widget de la fila de serie.
  /// Muestra los campos de entrada y maneja la lógica de UI.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(width: 70, child: Text(seriesLabel, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: loggedSet.weightCtrl,
              decoration: const InputDecoration(labelText: 'Peso'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: loggedSet.repsCtrl,
              decoration: InputDecoration(labelText: 'Reps', hintText: repsHint),
              keyboardType: TextInputType.number,
            ),
          ),
          // Solo muestra estos widgets si NO es calentamiento
          if (!loggedSet.isWarmup) ...[
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: loggedSet.rpeCtrl,
                decoration: InputDecoration(labelText: 'RPE/RIR', hintText: effortHint),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
          if (onRemove != null)
            IconButton(
              onPressed: onRemove, // Llama a la función cuando se presiona
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              padding: EdgeInsets.zero,
            ),
          Checkbox(
            value: loggedSet.isCompleted,
            onChanged: (bool? value) {
              onCheckChanged();
            },
          ),
        ],
      ),
    );
  }
}