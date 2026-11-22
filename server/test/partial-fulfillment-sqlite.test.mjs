
import test from 'node:test';
import assert from 'node:assert/strict';

import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  SqliteStore,
} from '../src/sqlite-store.mjs';

import {
  confirmarAtencionParcial,
} from '../src/partial-fulfillment-transaction.mjs';

/**
 * HU09 - T09.2
 * Pruebas de integración con SQLite real.
 *
 * Se usan registros ficticios para aislar
 * el comportamiento transaccional.
 */

const UNIDADES = ['UNI-001', 'UNI-002'];

/**
 * Crea una solicitud hospitalaria ficticia.
 */
function sembrarPedido(store) {
  store.update((db) => {
    db.records.push({
      id: 'PED-001',
      module: 'requests',
      scopeId: 'HOSP-001',
      hospitalId: 'HOSP-001',
      grupoAbo: 'O',
      factorRh: 'positivo',
      prioridad: 'normal',
      cantidadSolicitada: 5,
      cantidadDespachada: 0,
      cantidadReservada: 0,
      estado: 'pendiente',
    });
  });
}

/**
 * Adaptadores de prueba.
 *
 * No reemplazan las operaciones de HU08.
 * Permiten comprobar la atomicidad usando
 * el almacén SQLite verdadero.
 */
function crearDependencias(store, {
  fallarAviso = false,
} = {}) {
  return {
    store,

    obtenerEstado(db, pedidoId) {
      const pedido = db.records.find(
        (record) =>
          record.module === 'requests' &&
          record.id === pedidoId,
      );

      if (!pedido) {
        throw new Error('Pedido no encontrado.');
      }

      const reservadas = new Set(
        db.records
          .filter(
            (record) =>
              record.module === 'reservations' &&
              record.estado === 'activa',
          )
          .map((record) => record.unidadId),
      );

      return {
        saldos: {
          Q: pedido.cantidadSolicitada,
          D: pedido.cantidadDespachada,
          R: pedido.cantidadReservada,
        },

        unidadesElegibles: UNIDADES.filter(
          (id) => !reservadas.has(id),
        ),
      };
    },

    guardarReservas(db, plan) {
      const pedido = db.records.find(
        (record) =>
          record.module === 'requests' &&
          record.id === plan.pedidoId,
      );

      for (const id of plan.reservaIds) {
        db.records.push({
          id: `RES-${id}`,
          module: 'reservations',
          scopeId: 'SEDE-001',
          pedidoId: plan.pedidoId,
          unidadId: id,
          estado: 'activa',
        });
      }

      pedido.cantidadReservada += plan.reservaIds.length;
    },

    guardarAviso(db, aviso) {
      if (fallarAviso) {
        throw new Error(
          'Fallo de escritura simulado.',
        );
      }

      const cantidadAvisos = db.records.filter(
        (record) => record.module === 'notices',
      ).length;

      db.records.push({
        id: `AVISO-${cantidadAvisos + 1}`,
        module: 'notices',
        scopeId: 'HOSP-001',
        pedidoId: aviso.pedidoId,
        cantidadFaltante: aviso.cantidadFaltante,
        decision: aviso.decision,
        fechaRegistro: '2026-11-22T19:00:00.000Z',
      });
    },
  };
}

test('SQLite: guarda reservas y aviso tras reiniciar', async () => {
  const directorio = mkdtempSync(
    join(tmpdir(), 'hemolink-hu09-'),
  );

  const ruta = join(directorio, 'prueba.sqlite');
  let store;

  try {
    store = new SqliteStore(ruta);
    sembrarPedido(store);

    const resultado = await confirmarAtencionParcial({
      ...crearDependencias(store),
      pedidoId: 'PED-001',
      decision: 'aceptar',
      unidadesPropuestas: UNIDADES,
    });

    assert.equal(resultado.reservaIds.length, 2);
    assert.equal(resultado.aviso.cantidadFaltante, 3);

    // Cerrar y abrir nuevamente la base.
    store.close();
    store = new SqliteStore(ruta);

    const db = store.read();

    const reservas = db.records.filter(
      (record) => record.module === 'reservations',
    );

    const avisos = db.records.filter(
      (record) => record.module === 'notices',
    );

    const pedido = db.records.find(
      (record) =>
        record.module === 'requests' &&
        record.id === 'PED-001',
    );

    assert.equal(reservas.length, 2);
    assert.equal(avisos.length, 1);
    assert.equal(avisos[0].cantidadFaltante, 3);
    assert.equal(pedido.cantidadReservada, 2);
  } finally {
    store?.close();
    rmSync(directorio, {
      recursive: true,
      force: true,
    });
  }
});

test('SQLite: un fallo del aviso revierte las reservas', async () => {
  const store = new SqliteStore(':memory:');

  try {
    sembrarPedido(store);

    const estadoOriginal = store.read();

    await assert.rejects(
      confirmarAtencionParcial({
        ...crearDependencias(store, {
          fallarAviso: true,
        }),
        pedidoId: 'PED-001',
        decision: 'aceptar',
        unidadesPropuestas: UNIDADES,
      }),
      /Fallo de escritura simulado/,
    );

    // Debe revertirse toda la actualización.
    assert.deepEqual(
      store.read(),
      estadoOriginal,
    );

    assert.equal(
      store.read().records.filter(
        (record) => record.module === 'reservations',
      ).length,
      0,
    );

    assert.equal(
      store.read().records.filter(
        (record) => record.module === 'notices',
      ).length,
      0,
    );
  } finally {
    store.close();
  }
});

test('SQLite: rechazar guarda el aviso sin reservas', async () => {
  const store = new SqliteStore(':memory:');

  try {
    sembrarPedido(store);

    const resultado = await confirmarAtencionParcial({
      ...crearDependencias(store),
      pedidoId: 'PED-001',
      decision: 'rechazar',
      unidadesPropuestas: [],
    });

    const db = store.read();

    assert.deepEqual(resultado.reservaIds, []);

    assert.equal(
      db.records.filter(
        (record) => record.module === 'reservations',
      ).length,
      0,
    );

    const avisos = db.records.filter(
      (record) => record.module === 'notices',
    );

    assert.equal(avisos.length, 1);
    assert.equal(avisos[0].cantidadFaltante, 5);
  } finally {
    store.close();
  }
});
