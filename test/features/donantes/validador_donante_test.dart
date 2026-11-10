import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/donantes/domain/validador_donante.dart';

void main() {
  final hoy = DateTime(2026, 11, 8, 10);
  final registro = DateTime.utc(2026, 11, 8, 13);
  const validador = ValidadorDonante();

  DatosDonante datos({
    String? rut = '12.345.678-5',
    String? nombre = 'María Soto',
    DateTime? fechaNacimiento,
    bool sinNacimiento = false,
    double? pesoKg = 65.5,
    String? grupoAbo = 'O',
    String? factorRh = 'positivo',
    String? telefono = '+56 9 1234 5678',
  }) => DatosDonante(
    rut: rut,
    nombre: nombre,
    fechaNacimiento: sinNacimiento
        ? null
        : fechaNacimiento ?? DateTime(1998, 3, 12),
    pesoKg: pesoKg,
    grupoAbo: grupoAbo,
    factorRh: factorRh,
    telefono: telefono,
  );

  Donante validar(
    DatosDonante entrada, {
    String id = 'DON001',
    String usuarioRegistroId = 'ENF001',
  }) => validador.validar(
    entrada,
    id: id,
    usuarioRegistroId: usuarioRegistroId,
    fechaRegistro: registro,
    fechaActual: hoy,
  );

  Matcher errorDeCampo(String campo) => throwsA(
    isA<ValidacionDonanteException>().having(
      (error) => error.errores,
      'errores por campo',
      contains(campo),
    ),
  );

  group('T01.2 - Modelo y UT01.2-B: datos del donante', () {
    test('conserva antecedentes e identificadores de registro', () {
      final donante = validar(datos());

      expect(donante.id, 'DON001');
      expect(donante.rut, '12345678-5');
      expect(donante.nombre, 'María Soto');
      expect(donante.fechaNacimiento, DateTime(1998, 3, 12));
      expect(donante.pesoKg, 65.5);
      expect(donante.grupoAbo, 'O');
      expect(donante.factorRh, 'positivo');
      expect(donante.telefono, '+56 9 1234 5678');
      expect(donante.usuarioRegistroId, 'ENF001');
      expect(donante.fechaRegistro, registro);
    });

    test('normaliza los campos sin perder acentos ni datos de contacto', () {
      final donante = validar(
        datos(
          rut: ' 6.000.000-k ',
          nombre: ' María Soto ',
          grupoAbo: ' ab ',
          factorRh: ' NEGATIVO ',
          telefono: ' +56 9 1234 5678 ',
        ),
      );

      expect(donante.rut, '6000000-K');
      expect(donante.nombre, 'María Soto');
      expect(donante.grupoAbo, 'AB');
      expect(donante.factorRh, 'negativo');
      expect(donante.telefono, '+56 9 1234 5678');
    });

    for (final grupo in ['A', 'B', 'AB', 'O']) {
      for (final rh in ['positivo', 'negativo']) {
        test('acepta grupo $grupo con Rh $rh', () {
          final donante = validar(datos(grupoAbo: grupo, factorRh: rh));
          expect(donante.grupoAbo, grupo);
          expect(donante.factorRh, rh);
        });
      }
    }

    final invalidos = <String, List<DatosDonante>>{
      'rut': [datos(rut: null), datos(rut: ' '), datos(rut: '12.345.678-4')],
      'nombre': [datos(nombre: null), datos(nombre: ' ')],
      'fechaNacimiento': [
        datos(sinNacimiento: true),
        datos(fechaNacimiento: DateTime(2026, 11, 9)),
      ],
      'pesoKg': [
        datos(pesoKg: null),
        datos(pesoKg: 0),
        datos(pesoKg: -1),
        datos(pesoKg: double.nan),
        datos(pesoKg: double.infinity),
        datos(pesoKg: double.negativeInfinity),
      ],
      'grupoAbo': [
        datos(grupoAbo: null),
        datos(grupoAbo: ' '),
        datos(grupoAbo: 'C'),
      ],
      'factorRh': [
        datos(factorRh: null),
        datos(factorRh: ' '),
        datos(factorRh: 'desconocido'),
      ],
      'telefono': [datos(telefono: null), datos(telefono: ' ')],
    };

    for (final campo in invalidos.entries) {
      for (var i = 0; i < campo.value.length; i++) {
        test('rechaza ${campo.key} obligatorio o inválido ($i)', () {
          expect(() => validar(campo.value[i]), errorDeCampo(campo.key));
        });
      }
    }

    test('informa todos los campos ausentes en una sola validación', () {
      expect(
        () => validar(const DatosDonante()),
        throwsA(
          isA<ValidacionDonanteException>().having(
            (error) => error.errores.keys,
            'campos obligatorios',
            unorderedEquals([
              'rut',
              'nombre',
              'fechaNacimiento',
              'pesoKg',
              'grupoAbo',
              'factorRh',
              'telefono',
            ]),
          ),
        ),
      );
    });

    test('acepta nacimiento hoy sin comparar la hora', () {
      final nacimiento = DateTime(2026, 11, 8, 23, 59);
      expect(
        validar(datos(fechaNacimiento: nacimiento)).fechaNacimiento,
        DateTime(2026, 11, 8),
      );
    });

    test('compara nacimiento UTC por su fecha de calendario', () {
      final nacimiento = DateTime.utc(2026, 11, 8, 23, 59);
      expect(
        validar(datos(fechaNacimiento: nacimiento)).fechaNacimiento,
        DateTime(2026, 11, 8),
      );
    });

    test('no añade límites de edad o peso clínicos fuera de HU01', () {
      expect(
        validar(datos(fechaNacimiento: DateTime(2026, 11, 8), pesoKg: 0.1))
            .pesoKg,
        0.1,
      );
    });

    test('exige identificador y usuario de registro', () {
      expect(() => validar(datos(), id: ' '), errorDeCampo('id'));
      expect(
        () => validar(datos(), usuarioRegistroId: ' '),
        errorDeCampo('usuarioRegistroId'),
      );
    });

    test('los errores por campo no se pueden modificar', () {
      try {
        validar(const DatosDonante());
        fail('Debió rechazar los datos incompletos.');
      } on ValidacionDonanteException catch (error) {
        expect(() => error.errores.clear(), throwsUnsupportedError);
      }
    });
  });
}
