import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/app_user.dart';
import 'package:hemolink/domain/muestra.dart' show Muestra;
import 'package:hemolink/features/aptitud/data/evaluacion_repository.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/donaciones/data/api_donacion_repository.dart';
import 'package:hemolink/features/donaciones/data/donacion_repository.dart';
import 'package:hemolink/features/donaciones/domain/donacion.dart';
import 'package:hemolink/features/donaciones/domain/registro_donaciones.dart';
import 'package:hemolink/features/donaciones/presentation/donacion_detalle_page.dart';
import 'package:hemolink/features/donaciones/presentation/donacion_formulario_page.dart';
import 'package:hemolink/features/donaciones/presentation/donaciones_page.dart';
import 'package:hemolink/features/donaciones/presentation/formulario_donacion_controller.dart';
import 'package:hemolink/features/donantes/data/donante_repository.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/muestras/data/muestra_repository.dart';

import '../donantes/donantes_page_test.dart' show sesionPrueba;

// Reloj de prueba: 04-11-2026. Evaluación apta del 02 al 13 de noviembre.
DateTime reloj() => DateTime(2026, 11, 4);

final donanteO = Donante(
  id: 'D-1',
  rut: '12345678-5',
  nombre: 'Ana Prueba',
  fechaNacimiento: DateTime(1995, 4, 10),
  pesoKg: 65,
  grupoAbo: 'O',
  factorRh: 'positivo',
  telefono: '912345678',
  usuarioRegistroId: 'nursing-demo',
  fechaRegistro: DateTime.utc(2026, 11, 1),
);

final evaluacionApta = EvaluacionAptitud(
  id: 'EV001',
  donanteId: 'D-1',
  resultado: ResultadoAptitud.apto,
  fechaEvaluacion: DateTime(2026, 11, 2),
  fechaFinVigencia: DateTime(2026, 11, 13),
  responsableId: 'nursing-demo',
  fechaRegistro: DateTime.utc(2026, 11, 2),
);

final enfermeria = AppUser(
  id: 'nursing-demo',
  role: UserRole.nursing,
  isVerified: true,
  siteId: 'sede-central',
);

Donacion donacionDe(DatosDonacion d) => Donacion(
  id: 'DON-1',
  donanteId: d.donanteId,
  evaluacionId: d.evaluacionId,
  fechaExtraccion: d.fechaExtraccion,
  volumenMl: d.volumenMl,
  sedeId: 'sede-central',
  responsableId: 'nursing-demo',
  fechaRegistro: DateTime.utc(2026, 11, 4, 12),
  unidades: [
    for (final codigo in d.codigosUnidades)
      UnidadSangre(
        id: 'u-$codigo',
        codigo: codigo,
        donacionId: 'DON-1',
        grupoAbo: 'O',
        factorRh: 'positivo',
        sedeId: 'sede-central',
        estado: EstadoUnidad.disponible,
        fechaVencimiento: calcularVencimiento(d.fechaExtraccion),
      ),
  ],
);

class RepoDonantes implements DonanteRepository {
  List<Donante> lista = [donanteO];

  @override
  Future<List<Donante>> buscar({String? rut, String? nombre}) async => lista;

  @override
  Future<Donante?> buscarPorId(String id) async => null;

  @override
  Future<Donante> guardar(DatosDonante datos) => throw UnimplementedError();

  @override
  Future<Donante> actualizar(String id, DatosDonante datos) =>
      throw UnimplementedError();
}

class RepoEvaluaciones implements EvaluacionRepository {
  Map<String, EvaluacionAptitud> actuales = {'D-1': evaluacionApta};

  @override
  Future<EvaluacionAptitud?> buscarActual(String donanteId) async =>
      actuales[donanteId];

  @override
  Future<EvaluacionAptitud?> buscarPorId(String id) async => null;

  @override
  Future<void> guardar(EvaluacionAptitud evaluacion) =>
      throw UnimplementedError();
}

class RepoDonaciones implements DonacionRepository {
  final enviados = <DatosDonacion>[];
  Future<Donacion> Function(DatosDonacion) responder = (d) async =>
      donacionDe(d);
  List<ResumenDonacion> resumenes = const [];
  Donacion? detalle;

  @override
  Future<Donacion> guardar(DatosDonacion datos) {
    enviados.add(datos);
    return responder(datos);
  }

  @override
  Future<Donacion?> buscarPorId(String id) async => detalle;

  @override
  Future<List<ResumenDonacion>> listar() async => resumenes;
}

class RepoMuestras implements MuestraRepository {
  List<Muestra> lista = [];

  @override
  Future<List<Muestra>> buscar({String? donacionId}) async =>
      lista.where((m) => m.donacionId == donacionId).toList();

  @override
  Future<Muestra?> buscarPorId(String id) async => null;

  @override
  Future<Muestra> guardar(DatosMuestra datos) => throw UnimplementedError();
}

FormularioDonacionController controlador({
  AppUser? usuario,
  RepoDonaciones? donaciones,
  bool sinUsuario = false,
}) => FormularioDonacionController(
  usuario: sinUsuario ? null : (usuario ?? enfermeria),
  donantes: RepoDonantes(),
  evaluaciones: RepoEvaluaciones(),
  registro: RegistroDonaciones(
    repositorio: donaciones ?? RepoDonaciones(),
    reloj: reloj,
  ),
  reloj: reloj,
);

/// Formulario completo y válido: donante apto, 450 mL y una unidad.
Future<void> completar(FormularioDonacionController c) async {
  await c.cargarDonantes();
  await c.seleccionarDonante('D-1');
  c.cambiarVolumen('450');
  c.agregarUnidad('U-001');
}

Future<void> tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> escribir(WidgetTester tester, String key, String valor) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, valor);
  await tester.pumpAndSettle();
}

Future<RepoDonaciones> montarFormulario(
  WidgetTester tester, {
  String? rol = 'nursing',
  RepoDonaciones? donaciones,
}) async {
  final repo = donaciones ?? RepoDonaciones();
  final sesion = await sesionPrueba(tester, rol: rol);
  await tester.pumpWidget(
    MaterialApp(
      home: DonacionFormularioPage(
        sesion: sesion,
        donantes: RepoDonantes(),
        evaluaciones: RepoEvaluaciones(),
        donaciones: repo,
        muestras: RepoMuestras(),
        reloj: reloj,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> llenarFormulario(WidgetTester tester) async {
  await tocar(tester, find.byKey(const Key('donacion-donante')));
  await tester.tap(find.text('Ana Prueba · 12345678-5 · O+').last);
  await tester.pumpAndSettle();
  await escribir(tester, 'donacion-volumen', '450');
  await escribir(tester, 'donacion-codigo-unidad', 'U-001');
  await tocar(tester, find.byKey(const Key('donacion-agregar-unidad')));
}

void main() {
  group('UT03.3-A: no envía sin donante o unidades y muestra los errores', () {
    test('sin donante ni unidades no llama al repositorio', () async {
      final repo = RepoDonaciones();
      final c = controlador(donaciones: repo);
      await c.cargarDonantes();
      c.cambiarVolumen('450');

      expect(await c.confirmar(), isNull);
      expect(repo.enviados, isEmpty);
      expect(c.errores['donanteId'], 'Selecciona un donante.');
      expect(c.errores['unidades'], isNotNull);
    });

    test('con donante pero sin unidades tampoco envía', () async {
      final repo = RepoDonaciones();
      final c = controlador(donaciones: repo);
      await c.cargarDonantes();
      await c.seleccionarDonante('D-1');
      c.cambiarVolumen('450');

      expect(await c.confirmar(), isNull);
      expect(repo.enviados, isEmpty);
      expect(c.errores.keys, contains('unidades'));
      expect(c.errores.keys, isNot(contains('donanteId')));
    });

    test('código de unidad vacío o repetido no se agrega', () async {
      final c = controlador();
      expect(c.agregarUnidad('  '), isFalse);
      expect(c.agregarUnidad('U-001'), isTrue);
      expect(c.agregarUnidad('u-001'), isFalse);
      expect(c.codigos, ['U-001']);
      expect(c.errores['unidades'], contains('ya está en la lista'));
    });

    test('los errores recibidos del servidor se muestran', () async {
      final repo = RepoDonaciones()
        ..responder = (_) async => throw DonacionApiException(
          409,
          'El código de unidad U-001 ya existe.',
          errores: {'unidades': 'Código repetido.'},
        );
      final c = controlador(donaciones: repo);
      await completar(c);

      expect(await c.confirmar(), isNull);
      expect(c.errorGeneral, 'El código de unidad U-001 ya existe.');
      expect(c.errores['unidades'], 'Código repetido.');
    });

    testWidgets('GUI: confirmar vacío marca donante y unidades sin enviar', (
      tester,
    ) async {
      final repo = await montarFormulario(tester);
      await tocar(tester, find.byKey(const Key('donacion-confirmar')));

      expect(repo.enviados, isEmpty);
      expect(find.text('Selecciona un donante.'), findsOneWidget);
      expect(find.text('Agrega al menos una unidad.'), findsOneWidget);
      expect(find.text('Registrar donación'), findsOneWidget);
    });
  });

  group('UT03.3-B: el vencimiento se calcula y no se ingresa', () {
    test('cambia con la fecha de extracción (02-11 vence 14-12)', () {
      final c = controlador();
      expect(c.vencimiento, DateTime.utc(2026, 12, 16)); // hoy 04-11
      c.cambiarFecha(DateTime(2026, 11, 2));
      expect(c.vencimiento, DateTime.utc(2026, 12, 14));
    });

    testWidgets('GUI: se muestra como texto; solo volumen y código son editables', (
      tester,
    ) async {
      await montarFormulario(tester);

      final vencimiento = tester.widget<Text>(
        find.byKey(const Key('donacion-vencimiento')),
      );
      expect(vencimiento.data, '16/12/2026');
      final sede = tester.widget<Text>(find.byKey(const Key('donacion-sede')));
      expect(sede.data, 'sede-central');
      // Los únicos campos de texto son volumen y código de unidad.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byKey(const Key('donacion-volumen')), findsOneWidget);
      expect(find.byKey(const Key('donacion-codigo-unidad')), findsOneWidget);
    });
  });

  group('UT03.3-C: un fallo no muestra éxito y conserva lo escrito', () {
    test('lógica: conserva datos y reintenta con la misma clave', () async {
      var falla = true;
      final repo = RepoDonaciones()
        ..responder = (d) async {
          if (falla) {
            throw DonacionApiException(
              null,
              'No fue posible conectar con el servidor.',
            );
          }
          return donacionDe(d);
        };
      final c = controlador(donaciones: repo);
      await completar(c);

      expect(await c.confirmar(), isNull);
      expect(c.errorGeneral, 'No fue posible conectar con el servidor.');
      expect(c.donante?.id, 'D-1');
      expect(c.volumen, '450');
      expect(c.codigos, ['U-001']);
      expect(c.guardando, isFalse);

      falla = false;
      final donacion = await c.confirmar();
      expect(donacion?.id, 'DON-1');
      expect(repo.enviados, hasLength(2));
      expect(
        repo.enviados.last.claveConfirmacion,
        repo.enviados.first.claveConfirmacion,
        reason: 'el reintento debe reutilizar la clave (T03.2)',
      );
    });

    testWidgets('GUI: el fallo deja el formulario; luego el éxito abre el detalle', (
      tester,
    ) async {
      var falla = true;
      final repo = RepoDonaciones()
        ..responder = (d) async {
          if (falla) {
            throw DonacionApiException(
              null,
              'No fue posible conectar con el servidor.',
            );
          }
          return donacionDe(d);
        };
      await montarFormulario(tester, donaciones: repo);
      await llenarFormulario(tester);
      expect(
        find.textContaining('Puede donar en la fecha elegida.'),
        findsOneWidget,
      );

      await tocar(tester, find.byKey(const Key('donacion-confirmar')));
      expect(
        find.text('No fue posible conectar con el servidor.'),
        findsOneWidget,
      );
      expect(find.text('Donación registrada correctamente.'), findsNothing);
      expect(find.text('Registrar donación'), findsOneWidget);
      final volumen = tester.widget<TextField>(
        find.byKey(const Key('donacion-volumen')),
      );
      expect(volumen.controller?.text, '450');
      expect(find.byKey(const Key('unidad-U-001')), findsOneWidget);

      falla = false;
      await tocar(tester, find.byKey(const Key('donacion-confirmar')));
      expect(find.text('Detalle de donación DON-1'), findsOneWidget);
      expect(find.text('Unidad: U-001'), findsOneWidget);
      expect(repo.enviados.last.volumenMl, 450);
      expect(repo.enviados.last.codigosUnidades, ['U-001']);
    });
  });

  testWidgets('UT03.3-D: el detalle presenta vínculos y colecciones separadas', (
    tester,
  ) async {
    final sesion = await sesionPrueba(tester);
    final donacion = donacionDe(
      DatosDonacion(
        claveConfirmacion: 'clave-de-prueba-0001',
        donanteId: 'D-1',
        evaluacionId: 'EV001',
        fechaExtraccion: DateTime(2026, 11, 3),
        volumenMl: 450,
        codigosUnidades: ['U-001'],
      ),
    );
    final muestra = Muestra(
      id: 'm-1',
      codigo: 'M-001',
      donacionId: 'DON-1',
      responsableId: 'nursing-demo',
      fechaRegistro: DateTime(2026, 11, 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DonacionDetallePage(
          sesion: sesion,
          donacion: donacion,
          muestraRepository: RepoMuestras(),
          muestrasIniciales: [muestra],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Donante ID: D-1'), findsOneWidget);
    expect(find.text('Evaluación utilizada: EV001'), findsOneWidget);
    expect(find.text('Sede: sede-central'), findsOneWidget);
    expect(find.text('Responsable: nursing-demo'), findsOneWidget);
    expect(find.text('Unidades de sangre'), findsOneWidget);
    expect(find.text('Muestras'), findsOneWidget);
    expect(find.text('Unidad: U-001'), findsOneWidget);
    expect(find.text('Muestra: M-001'), findsOneWidget);
    // La muestra no se presenta como unidad ni al revés.
    expect(find.text('Unidad: M-001'), findsNothing);
    expect(find.text('Muestra: U-001'), findsNothing);
    expect(find.textContaining('Vence: 15/12/2026'), findsOneWidget);
  });

  group('UT03.3-E: sin sesión o con rol ajeno se rechaza', () {
    test('sin usuario o con inventario no llama al repositorio', () async {
      for (final c in [
        controlador(sinUsuario: true),
        controlador(
          usuario: AppUser(
            id: 'inventory-demo',
            role: UserRole.inventory,
            isVerified: true,
            siteId: 'sede-central',
          ),
        ),
      ]) {
        final repo = c.registro.repositorio as RepoDonaciones;
        await completar(c);
        expect(await c.confirmar(), isNull);
        expect(repo.enviados, isEmpty);
        expect(c.errorGeneral, 'Tu perfil no puede registrar donaciones.');
      }
    });

    test('el rechazo del servicio (403) se informa sin mostrar éxito', () async {
      final repo = RepoDonaciones()
        ..responder = (_) async => throw DonacionApiException(
          403,
          'Tu perfil no puede gestionar donaciones.',
        );
      final c = controlador(donaciones: repo);
      await completar(c);
      expect(await c.confirmar(), isNull);
      expect(c.errorGeneral, 'Tu perfil no puede gestionar donaciones.');
    });

    testWidgets('GUI: con inventario el botón confirmar queda deshabilitado', (
      tester,
    ) async {
      await montarFormulario(tester, rol: 'inventory');
      expect(
        find.text('Tu perfil no puede registrar donaciones.'),
        findsOneWidget,
      );
      final boton = tester.widget<FilledButton>(
        find.byKey(const Key('donacion-confirmar')),
      );
      expect(boton.onPressed, isNull);
    });
  });

  testWidgets('T03.3: el listado abre el detalle de la donación elegida', (
    tester,
  ) async {
    final sesion = await sesionPrueba(tester);
    final repo = RepoDonaciones()
      ..resumenes = [
        ResumenDonacion(
          id: 'DON-1',
          donanteId: 'D-1',
          fechaExtraccion: DateTime(2026, 11, 3),
          volumenMl: 450,
        ),
      ]
      ..detalle = donacionDe(
        DatosDonacion(
          claveConfirmacion: 'clave-de-prueba-0001',
          donanteId: 'D-1',
          evaluacionId: 'EV001',
          fechaExtraccion: DateTime(2026, 11, 3),
          volumenMl: 450,
          codigosUnidades: ['U-001'],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: DonacionesPage(
          sesion: sesion,
          donaciones: repo,
          donantes: RepoDonantes(),
          evaluaciones: RepoEvaluaciones(),
          muestras: RepoMuestras(),
          reloj: reloj,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Extracción 03/11/2026 · 450 mL'), findsOneWidget);
    await tocar(tester, find.byKey(const Key('donacion-DON-1')));
    expect(find.text('Detalle de donación DON-1'), findsOneWidget);
    expect(find.text('Evaluación utilizada: EV001'), findsOneWidget);
  });
}