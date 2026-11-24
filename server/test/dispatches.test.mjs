import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  DispatchError,
  validarComandoDespacho,
  crearComprobanteDespacho,
  confirmarDespacho,
} from '../src/dispatches.mjs';
import { SqliteStore } from '../src/sqlite-store.mjs';
import { seedDemoData } from '../src/auth.mjs';

test('UT10.1-A: programado acepta fecha civil válida', () => {
  const comandoValido = validarComandoDespacho({
    tipo: 'programado',
    fechaPrevista: '2026-12-01',
    reservaIds: ['RES-001', 'RES-002'],
  });

  assert.equal(comandoValido.tipo, 'programado');
  assert.equal(comandoValido.fechaPrevista, '2026-12-01');
  assert.equal(comandoValido.motivo, null);
  assert.deepEqual(comandoValido.reservaIds, ['RES-001', 'RES-002']);

  const comprobante = crearComprobanteDespacho(comandoValido, {
    clock: () => new Date('2026-11-20T10:00:00Z').getTime(),
  });
  assert.equal(comprobante.tipo, 'programado');
  assert.equal(comprobante.fechaPrevista, '2026-12-01');
  assert.deepEqual(comprobante.reservaIds, ['RES-001', 'RES-002']);

  // Rechaza fecha inválida (formato incorrecto o fecha imposible como 2026-02-30)
  for (const fechaInvalida of ['', '2026-13-01', '2026-02-30', 'invalida']) {
    assert.throws(
      () =>
        validarComandoDespacho({
          tipo: 'programado',
          fechaPrevista: fechaInvalida,
          reservaIds: ['RES-001'],
        }),
      (err) => err instanceof DispatchError && err.status === 400
    );
  }
});

test('UT10.1-B: urgente acepta motivo y rechaza blancos', () => {
  const comandoValido = validarComandoDespacho({
    tipo: 'urgente',
    motivo: '  Cirugía de emergencia  ',
    reservaIds: ['RES-003'],
  });

  assert.equal(comandoValido.tipo, 'urgente');
  assert.equal(comandoValido.fechaPrevista, null);
  assert.equal(comandoValido.motivo, 'Cirugía de emergencia');
  assert.deepEqual(comandoValido.reservaIds, ['RES-003']);

  const comprobante = crearComprobanteDespacho(comandoValido, {
    clock: () => new Date('2026-11-20T11:00:00Z').getTime(),
  });
  assert.equal(comprobante.tipo, 'urgente');
  assert.equal(comprobante.motivo, 'Cirugía de emergencia');
  assert.deepEqual(comprobante.reservaIds, ['RES-003']);

  // Rechaza motivo ausente, vacío o compuesto solo de espacios en blanco
  for (const motivoInvalido of [undefined, null, '', '   ', '\t\n']) {
    assert.throws(
      () =>
        validarComandoDespacho({
          tipo: 'urgente',
          motivo: motivoInvalido,
          reservaIds: ['RES-003'],
        }),
      (err) => err instanceof DispatchError && err.status === 400
    );
  }
});

test('UT10.1-C: selección vacía o con IDs repetidos se rechaza', () => {
  // Rechaza selección no proporcionada, vacía o nula
  for (const seleccionInvalida of [undefined, null, [], 'no-array', {}]) {
    assert.throws(
      () =>
        validarComandoDespacho({
          tipo: 'programado',
          fechaPrevista: '2026-12-01',
          reservaIds: seleccionInvalida,
        }),
      (err) => err instanceof DispatchError && err.status === 400
    );
  }

  // Rechaza IDs vacíos dentro del arreglo
  assert.throws(
    () =>
      validarComandoDespacho({
        tipo: 'programado',
        fechaPrevista: '2026-12-01',
        reservaIds: ['RES-001', '   '],
      }),
    (err) => err instanceof DispatchError && err.status === 400
  );

  // Rechaza IDs de reserva duplicados (e.g. ['RES-001', 'RES-001'])
  assert.throws(
    () =>
      validarComandoDespacho({
        tipo: 'programado',
        fechaPrevista: '2026-12-01',
        reservaIds: ['RES-001', 'RES-002', 'RES-001'],
      }),
    (err) =>
      err instanceof DispatchError &&
      err.status === 400 &&
      err.message.includes('duplicados')
  );

  // Admite propiedad alternativa 'unidades' si es un arreglo válido sin duplicados
  const comandoConUnidades = validarComandoDespacho({
    tipo: 'urgente',
    motivo: 'Traslado de emergencia',
    unidades: ['RES-010', 'RES-011'],
  });
  assert.deepEqual(comandoConUnidades.reservaIds, ['RES-010', 'RES-011']);
});

const HOY = '2026-11-22';
const AHORA = '2026-11-22T12:00:00.000Z';
const USER_INV = { id: 'inventory-demo', role: 'inventory', siteId: 'sede-central' };

function crearBasePruebas(t) {
  const store = new SqliteStore(':memory:');
  t?.after?.(() => store.close());
  seedDemoData(store, 'DemoHemoLink2026!');
  store.update((db) => {
    db.records.push(
      {
        id: 'PED-01', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 3, cantidadDespachada: 0,
        cantidadReservada: 2, pendienteAsignar: 1, pendienteEntregar: 3, estado: 'parcial',
      },
      { id: 'DON-01', module: 'donations', scopeId: 'sede-central' },
      { id: 'DON-NORTE', module: 'donations', scopeId: 'sede-norte' },
      {
        id: 'UNI-OK1', module: 'inventory', scopeId: 'sede-central', codigo: 'U-OK1', donacionId: 'DON-01',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-01', fechaVencimiento: '2026-12-01',
      },
      {
        id: 'UNI-OK2', module: 'inventory', scopeId: 'sede-central', codigo: 'U-OK2', donacionId: 'DON-01',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-01', fechaVencimiento: '2026-12-05',
      },
      {
        id: 'UNI-NORTE', module: 'inventory', scopeId: 'sede-norte', codigo: 'U-NORTE', donacionId: 'DON-NORTE',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-01', fechaVencimiento: '2026-12-01',
      },
      {
        id: 'UNI-GRUPO', module: 'inventory', scopeId: 'sede-central', codigo: 'U-GRP', donacionId: 'DON-01',
        grupoAbo: 'A', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-01', fechaVencimiento: '2026-12-01',
      },
      {
        id: 'UNI-DISP', module: 'inventory', scopeId: 'sede-central', codigo: 'U-DISP', donacionId: 'DON-01',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'disponible', fechaVencimiento: '2026-12-01',
      },
    );
  });
  return store;
}

test('UT10.2-A: Sede, grupo, pedido, fecha o estado inválidos rechazan la salida', async (t) => {
  const store = crearBasePruebas(t);

  // 1. Sede manipulada en datos (409)
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-01', hoy: HOY, ahora: AHORA,
      datos: { tipo: 'urgente', motivo: 'Emergencia', reservaIds: ['UNI-OK1'], sedeId: 'sede-otra' },
    }),
    (err) => err instanceof DispatchError && err.status === 409
  );

  // 2. Unidad de sede ajena (409)
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-01', hoy: HOY, ahora: AHORA,
      datos: { tipo: 'urgente', motivo: 'Emergencia', reservaIds: ['UNI-NORTE'] },
    }),
    (err) => err instanceof DispatchError && err.status === 409
  );

  // 3. Grupo ABO contradictorio con el pedido (400)
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-01', hoy: HOY, ahora: AHORA,
      datos: { tipo: 'urgente', motivo: 'Emergencia', reservaIds: ['UNI-GRUPO'] },
    }),
    (err) => err instanceof DispatchError && err.status === 400
  );

  // 4. Pedido inexistente (404)
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-NO-EXISTE', hoy: HOY, ahora: AHORA,
      datos: { tipo: 'urgente', motivo: 'Emergencia', reservaIds: ['UNI-OK1'] },
    }),
    (err) => err instanceof DispatchError && err.status === 404
  );

  // 5. Fecha prevista pasada en despacho programado (400)
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-01', hoy: HOY, ahora: AHORA,
      datos: { tipo: 'programado', fechaPrevista: '2026-11-20', reservaIds: ['UNI-OK1'] },
    }),
    (err) => err instanceof DispatchError && err.status === 400
  );

  // 6. Estado inválido (disponible en vez de reservada) (400)
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-01', hoy: HOY, ahora: AHORA,
      datos: { tipo: 'urgente', motivo: 'Emergencia', reservaIds: ['UNI-DISP'] },
    }),
    (err) => err instanceof DispatchError && err.status === 400
  );

  // 7. Rol ajeno a inventario (403)
  await assert.rejects(
    () => confirmarDespacho({
      store, user: { id: 'hosp', role: 'hospital', siteId: 'sede-central' }, pedidoId: 'PED-01',
      hoy: HOY, ahora: AHORA, datos: { tipo: 'urgente', motivo: 'Emergencia', reservaIds: ['UNI-OK1'] },
    }),
    (err) => err instanceof DispatchError && err.status === 403
  );

  // Verifica que ningún despacho fue creado ni el pedido alterado
  const db = store.read();
  const despachos = db.records.filter((r) => r.module === 'dispatches');
  assert.equal(despachos.length, 0);
  const pedido = db.records.find((r) => r.id === 'PED-01');
  assert.equal(pedido.cantidadDespachada, 0);
  assert.equal(pedido.estado, 'parcial');
});

test('UT10.2-B: Selección inválida solo invalida la reserva propia que perdió vigencia', async (t) => {
  const store = new SqliteStore(':memory:');
  t?.after?.(() => store.close());
  seedDemoData(store, 'DemoHemoLink2026!');

  store.update((db) => {
    db.records.push(
      {
        id: 'PED-B1', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 3, cantidadDespachada: 0,
        cantidadReservada: 2, pendienteAsignar: 1, pendienteEntregar: 3, estado: 'parcial',
      },
      {
        id: 'PED-B2', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 1, cantidadDespachada: 0,
        cantidadReservada: 1, pendienteAsignar: 0, pendienteEntregar: 1, estado: 'reservado',
      },
      { id: 'DON-B', module: 'donations', scopeId: 'sede-central' },
      { id: 'DON-NORTE-B', module: 'donations', scopeId: 'sede-norte' },
      {
        id: 'UNI-VIG', module: 'inventory', scopeId: 'sede-central', codigo: 'U-VIG', donacionId: 'DON-B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-B1', fechaVencimiento: '2026-11-28',
      },
      {
        id: 'UNI-VENC', module: 'inventory', scopeId: 'sede-central', codigo: 'U-VENC', donacionId: 'DON-B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-B1', fechaVencimiento: '2026-11-20',
      },
      {
        id: 'UNI-OTRO-PED', module: 'inventory', scopeId: 'sede-central', codigo: 'U-OTRO', donacionId: 'DON-B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-B2', fechaVencimiento: '2026-11-20',
      },
      {
        id: 'UNI-OTRA-SEDE', module: 'inventory', scopeId: 'sede-norte', codigo: 'U-OTRAS', donacionId: 'DON-NORTE-B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-B1', fechaVencimiento: '2026-11-20',
      },
    );
  });

  // Intento de despacho con una unidad vigente y una vencida seleccionada
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-B1', hoy: HOY, ahora: AHORA,
      datos: { tipo: 'urgente', motivo: 'Cirugía', reservaIds: ['UNI-VIG', 'UNI-VENC'] },
    }),
    (err) => err instanceof DispatchError && err.status === 409
  );

  // Comprobar persistencia atómica de la invalidación exclusiva
  const db = store.read();
  const uVenc = db.records.find((r) => r.id === 'UNI-VENC');
  assert.equal(uVenc.estado, 'vencida');
  assert.equal(uVenc.usuarioModificacionId, USER_INV.id);
  assert.equal(uVenc.fechaModificacion, AHORA);

  // La reserva vigente propia permanece intacta
  const uVig = db.records.find((r) => r.id === 'UNI-VIG');
  assert.equal(uVig.estado, 'reservada');

  // Las reservas de otros pedidos y sedes permanecen intactas
  const uOtroPed = db.records.find((r) => r.id === 'UNI-OTRO-PED');
  assert.equal(uOtroPed.estado, 'reservada');
  const uOtraSede = db.records.find((r) => r.id === 'UNI-OTRA-SEDE');
  assert.equal(uOtraSede.estado, 'reservada');

  // Saldos del pedido recalculados tras persistir la invalidación
  const pedido = db.records.find((r) => r.id === 'PED-B1');
  assert.equal(pedido.cantidadReservada, 1);
  assert.equal(pedido.pendienteAsignar, 2);
  assert.equal(pedido.pendienteEntregar, 3);
  assert.equal(pedido.cantidadDespachada, 0);

  // Conflicto recuperable: despacho posterior de la reserva vigente procede
  const resultado = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-B1', hoy: HOY, ahora: AHORA,
    datos: { tipo: 'urgente', motivo: 'Cirugía', reservaIds: ['UNI-VIG'] },
  });
  assert.equal(resultado.item.tipo, 'urgente');
  assert.equal(resultado.item.cantidad, 1);
  assert.equal(resultado.saldos.cantidadDespachada, 1);
  assert.equal(resultado.saldos.cantidadReservada, 0);
  assert.equal(resultado.saldos.pendienteEntregar, 2);
});

test('UT10.2-C: Misma clave y datos recuperan el resultado', async (t) => {
  const store = new SqliteStore(':memory:');
  t?.after?.(() => store.close());
  seedDemoData(store, 'DemoHemoLink2026!');

  store.update((db) => {
    db.records.push(
      {
        id: 'PED-C1', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 2, cantidadDespachada: 0,
        cantidadReservada: 2, pendienteAsignar: 0, pendienteEntregar: 2, estado: 'reservado',
      },
      { id: 'DON-C', module: 'donations', scopeId: 'sede-central' },
      {
        id: 'UNI-C1', module: 'inventory', scopeId: 'sede-central', codigo: 'U-C1', donacionId: 'DON-C',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-C1', fechaVencimiento: '2026-12-10',
      },
    );
  });

  const datos = {
    tipo: 'programado', fechaPrevista: '2026-11-30', reservaIds: ['UNI-C1'],
    claveConfirmacion: 'clave-idemp-001',
  };

  const primerIntento = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-C1', hoy: HOY, ahora: AHORA, datos,
  });
  assert.equal(primerIntento.existente, false);
  assert.equal(primerIntento.item.cantidad, 1);

  // Reintento idéntico recupera el comprobante original
  const segundoIntento = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-C1', hoy: HOY, ahora: AHORA, datos,
  });
  assert.equal(segundoIntento.existente, true);
  assert.equal(segundoIntento.item.id, primerIntento.item.id);
  assert.equal(segundoIntento.item.fechaRegistro, primerIntento.item.fechaRegistro);

  // Comprueba que no se duplicaron comprobantes ni despacho en saldos
  const db = store.read();
  const despachos = db.records.filter((r) => r.module === 'dispatches');
  assert.equal(despachos.length, 1);
  const pedido = db.records.find((r) => r.id === 'PED-C1');
  assert.equal(pedido.cantidadDespachada, 1);
});

test('UT10.2-D: Misma clave con otros datos produce conflicto', async (t) => {
  const store = new SqliteStore(':memory:');
  t?.after?.(() => store.close());
  seedDemoData(store, 'DemoHemoLink2026!');

  store.update((db) => {
    db.records.push(
      {
        id: 'PED-D1', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 3, cantidadDespachada: 0,
        cantidadReservada: 2, pendienteAsignar: 1, pendienteEntregar: 3, estado: 'parcial',
      },
      { id: 'DON-D', module: 'donations', scopeId: 'sede-central' },
      {
        id: 'UNI-D1', module: 'inventory', scopeId: 'sede-central', codigo: 'U-D1', donacionId: 'DON-D',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-D1', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'UNI-D2', module: 'inventory', scopeId: 'sede-central', codigo: 'U-D2', donacionId: 'DON-D',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-D1', fechaVencimiento: '2026-12-10',
      },
    );
  });

  const datosOriginales = {
    tipo: 'urgente', motivo: 'Cirugía inicial', reservaIds: ['UNI-D1'],
    claveConfirmacion: 'clave-idemp-002',
  };

  const primerIntento = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-D1', hoy: HOY, ahora: AHORA, datos: datosOriginales,
  });
  assert.equal(primerIntento.existente, false);

  // Misma clave con otro motivo produce conflicto 409
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-D1', hoy: HOY, ahora: AHORA,
      datos: { ...datosOriginales, motivo: 'Otro motivo diferente' },
    }),
    (err) => err instanceof DispatchError && err.status === 409 && err.message.includes('otros datos')
  );

  // Misma clave con otra selección de reservas produce conflicto 409
  await assert.rejects(
    () => confirmarDespacho({
      store, user: USER_INV, pedidoId: 'PED-D1', hoy: HOY, ahora: AHORA,
      datos: { ...datosOriginales, reservaIds: ['UNI-D2'] },
    }),
    (err) => err instanceof DispatchError && err.status === 409 && err.message.includes('otros datos')
  );

  // La base conserva únicamente el despacho original y la unidad D2 sigue reservada
  const db = store.read();
  const despachos = db.records.filter((r) => r.module === 'dispatches');
  assert.equal(despachos.length, 1);
  const u2 = db.records.find((r) => r.id === 'UNI-D2');
  assert.equal(u2.estado, 'reservada');
});

test('Integración: Fallo de escritura revierte cambios, y doble confirmación y reinicio conservan un único comprobante, incluso tras importar una base anterior', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'hemolink-disp-'));
  const dbPath = join(dir, 'hemolink.sqlite');
  let store = null;
  let importedStore = null;

  try {
    store = new SqliteStore(dbPath);
    seedDemoData(store, 'DemoHemoLink2026!');

    store.update((db) => {
      db.records.push(
        {
          id: 'PED-INT1', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
          grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 2, cantidadDespachada: 0,
          cantidadReservada: 2, pendienteAsignar: 0, pendienteEntregar: 2, estado: 'reservado',
        },
        { id: 'DON-INT', module: 'donations', scopeId: 'sede-central' },
        {
          id: 'UNI-INT1', module: 'inventory', scopeId: 'sede-central', codigo: 'U-INT1', donacionId: 'DON-INT',
          grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-INT1', fechaVencimiento: '2026-12-15',
        },
        {
          id: 'UNI-INT2', module: 'inventory', scopeId: 'sede-central', codigo: 'U-INT2', donacionId: 'DON-INT',
          grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-INT1', fechaVencimiento: '2026-12-15',
        },
      );
    });

    const clave = 'clave-int-001';
    const datos = {
      tipo: 'urgente', motivo: 'Urgencia integración', reservaIds: ['UNI-INT1'], claveConfirmacion: clave,
    };

    const originalUpdate = store.update.bind(store);
    store.update = (callback) =>
      originalUpdate((db) => {
        callback(db);
        throw new Error('Fallo simulado antes del commit');
      });

    await assert.rejects(
      () => confirmarDespacho({ store, user: USER_INV, pedidoId: 'PED-INT1', hoy: HOY, ahora: AHORA, datos }),
      (err) => err.message === 'Fallo simulado antes del commit'
    );

    store.update = originalUpdate;
    let db = store.read();
    assert.equal(db.records.filter((r) => r.module === 'dispatches').length, 0);
    assert.equal(db.records.find((r) => r.id === 'UNI-INT1').estado, 'reservada');
    assert.equal(db.records.find((r) => r.id === 'PED-INT1').cantidadDespachada, 0);

    await Promise.all([
      confirmarDespacho({ store, user: USER_INV, pedidoId: 'PED-INT1', hoy: HOY, ahora: AHORA, datos }),
      confirmarDespacho({ store, user: USER_INV, pedidoId: 'PED-INT1', hoy: HOY, ahora: AHORA, datos }),
    ]);

    store.close();
    store = new SqliteStore(dbPath);

    db = store.read();
    const despachos = db.records.filter((r) => r.module === 'dispatches' && r.claveConfirmacion === clave);
    assert.equal(despachos.length, 1);
    assert.equal(db.records.find((r) => r.id === 'UNI-INT1').estado, 'despachada');
    assert.equal(db.records.find((r) => r.id === 'PED-INT1').cantidadDespachada, 1);

    const jsonExportPath = join(dir, 'backup.json');
    store.exportJsonTo(jsonExportPath);
    store.close();
    store = null;

    const importedDbPath = join(dir, 'imported.sqlite');
    importedStore = new SqliteStore(importedDbPath, { importJsonPath: jsonExportPath, requireNew: true });

    const recuperado = await confirmarDespacho({
      store: importedStore, user: USER_INV, pedidoId: 'PED-INT1', hoy: HOY, ahora: AHORA, datos,
    });
    assert.equal(recuperado.existente, true);
    assert.equal(recuperado.item.id, despachos[0].id);

    const dbImportada = importedStore.read();
    const despachosImportados = dbImportada.records.filter(
      (r) => r.module === 'dispatches' && r.claveConfirmacion === clave,
    );
    assert.equal(despachosImportados.length, 1);
  } finally {
    try { store?.close(); } catch {}
    try { importedStore?.close(); } catch {}
    try { rmSync(dir, { recursive: true, force: true }); } catch {}
  }
});
