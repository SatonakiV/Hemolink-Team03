/// Normalización y módulo 11 compartidos por el registro y la edición.
abstract final class ValidadorRut {
  static final _formato = RegExp(r'^([0-9]{1,8})-?([0-9K])$');

  /// Devuelve cuerpo-DV sin puntos, espacios ni ceros iniciales, con K mayúscula.
  /// Normalizar no comprueba el dígito verificador; usar [esValido] para ello.
  static String normalizar(String rut) {
    final compacto = rut.replaceAll(RegExp(r'[.\s]'), '').toUpperCase();
    final partes = _formato.firstMatch(compacto);
    if (partes == null) throw const FormatException('Formato de RUT inválido.');

    final cuerpo = int.parse(partes.group(1)!);
    if (cuerpo == 0) {
      throw const FormatException('El RUT debe ser distinto de cero.');
    }
    return '$cuerpo-${partes.group(2)}';
  }

  static bool esValido(String rut) {
    final String normalizado;
    try {
      normalizado = normalizar(rut);
    } on FormatException {
      return false;
    }

    final partes = normalizado.split('-');
    final cuerpo = partes[0];
    var suma = 0;
    var factor = 2;
    for (var i = cuerpo.length - 1; i >= 0; i--) {
      suma += int.parse(cuerpo[i]) * factor;
      factor = factor == 7 ? 2 : factor + 1;
    }
    final resultado = 11 - suma % 11;
    final esperado = switch (resultado) {
      11 => '0',
      10 => 'K',
      _ => '$resultado',
    };
    return partes[1] == esperado;
  }
}
