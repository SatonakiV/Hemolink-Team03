import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/donantes/domain/validador_rut.dart';

void main() {
  group('T01.2 - UT01.2-A: RUT', () {
    test('normaliza variantes al mismo RUT', () {
      for (final rut in [
        '12.345.678-5',
        '12345678-5',
        '123456785',
        ' 12.345.678 - 5 ',
      ]) {
        expect(ValidadorRut.normalizar(rut), '12345678-5');
        expect(ValidadorRut.esValido(rut), isTrue);
      }
    });

    test('acepta K minúscula y la convierte a mayúscula', () {
      expect(ValidadorRut.normalizar(' 6.000.000-k '), '6000000-K');
      expect(ValidadorRut.esValido('6.000.000-k'), isTrue);
    });

    test('acepta dígito verificador cero', () {
      expect(ValidadorRut.esValido('10.000.004-0'), isTrue);
    });

    test('normaliza ceros iniciales sin crear otra identidad', () {
      expect(ValidadorRut.normalizar('06.000.000-k'), '6000000-K');
      expect(ValidadorRut.esValido('06.000.000-k'), isTrue);
    });

    for (final rut in ['12.345.678-4', '6.000.000-0', '10.000.004-K']) {
      test('rechaza dígito verificador incorrecto: $rut', () {
        expect(ValidadorRut.esValido(rut), isFalse);
      });
    }

    for (final rut in [
      '',
      '   ',
      '12345678',
      '123456789-0',
      '12A45678-5',
      '12345678-X',
      '12345678--5',
      '-123456785',
      '12345678-5 extra',
      '0-0',
      '00000000-0',
    ]) {
      test('rechaza RUT vacío o mal formado: "$rut"', () {
        expect(ValidadorRut.esValido(rut), isFalse);
      });
    }

    test('normalizar informa un formato ilegible', () {
      expect(() => ValidadorRut.normalizar('sin RUT'), throwsFormatException);
    });
  });
}
