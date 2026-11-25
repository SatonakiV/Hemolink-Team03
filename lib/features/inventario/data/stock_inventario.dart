import '../../../core/access/auth_session.dart';

class UnidadStock {
  UnidadStock.fromJson(Map<String, dynamic> json)
    : id = json['id'] is String ? json['id'] as String : '',
      codigo = json['codigo'] as String,
      sedeId = json['sedeId'] as String,
      grupoAbo = json['grupoAbo'] as String,
      factorRh = json['factorRh'] as String,
      vencimiento = DateTime.parse(
        json['fechaVencimiento'] as String,
      );

  final String id;
  final String codigo;
  final String sedeId;
  final String grupoAbo;
  final String factorRh;
  final DateTime vencimiento;

  bool get tieneIdentificador => id.isNotEmpty;

  String get grupo =>
      '$grupoAbo${factorRh == 'positivo' ? '+' : '-'}';
}

class StockInventario {
  const StockInventario._(this.unidades, this.total);

  final List<UnidadStock> unidades;
  final int total;

  static Future<StockInventario> consultar(
    AuthSession sesion, {
    required String sedeId,
    required String grupoAbo,
    required String factorRh,
  }) async {
    final filtros = {
      if (sedeId.isNotEmpty) 'sedeId': sedeId,
      if (grupoAbo.isNotEmpty) 'grupoAbo': grupoAbo,
      if (factorRh.isNotEmpty) 'factorRh': factorRh,
    };

    final datos = await sesion.loadModuleData(
      'inventory',
      queryParameters: filtros.isEmpty ? null : filtros,
    );

    final itemsJson = datos['items'];

    if (itemsJson is! List) {
      throw const FormatException('Respuesta de stock inválida');
    }

    final unidades = itemsJson
        .cast<Map<String, dynamic>>()
        .map(UnidadStock.fromJson)
        .toList();

    final total = datos['total'] is int
        ? datos['total'] as int
        : unidades.length;

    return StockInventario._(unidades, total);
  }
}
