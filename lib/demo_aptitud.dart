import 'package:flutter/material.dart';
import 'features/aptitud/domain/evaluacion_aptitud.dart';
import 'features/aptitud/presentation/evaluacion_aptitud_page.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HemoLink - Evaluaciones',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B2743),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F6),
        useMaterial3: true,
      ),
      home: EvaluacionAptitudPage(
        // Donante y enfermero ficticios.
        donanteId: 'D001',
        responsableId: 'ENF001',

        // Simula un guardado exitoso.
        // Todavía no modifica el JSON del servidor.
        onGuardar: (evaluacion) async {
          await Future<void>.delayed(
            const Duration(milliseconds: 300),
          );
        },

        // Evaluaciones ficticias para probar el historial.
        historialInicial: [
          EvaluacionAptitud(
            id: 'EV001',
            donanteId: 'D001',
            responsableId: 'ENF001',
            resultado: ResultadoAptitud.apto,
            fechaEvaluacion: DateTime(2026, 11, 2),
            fechaFinVigencia: DateTime(2026, 11, 20),
            fechaRegistro: DateTime(2026, 11, 2),
          ),
          EvaluacionAptitud(
            id: 'EV002',
            donanteId: 'D001',
            responsableId: 'ENF001',
            resultado: ResultadoAptitud.diferido,
            fechaEvaluacion: DateTime(2026, 11, 8),
            fechaHabilitacion: DateTime(2026, 11, 15),
            fechaRegistro: DateTime(2026, 11, 8),
          ),
        ],
      ),
    ),
  );
}
