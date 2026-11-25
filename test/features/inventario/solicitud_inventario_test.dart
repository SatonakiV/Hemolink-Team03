import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/inventario/data/solicitud_inventario.dart';

void main() {
  group('SolicitudInventario', () {
    test('diferencia pendiente de asignar y pendiente de entregar', () {
      final solicitud = SolicitudInventario.fromJson({
        'id': 'PED-001',
        'numero': 1,
        'grupoAbo': 'O',
        'factorRh': 'negativo',
        'prioridad': 'urgente',
        'cantidadSolicitada': 5,
        'cantidadDespachada': 0,
        'cantidadReservada': 2,
        'pendienteAsignar': 3,
        'pendienteEntregar': 5,
        'estado': 'parcial',
        'avisos': [],
      });

      expect(solicitud.pendienteAsignar, 3);
      expect(solicitud.pendienteEntregar, 5);
      expect(solicitud.grupo, 'O-');
    });

    test('recupera el faltante del aviso persistido', () {
      final solicitud = SolicitudInventario.fromJson({
        'id': 'PED-002',
        'numero': 2,
        'grupoAbo': 'A',
        'factorRh': 'positivo',
        'prioridad': 'normal',
        'cantidadSolicitada': 5,
        'cantidadDespachada': 0,
        'cantidadReservada': 2,
        'pendienteAsignar': 3,
        'pendienteEntregar': 5,
        'estado': 'parcial',
        'avisos': [
          {
            'pedidoId': 'PED-002',
            'cantidadFaltante': 3,
            'decision': 'aceptar',
          },
        ],
      });

      expect(solicitud.ultimoAviso, isNotNull);
      expect(solicitud.cantidadFaltante, 3);
      expect(solicitud.ultimoAviso!.decision, 'aceptar');
    });
  });

  group('PropuestaReserva', () {
    test('conserva los identificadores de las unidades FEFO', () {
      final propuesta = PropuestaReserva.fromJson({
        'estado': 'stock_insuficiente',
        'pendienteAsignar': 5,
        'stockElegible': 2,
        'faltante': 3,
        'unidades': [
          {
            'id': 'UNI-001',
            'codigo': 'U001',
            'sedeId': 'sede-central',
            'grupoAbo': 'O',
            'factorRh': 'negativo',
            'fechaVencimiento': '2026-12-01',
          },
          {
            'id': 'UNI-002',
            'codigo': 'U002',
            'sedeId': 'sede-central',
            'grupoAbo': 'O',
            'factorRh': 'negativo',
            'fechaVencimiento': '2026-12-05',
          },
        ],
      });

      expect(propuesta.faltante, 3);
      expect(propuesta.stockElegible, 2);
      expect(propuesta.unidades.length, 2);
      expect(propuesta.unidades.first.id, 'UNI-001');
      expect(propuesta.unidades.last.id, 'UNI-002');
    });

    test('rechaza unidades sin identificador', () {
      expect(
        () => PropuestaReserva.fromJson({
          'estado': 'completa',
          'pendienteAsignar': 1,
          'stockElegible': 1,
          'faltante': 0,
          'unidades': [
            {
              'codigo': 'U001',
              'sedeId': 'sede-central',
              'grupoAbo': 'O',
              'factorRh': 'negativo',
              'fechaVencimiento': '2026-12-01',
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
