import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/domain/muestra.dart' hide UnidadSangre;
import 'package:hemolink/features/donaciones/domain/donacion.dart';
import 'package:hemolink/features/donaciones/presentation/donacion_detalle_page.dart';
import 'package:hemolink/features/muestras/data/api_muestra_repository.dart';
import 'package:hemolink/features/muestras/data/muestra_repository.dart';

class MockMuestraRepository implements MuestraRepository {
  final List<Muestra> muestrasGuardadas = [];
  Object? errorAlGuardar;
  DatosMuestra? ultimoDatosGuardados;

  @override
  Future<List<Muestra>> buscar({String? donacionId}) async {
    if (donacionId == null || donacionId.isEmpty) {
      return List.unmodifiable(muestrasGuardadas);
    }
    return muestrasGuardadas.where((m) => m.donacionId == donacionId).toList();
  }

  @override
  Future<Muestra?> buscarPorId(String id) async {
    for (final m in muestrasGuardadas) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<Muestra> guardar(DatosMuestra datos) async {
    ultimoDatosGuardados = datos;
    if (errorAlGuardar != null) throw errorAlGuardar!;
    if (muestrasGuardadas.any(
      (m) => m.codigo.toLowerCase() == datos.codigo.toLowerCase(),
    )) {
      throw MuestraApiException(
        409,
        'Ya existe una muestra con ese código.',
      );
    }
    final nueva = Muestra(
      id: 'm-gen-${muestrasGuardadas.length + 1}',
      codigo: datos.codigo,
      donacionId: datos.donacionId,
      donanteId: 'D-DEMO',
      scopeId: 'sede-central',
      responsableId: 'nursing-demo',
      fechaRegistro: DateTime(2026, 11, 8),
    );
    muestrasGuardadas.add(nueva);
    return nueva;
  }
}

Widget crearWidgetPrueba({
  required Donacion donacion,
  required MuestraRepository muestraRepository,
  List<Muestra>? muestrasIniciales,
}) {
  return MaterialApp(
    home: DonacionDetallePage(
      sesion: AuthSession(),
      donacion: donacion,
      muestraRepository: muestraRepository,
      muestrasIniciales: muestrasIniciales,
    ),
  );
}

void main() {
  final donacionBase = Donacion(
    id: 'DON-001',
    donanteId: 'D-001',
    evaluacionId: 'EV-001',
    fechaExtraccion: DateTime(2026, 11, 3),
    volumenMl: 450,
    sedeId: 'sede-central',
    responsableId: 'nursing-demo',
    fechaRegistro: DateTime(2026, 11, 3),
    unidades: [
      UnidadSangre(
        id: 'u-1',
        codigo: 'U-001',
        donacionId: 'DON-001',
        grupoAbo: 'O',
        factorRh: 'positivo',
        sedeId: 'sede-central',
        estado: EstadoUnidad.disponible,
        fechaVencimiento: DateTime(2026, 12, 15),
      ),
    ],
  );

  testWidgets('UT04.2-A: Una donación presenta listas separadas de muestras y unidades', (tester) async {
    final repo = MockMuestraRepository();
    final muestraInicial = Muestra(
      id: 'm-1',
      codigo: 'M-001',
      donacionId: 'DON-001',
      donanteId: 'D-001',
      scopeId: 'sede-central',
      responsableId: 'nursing-demo',
      fechaRegistro: DateTime(2026, 11, 3),
    );

    await tester.pumpWidget(
      crearWidgetPrueba(
        donacion: donacionBase,
        muestraRepository: repo,
        muestrasIniciales: [muestraInicial],
      ),
    );
    await tester.pumpAndSettle();

    // Secciones con títulos diferenciados
    expect(find.text('Unidades de sangre'), findsOneWidget);
    expect(find.text('Muestras'), findsOneWidget);

    // Listas separadas presentadas
    expect(find.text('Unidad: U-001'), findsOneWidget);
    expect(find.text('Muestra: M-001'), findsOneWidget);
  });

  testWidgets('UT04.2-B: Código vacío impide enviar', (tester) async {
    final repo = MockMuestraRepository();
    await tester.pumpWidget(
      crearWidgetPrueba(
        donacion: donacionBase,
        muestraRepository: repo,
        muestrasIniciales: [],
      ),
    );
    await tester.pumpAndSettle();

    // Intentar registrar con campo de texto vacío
    await tester.tap(find.byKey(const Key('registrar-muestra-btn')));
    await tester.pumpAndSettle();

    // Verificar que no se llamó a guardar en el repositorio
    expect(repo.ultimoDatosGuardados, isNull);

    // Señalar el error por dato inválido
    expect(find.text('Ingresa un código de muestra.'), findsOneWidget);
  });
}
