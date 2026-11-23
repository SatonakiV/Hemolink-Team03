
import test from 'node:test';
import assert from 'node:assert/strict';

import { SqliteStore } from '../src/sqlite-store.mjs';
import { seedDemoData } from '../src/auth.mjs';
import { obtenerFichaSolicitud } from '../src/requests.mjs';

import {
  atenderPedidoParcial,
} from '../src/partial-fulfillment-integration.mjs';

const HOY = '2026-11-22';
const AHORA = '2026-11-22T20:00:00.000Z';

function prepararBase(t) {
  const store = new SqliteStore(':memory:');

  t.after(() => store.close());

  seedDemoData(store, 'DemoHemoLink2026!');

  store.update(db => {
    db.records.push(
      {
        id: 'PED-HU09',
        module: 'requests',
        scopeId: 'hospital-demo',
        hospitalId: 'hospital-demo',
        grupoAbo: 'O',
        factorRh: 'positivo',
        prioridad: 'normal',
        cantidadSolicitada: 5,
        cantidadDespachada: 0,
        cantidadReservada: 0,
        pendienteAsignar: 5,
        pendienteEntregar: 5,
        estado: 'pendiente',
      },
      {
        id: 'DON-HU09',
        module: 'donations',
        scopeId: 'sede-central',
      },
      {
        id: 'UNI-001',
        module: 'inventory',
        scopeId: 'sede-central',
        codigo: 'HU09-001',
        donacionId: 'DON-HU09',
        grupoAbo: 'O',
        factorRh: 'positivo',
        estado: 'disponible',
        fechaVencimiento: '2026-11-28',
      },
      {
        id: 'UNI-002',
        module: 'inventory',
        scopeId: 'sede-central',
        codigo: 'HU09-002',
        donacionId: 'DON-HU09',
        grupoAbo: 'O',
        factorRh: 'positivo',
        estado: 'disponible',
        fechaVencimiento: '2026-12-10',
      },
    );
  });

  return store;
}

const inventario = {
  id: 'inventory-demo',
  role: 'inventory',
  siteId: 'sede-central',
};

function confirmar(store, cambios = {}) {
  return atenderPedidoParcial({
    store,
    user: inventario,
    pedidoId: 'PED-HU09',
    decision: 'aceptar',
    unidadesPropuestas: ['UNI-001', 'UNI-002'],
    hoy: HOY,
    ahora: AHORA,
    ...cambios,
  });
}

test('T09.2 real: aceptar reserva dos y registra aviso por tres', async t => {
  const store = prepararBase(t);

  const resultado = await confirmar(store);

  assert.deepEqual(resultado.reservaIds, [
    'UNI-001',
    'UNI-002',
  ]);

  assert.equal(resultado.aviso.cantidadFaltante, 3);
  assert.equal(resultado.aviso.hospitalId, 'hospital-demo');
  assert.equal(resultado.saldos.pendienteAsignar, 3);

  const db = store.read();

  const reservas = db.records.filter(
    r =>
      r.module === 'inventory' &&
      r.pedidoId === 'PED-HU09' &&
      r.estado === 'reservada',
  );

  assert.equal(reservas.length, 2);
  assert.equal(reservas[0].donacionId, 'DON-HU09');
  assert.equal(reservas[0].scopeId, 'sede-central');

  const ficha = obtenerFichaSolicitud(
    db,
    { role: 'hospital', hospitalId: 'hospital-demo' },
    'PED-HU09',
    { hoy: HOY },
  );

  assert.equal(ficha.cantidadReservada, 2);
  assert.equal(ficha.pendienteAsignar, 3);
  assert.equal(ficha.pendienteEntregar, 5);
  assert.equal(ficha.estado, 'parcial');
  assert.equal(ficha.avisos.length, 1);
});

test('T09.2 real: rechazar conserva las unidades disponibles', async t => {
  const store = prepararBase(t);

  const resultado = await confirmar(store, {
    decision: 'rechazar',
    unidadesPropuestas: [],
  });

  assert.deepEqual(resultado.reservaIds, []);
  assert.equal(resultado.aviso.cantidadFaltante, 5);

  const db = store.read();

  assert.equal(
    db.records.filter(
      r =>
        r.module === 'inventory' &&
        r.estado === 'reservada',
    ).length,
    0,
  );

  assert.equal(
    db.records.filter(
      r =>
        r.module === 'notices' &&
        r.pedidoId === 'PED-HU09',
    ).length,
    1,
  );
});

test('T09.2 real: stock cero registra aviso sin reservas', async t => {
  const store = prepararBase(t);

  store.update(db => {
    for (const unidad of db.records) {
      if (
        unidad.module === 'inventory' &&
        ['UNI-001', 'UNI-002'].includes(unidad.id)
      ) {
        unidad.estado = 'descartada';
      }
    }
  });

  const resultado = await confirmar(store, {
    unidadesPropuestas: [],
  });

  assert.deepEqual(resultado.reservaIds, []);
  assert.equal(resultado.aviso.cantidadFaltante, 5);
});

test('T09.2 real: stock cambiado devuelve conflicto sin alterar datos', async t => {
  const store = prepararBase(t);

  store.update(db => {
    const unidad = db.records.find(
      r =>
        r.module === 'inventory' &&
        r.id === 'UNI-002',
    );

    unidad.estado = 'descartada';
  });

  const anterior = store.read();

  await assert.rejects(
    confirmar(store),
    error => error.code === 'STOCK_CONFLICT',
  );

  assert.deepEqual(store.read(), anterior);
});

test('T09.2 real: un fallo de integridad revierte toda la transaccion', async t => {
  const store = prepararBase(t);

  // Usuario inexistente: la FK de auditoria fallara
  // al confirmar el cambio en SQLite.
  await assert.rejects(
    confirmar(store, {
      user: {
        id: 'USUARIO-INEXISTENTE',
        role: 'inventory',
        siteId: 'sede-central',
      },
    }),
  );

  const db = store.read();

  // No deben persistir reservas ni avisos.
  assert.equal(
    db.records.filter(
      r =>
        r.module === 'inventory' &&
        r.estado === 'reservada',
    ).length,
    0,
  );

  assert.equal(
    db.records.filter(
      r =>
        r.module === 'notices' &&
        r.pedidoId === 'PED-HU09',
    ).length,
    0,
  );
});
