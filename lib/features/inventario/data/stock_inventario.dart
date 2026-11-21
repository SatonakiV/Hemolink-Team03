import '../../../core/access/auth_session.dart';

class UnidadStock {
  UnidadStock.fromJson(Map<String, dynamic> json)
    : codigo = json['codigo'] as String,
      sedeId = json['sedeId'] as String,
      grupoAbo = json['grupoAbo'] as String,
      factorRh = json['factorRh'] as String,
      vencimiento = DateTime.parse(json['fechaVencimiento'] as String);

  final String codigo;
  final String sedeId;
  final String grupoAbo;
  final String factorRh;
  final DateTime vencimiento;

  String get grupo => '$grupoAbo${factorRh == 'positivo' ? '+' : '-'}';
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
    if (datos
        case {'items': final List<dynamic> items, 'total': final int total}
        when total == items.length) {
      return StockInventario._(
        items.cast<Map<String, dynamic>>().map(UnidadStock.fromJson).toList(),
        total,
      );
    }
    throw const FormatException('Respuesta de stock inválida');
  }
}
