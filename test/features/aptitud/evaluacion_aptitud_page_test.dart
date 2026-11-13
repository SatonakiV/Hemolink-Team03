import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/presentation/evaluacion_aptitud_page.dart';

void main() {
  // Construye la pantalla usando datos ficticios.
  Widget crearPantalla({
    Future<void> Function(EvaluacionAptitud)? onGuardar,
  }) {
    return MaterialApp(
      home: EvaluacionAptitudPage(
        donanteId: 'D001',
        responsableId: 'ENF001',
        onGuardar: onGuardar ?? (_) async {},
      ),
    );
  }

  // Selecciona un resultado desde el desplegable.
  Future<void> seleccionarResultado(
    WidgetTester tester,
    String actual,
    String nuevo,
  ) async {
    await tester.tap(find.text(actual).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(nuevo).last);
    await tester.pumpAndSettle();
  }

  // Selecciona la fecha inicial del calendario.
  Future<void> seleccionarFechaEvaluacion(
    WidgetTester tester,
  ) async {
    await tester.tap(
      find.byKey(const Key('fecha-evaluacion')),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  // UT1: campos dinámicos.
  testWidgets('UT1: muestra campos según el resultado', (
    tester,
  ) async {
    await tester.pumpWidget(crearPantalla());

    // Apto requiere fecha de fin de vigencia.
    expect(
      find.text('Seleccionar fin de vigencia'),
      findsOneWidget,
    );

    // Diferido requiere fecha de reevaluación.
    await seleccionarResultado(
      tester,
      'Apto',
      'Diferido',
    );

    expect(
      find.text('Seleccionar fecha de reevaluación'),
      findsOneWidget,
    );

    // Rechazado no requiere una fecha adicional.
    await seleccionarResultado(
      tester,
      'Diferido',
      'Rechazado permanentemente',
    );

    expect(
      find.byKey(const Key('fecha-limite')),
      findsNothing,
    );
  });

  // UT2: validación de campos obligatorios.
  testWidgets('UT2: impide formularios incompletos', (
    tester,
  ) async {
    var guardados = 0;

    await tester.pumpWidget(
      crearPantalla(
        onGuardar: (_) async {
          guardados++;
        },
      ),
    );

    // Intento de guardado sin fecha de evaluación.
    await tester.tap(find.text('Guardar evaluación'));
    await tester.pumpAndSettle();

    expect(
      find.text('Selecciona la fecha de evaluación.'),
      findsOneWidget,
    );

    expect(guardados, 0);

    // Se indica la fecha inicial, pero falta la vigencia.
    await seleccionarFechaEvaluacion(tester);

    await tester.tap(find.text('Guardar evaluación'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Completa la fecha correspondiente al resultado.',
      ),
      findsOneWidget,
    );

    expect(guardados, 0);
  });

  // UT3: confirmación y actualización del historial.
  testWidgets('UT3: muestra confirmación al guardar', (
    tester,
  ) async {
    EvaluacionAptitud? guardada;

    await tester.pumpWidget(
      crearPantalla(
        onGuardar: (evaluacion) async {
          guardada = evaluacion;
        },
      ),
    );

    // Rechazado solamente requiere fecha de evaluación.
    await seleccionarResultado(
      tester,
      'Apto',
      'Rechazado permanentemente',
    );

    await seleccionarFechaEvaluacion(tester);

    await tester.tap(find.text('Guardar evaluación'));
    await tester.pumpAndSettle();

    // Verificar que se ejecutó el guardado.
    expect(guardada, isNotNull);
    expect(guardada!.donanteId, 'D001');

    expect(
      guardada!.resultado,
      ResultadoAptitud.rechazado,
    );

    // Verificar el mensaje de confirmación.
    expect(
      find.text('Evaluación registrada correctamente.'),
      findsOneWidget,
    );

    // Desplazar la pantalla hasta el historial.
    await tester.drag(
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    // Identificar la evaluación recién registrada.
    final fila = find.byKey(
      Key('evaluacion-${guardada!.id}'),
    );

    expect(fila, findsOneWidget);

    // Comprobar que el historial muestra el resultado.
    expect(
      find.descendant(
        of: fila,
        matching: find.text('Rechazado permanentemente'),
      ),
      findsOneWidget,
    );
  });

  // UT3: manejar errores sin alterar el historial.
  testWidgets('UT3: muestra error si falla el guardado', (
    tester,
  ) async {
    await tester.pumpWidget(
      crearPantalla(
        onGuardar: (_) async {
          throw StateError('Fallo simulado');
        },
      ),
    );

    await seleccionarResultado(
      tester,
      'Apto',
      'Rechazado permanentemente',
    );

    await seleccionarFechaEvaluacion(tester);

    await tester.tap(find.text('Guardar evaluación'));
    await tester.pumpAndSettle();

    // Debe mostrarse un mensaje de error.
    expect(
      find.text(
        'No fue posible guardar la evaluación. Intenta nuevamente.',
      ),
      findsOneWidget,
    );

    // El historial debe seguir vacío.
    expect(
      find.text(
        'Este donante no tiene evaluaciones registradas.',
      ),
      findsOneWidget,
    );
  });
}
