
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  planificarAtencionParcial,
} from '../src/partial-fulfillment.mjs';

// Pedido ficticio: 5 unidades solicitadas.
const pedidoBase = {
  pedidoId: 'PED-001',
  saldos: {
    Q: 5, // Solicitadas
    D: 0, // Despachadas
    R: 0, // Reservas válidas
  },
};

test('UT09.2-A: aceptar reserva las disponibles e informa el faltante', () => {
  const resultado = planificarAtencionParcial({
    ...pedidoBase,
    decision: 'aceptar',
    unidadesPropuestas: ['UNI-001', 'UNI-002'],
    unidadesElegibles: ['UNI-001', 'UNI-002'],
  });

  // Se proponen dos unidades para reservar.
  assert.deepEqual(resultado.reservaIds, [
    'UNI-001',
    'UNI-002',
  ]);

  // Quedan tres unidades sin asignar.
  assert.equal(resultado.aviso.pedidoId, 'PED-001');
  assert.equal(resultado.aviso.cantidadFaltante, 3);

  assert.equal(resultado.pendientePorAsignar, 3);

  // Todavía no se ha despachado ninguna unidad.
  assert.equal(resultado.pendientePorEntregar, 5);
});

test('UT09.2-B: rechazar no genera reservas nuevas', () => {
  const resultado = planificarAtencionParcial({
    ...pedidoBase,
    decision: 'rechazar',
    unidadesPropuestas: ['UNI-001', 'UNI-002'],
    unidadesElegibles: ['UNI-001', 'UNI-002'],
  });

  // El rechazo no debe asignar unidades.
  assert.deepEqual(resultado.reservaIds, []);

  // Se informa el faltante completo por asignar.
  assert.equal(resultado.aviso.cantidadFaltante, 5);
  assert.equal(resultado.pendientePorAsignar, 5);
});

test('UT09.2-B: stock cero registra aviso sin reservas', () => {
  const resultado = planificarAtencionParcial({
    ...pedidoBase,
    decision: 'aceptar',
    unidadesPropuestas: [],
    unidadesElegibles: [],
  });

  assert.deepEqual(resultado.reservaIds, []);

  assert.equal(resultado.aviso.cantidadFaltante, 5);
  assert.equal(resultado.pendientePorAsignar, 5);
});

test('UT09.2-C: cambio de stock provoca conflicto', () => {
  assert.throws(
    () => planificarAtencionParcial({
      ...pedidoBase,
      decision: 'aceptar',

      // El usuario seleccionó estas dos unidades.
      unidadesPropuestas: ['UNI-001', 'UNI-002'],

      // Al revalidar, la segunda ya no está disponible.
      unidadesElegibles: ['UNI-001'],
    }),
    (error) => error.code === 'STOCK_CONFLICT',
  );
});

test('UT09.2: no permite reservar por encima del saldo', () => {
  assert.throws(
    () => planificarAtencionParcial({
      pedidoId: 'PED-002',
      saldos: {
        Q: 5,
        D: 2,
        R: 2,
      },
      decision: 'aceptar',
      unidadesPropuestas: ['UNI-001', 'UNI-002'],
      unidadesElegibles: ['UNI-001', 'UNI-002'],
    }),
  );
});

test('UT09.2: conserva reservas existentes al rechazar', () => {
  const resultado = planificarAtencionParcial({
    pedidoId: 'PED-003',
    saldos: {
      Q: 8,
      D: 2,
      R: 3,
    },
    decision: 'rechazar',
    unidadesPropuestas: [],
    unidadesElegibles: [],
  });

  // Q - D - R = 8 - 2 - 3 = 3.
  assert.equal(resultado.pendientePorAsignar, 3);

  // Q - D = 8 - 2 = 6.
  assert.equal(resultado.pendientePorEntregar, 6);

  // Las reservas previas no se modifican.
  assert.deepEqual(resultado.reservaIds, []);
  assert.equal(resultado.aviso.cantidadFaltante, 3);
});
