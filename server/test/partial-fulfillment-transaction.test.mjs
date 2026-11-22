
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  confirmarAtencionParcial,
} from '../src/partial-fulfillment-transaction.mjs';

// Base de datos ficticia para probar la atomicidad.
function crearBase() {
  return {
    pedidos: {
      'PED-001': { Q: 5, D: 0, R: 0 },
    },
    unidades: [
      { id: 'UNI-001', disponible: true },
      { id: 'UNI-002', disponible: true },
    ],
    reservas: [],
    avisos: [],
  };
}

// Simula el comportamiento de una transacción:
// los cambios solo se confirman si todo termina bien.
function crearStore() {
  let datos = crearBase();

  return {
    get datos() {
      return structuredClone(datos);
    },

    async update(operacion) {
      const copia = structuredClone(datos);
      const resultado = operacion(copia);

      // Si la operación falla, no se reemplaza el estado.
      // Si termina correctamente, se confirma completo.
      datos = copia;
      return resultado;
    },
  };
}

// Adaptadores ficticios; después reutilizaremos
// las operaciones reales del servidor.
function dependencias(store) {
  return {
    store,

    obtenerEstado(datos, pedidoId) {
      return {
        saldos: datos.pedidos[pedidoId],
        unidadesElegibles: datos.unidades
          .filter((unidad) => unidad.disponible)
          .map((unidad) => unidad.id),
      };
    },

    guardarReservas(datos, plan) {
      for (const id of plan.reservaIds) {
        const unidad = datos.unidades.find(
          (item) => item.id === id,
        );

        unidad.disponible = false;

        datos.reservas.push({
          pedidoId: plan.pedidoId,
          unidadId: id,
        });
      }

      datos.pedidos[plan.pedidoId].R +=
        plan.reservaIds.length;
    },

    guardarAviso(datos, aviso) {
      datos.avisos.push(aviso);
    },
  };
}

test('T09.2: aceptar guarda reservas y aviso juntos', async () => {
  const store = crearStore();

  const resultado = await confirmarAtencionParcial({
    ...dependencias(store),
    pedidoId: 'PED-001',
    decision: 'aceptar',
    unidadesPropuestas: ['UNI-001', 'UNI-002'],
  });

  assert.deepEqual(resultado.reservaIds, [
    'UNI-001',
    'UNI-002',
  ]);

  assert.equal(store.datos.reservas.length, 2);
  assert.equal(store.datos.avisos.length, 1);

  assert.equal(
    store.datos.avisos[0].cantidadFaltante,
    3,
  );

  assert.equal(store.datos.pedidos['PED-001'].R, 2);
});

test('T09.2: rechazar guarda solo el aviso', async () => {
  const store = crearStore();

  await confirmarAtencionParcial({
    ...dependencias(store),
    pedidoId: 'PED-001',
    decision: 'rechazar',
    unidadesPropuestas: [],
  });

  assert.equal(store.datos.reservas.length, 0);
  assert.equal(store.datos.avisos.length, 1);
  assert.equal(
    store.datos.avisos[0].cantidadFaltante,
    5,
  );
});

test('T09.2: fallo del aviso revierte las reservas', async () => {
  const store = crearStore();

  const servicios = dependencias(store);

  servicios.guardarAviso = () => {
    throw new Error('Fallo de escritura simulado');
  };

  await assert.rejects(
    confirmarAtencionParcial({
      ...servicios,
      pedidoId: 'PED-001',
      decision: 'aceptar',
      unidadesPropuestas: ['UNI-001', 'UNI-002'],
    }),
    /Fallo de escritura simulado/,
  );

  // Ninguna reserva se confirma.
  assert.equal(store.datos.reservas.length, 0);

  // Tampoco se confirma el aviso.
  assert.equal(store.datos.avisos.length, 0);

  // El pedido conserva su saldo original.
  assert.equal(store.datos.pedidos['PED-001'].R, 0);

  // Las unidades continúan disponibles.
  assert.equal(
    store.datos.unidades.every(
      (unidad) => unidad.disponible,
    ),
    true,
  );
});

test('T09.2: una unidad ya reservada genera conflicto', async () => {
  const store = crearStore();

  const servicios = dependencias(store);

  await confirmarAtencionParcial({
    ...servicios,
    pedidoId: 'PED-001',
    decision: 'aceptar',
    unidadesPropuestas: ['UNI-001'],
  });

  const estadoAnterior = store.datos;

  await assert.rejects(
    confirmarAtencionParcial({
      ...servicios,
      pedidoId: 'PED-001',
      decision: 'aceptar',
      unidadesPropuestas: ['UNI-001'],
    }),
    (error) => error.code === 'STOCK_CONFLICT',
  );

  // El intento fallido no altera el estado anterior.
  assert.deepEqual(store.datos, estadoAnterior);
});
