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
import { seedDemoData, passwordHash } from '../src/auth.mjs';
import { createApplication } from '../src/app.mjs';
import { obtenerFichaSolicitud } from '../src/requests.mjs';

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

test('Despacho: resuelve el ID de la unidad y valida la reserva activa sin tocar el historial', async t => {
  const store = new SqliteStore(':memory:');
  t.after(() => store.close());
  seedDemoData(store, 'DemoHemoLink2026!');
  const pedidoId = 'PED-RESERVAS';
  const pedidoAjeno = 'PED-AJENAS';
  const solicitud = (id, cantidadSolicitada) => ({
    id, module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
    grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada, cantidadDespachada: 0,
  });
  const unidad = (id, cambios) => ({
    id, module: 'inventory', scopeId: 'sede-central', pedidoId, estado: 'reservada',
    grupoAbo: 'O', factorRh: 'positivo', fechaVencimiento: '2026-12-01', ...cambios,
  });
  const reserva = (id, unidadId, cambios) => ({
    id, unidadId, module: 'reservations', scopeId: 'sede-central', pedidoId,
    estado: 'reservada', ...cambios,
  });
  store.update(db => db.records.push(
    solicitud(pedidoId, 2), solicitud(pedidoAjeno, 3),
    unidad('U-ACTIVA'), unidad('U-RESTANTE'),
    unidad('U-SIN-FECHA', { fechaVencimiento: null, pedidoId: pedidoAjeno }),
    unidad('U-OTRA-SEDE', { pedidoId: pedidoAjeno }),
    unidad('U-OTRO-PEDIDO', { pedidoId: pedidoAjeno }),
    reserva('R-HISTORIAL', 'U-ACTIVA', { estado: 'vencida' }),
    reserva('R-ACTIVA', 'U-ACTIVA'), reserva('R-RESTANTE', 'U-RESTANTE'),
    reserva('R-OTRA-SEDE', 'U-OTRA-SEDE', { scopeId: 'sede-norte', pedidoId: pedidoAjeno }),
    reserva('R-OTRO-PEDIDO', 'U-OTRO-PEDIDO'),
  ));
  const despachar = (reservaIds, id = pedidoId) => confirmarDespacho({
    store, user: USER_INV, pedidoId: id, hoy: HOY, ahora: AHORA,
    datos: { tipo: 'urgente', motivo: 'Cirugía', reservaIds },
  });

  const antes = store.read();
  await assert.rejects(() => despachar(['U-ACTIVA', 'R-ACTIVA']), { status: 400 });
  await assert.rejects(() => despachar(['R-OTRA-SEDE'], pedidoAjeno), { status: 409 });
  await assert.rejects(() => despachar(['R-OTRO-PEDIDO'], pedidoAjeno), { status: 400 });
  await assert.rejects(() => despachar(['R-HISTORIAL']), { status: 400 });
  await assert.rejects(() => despachar(['U-SIN-FECHA'], pedidoAjeno), {
    status: 400, message: /fecha de vencimiento inválida/,
  });
  assert.deepEqual(store.read(), antes);

  const salida = await despachar(['U-ACTIVA']);
  assert.deepEqual(salida.item.unidades, ['U-ACTIVA']);
  assert.equal(salida.saldos.cantidadDespachada, 1);
  assert.equal(salida.saldos.cantidadReservada, 1);
  assert.equal(salida.saldos.pendienteAsignar, 0);
  const registros = new Map(store.read().records.map(r => [r.id, r]));
  assert.equal(registros.get('R-HISTORIAL').estado, 'vencida');
  assert.equal(registros.get('R-HISTORIAL').despachoId, undefined);
  assert.equal(registros.get('R-ACTIVA').despachoId, salida.item.id);
  assert.equal(registros.get('R-ACTIVA').estado, 'cerrada');
  assert.equal(registros.get('R-RESTANTE').estado, 'reservada');
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
        id: 'UNI-LIBERAR', module: 'inventory', scopeId: 'sede-central', codigo: 'U-LIBERAR', donacionId: 'DON-B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-B1', fechaVencimiento: '2026-11-28',
      },
      {
        id: 'RES-VIG', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-VIG',
        pedidoId: 'PED-B1', estado: 'reservada', fechaVencimiento: '2026-11-28',
      },
      {
        id: 'RES-VENC', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-LIBERAR',
        pedidoId: 'PED-B1', estado: 'reservada', fechaVencimiento: HOY,
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
      datos: { tipo: 'urgente', motivo: 'Cirugía', reservaIds: ['UNI-VIG', 'UNI-VENC', 'RES-VENC'] },
    }),
    (err) => err instanceof DispatchError && err.status === 409
  );

  // Comprobar persistencia atómica de la invalidación exclusiva
  const db = store.read();
  const uVenc = db.records.find((r) => r.id === 'UNI-VENC');
  assert.equal(uVenc.estado, 'vencida');
  assert.equal(uVenc.usuarioModificacionId, USER_INV.id);
  assert.equal(uVenc.fechaModificacion, AHORA);
  assert.equal(db.records.find(r => r.id === 'RES-VENC').estado, 'vencida');
  assert.equal(db.records.find(r => r.id === 'UNI-LIBERAR').estado, 'disponible');
  assert.equal(db.records.find(r => r.id === 'RES-VIG').estado, 'reservada');
  assert.equal(db.records.filter(r => r.module === 'dispatches').length, 0);

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

  // El reintento recupera el comprobante aunque la fecha prevista ya haya pasado.
  const segundoIntento = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-C1', hoy: '2026-12-01', ahora: '2026-12-01T12:00:00.000Z',
    datos: { ...datos, tipo: ' Programado ', fechaPrevista: ' 2026-11-30 ' },
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

test('HTTP HU10: ambas rutas revalidan la sesión al confirmar dentro de la transacción', async t => {
  const inicio = new Date(2026, 10, 22, 10).getTime();
  let dentroDeTransaccion = false;
  let expirarSesion = false;
  let expiracion;
  const { server, store } = createApplication({
    databasePath: ':memory:', seedDemo: true,
    clock: () => dentroDeTransaccion && expirarSesion ? expiracion : inicio,
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const pedidoId = 'PED-SESION';
  store.update(db => db.records.push(
    {
      id: pedidoId, module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
      grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 1, cantidadDespachada: 0,
    },
    {
      id: 'U-SESION', module: 'inventory', scopeId: 'sede-central', pedidoId, estado: 'reservada',
      grupoAbo: 'O', factorRh: 'positivo', fechaVencimiento: '2026-12-10',
    },
  ));
  const enviar = (ruta, datos, token) => fetch(`http://127.0.0.1:${server.address().port}${ruta}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token && { Authorization: `Bearer ${token}` }),
    },
    body: JSON.stringify(datos),
  });
  const login = await enviar('/api/login', {
    email: 'inventario@hemolink.test', password: 'DemoHemoLink2026!',
  });
  assert.equal(login.status, 200);
  const { token, expiresAt } = await login.json();
  expiracion = expiresAt;
  const update = store.update.bind(store);
  store.update = escribir => update(db => {
    dentroDeTransaccion = true;
    try { return escribir(db); }
    finally { dentroDeTransaccion = false; }
  });

  const datos = { pedidoId, tipo: 'urgente', motivo: 'Cirugía', reservaIds: ['U-SESION'] };
  const rutaPedido = `/api/requests/${pedidoId}/dispatches`;
  const antes = store.read();
  expirarSesion = true;
  for (const ruta of [rutaPedido, '/api/dispatches']) {
    const respuesta = await enviar(ruta, datos, token);
    assert.equal(respuesta.status, 401, ruta);
    await respuesta.json();
    assert.deepEqual(store.read(), antes);
  }
  expirarSesion = false;
  const aceptado = await enviar(rutaPedido, datos, token);
  assert.equal(aceptado.status, 201);
  assert.equal((await aceptado.json()).item.cantidad, 1);
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

test('UT10.3-A: Mover n unidades aumenta D, reduce R y F, y mantiene P', async (t) => {
  const store = new SqliteStore(':memory:');
  t?.after?.(() => store.close());
  seedDemoData(store, 'DemoHemoLink2026!');

  // Pedido con Q = 5. Reservas en distintas sedes: 2 en sede-central, 1 en sede-norte (Total R = 3).
  // Inicialmente: D = 0, R = 3, F = 5, P = 2, estado = 'parcial'.
  store.update((db) => {
    db.records.push(
      {
        id: 'PED-103A', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 5, cantidadDespachada: 0,
        cantidadReservada: 3, pendienteAsignar: 2, pendienteEntregar: 5, estado: 'parcial',
      },
      { id: 'DON-103A', module: 'donations', scopeId: 'sede-central' },
      { id: 'DON-NORTE-103A', module: 'donations', scopeId: 'sede-norte' },
      {
        id: 'UNI-C1', module: 'inventory', scopeId: 'sede-central', codigo: 'U-C1', donacionId: 'DON-103A',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-103A', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'UNI-C2', module: 'inventory', scopeId: 'sede-central', codigo: 'U-C2', donacionId: 'DON-103A',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-103A', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'UNI-N1', module: 'inventory', scopeId: 'sede-norte', codigo: 'U-N1', donacionId: 'DON-NORTE-103A',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-103A', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'RES-C1', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-C1',
        pedidoId: 'PED-103A', estado: 'reservada', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'RES-C2', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-C2',
        pedidoId: 'PED-103A', estado: 'reservada', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'RES-N1', module: 'reservations', scopeId: 'sede-norte', unidadId: 'UNI-N1',
        pedidoId: 'PED-103A', estado: 'reservada', fechaVencimiento: '2026-12-10',
      },
    );
  });

  // Mover n = 2 unidades desde sede-central (UNI-C1 y UNI-C2)
  const resultado = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-103A', hoy: HOY, ahora: AHORA,
    datos: { tipo: 'urgente', motivo: 'Despacho parcial T10.3-A', reservaIds: ['UNI-C1', 'UNI-C2'] },
  });

  // D aumenta en 2 (0 -> 2)
  assert.equal(resultado.saldos.cantidadDespachada, 2);
  // R disminuye en 2 (3 -> 1, ya que UNI-N1 en sede-norte sigue reservada)
  assert.equal(resultado.saldos.cantidadReservada, 1);
  // F (pendienteEntregar) disminuye en 2 (5 -> 3)
  assert.equal(resultado.saldos.pendienteEntregar, 3);
  // P (pendienteAsignar) se mantiene en 2
  assert.equal(resultado.saldos.pendienteAsignar, 2);
  assert.equal(resultado.saldos.estado, 'parcial');

  // Verificar persistencia en base de datos
  const db = store.read();
  const pedido = db.records.find((r) => r.id === 'PED-103A');
  assert.equal(pedido.cantidadDespachada, 2);
  assert.equal(pedido.cantidadReservada, 1);
  assert.equal(pedido.pendienteEntregar, 3);
  assert.equal(pedido.pendienteAsignar, 2);
  assert.equal(pedido.estado, 'parcial');

  // Verificar que obtenerFichaSolicitud expone contadores actualizados y el comprobante
  const userHospital = { id: 'hospital-demo', role: 'hospital', hospitalId: 'hospital-demo' };
  const ficha = obtenerFichaSolicitud(db, userHospital, 'PED-103A', { hoy: HOY });
  assert.equal(ficha.cantidadDespachada, 2);
  assert.equal(ficha.cantidadReservada, 1);
  assert.equal(ficha.pendienteEntregar, 3);
  assert.equal(ficha.pendienteAsignar, 2);
  assert.equal(ficha.estado, 'parcial');
  assert.equal(ficha.despachos.length, 1);
  assert.equal(ficha.despachos[0].id, resultado.item.id);
  assert.deepEqual(ficha.despachos[0].unidades, ['UNI-C1', 'UNI-C2']);
});

test('UT10.3-B: Despacho completo cierra el pedido', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'hemolink-disp-103b-'));
  const dbPath = join(dir, 'hemolink.sqlite');
  let store = new SqliteStore(dbPath);
  t.after(() => {
    try { store?.close(); } catch {}
    try { rmSync(dir, { recursive: true, force: true }); } catch {}
  });

  seedDemoData(store, 'DemoHemoLink2026!');

  // Pedido con Q = 3. Reservas R = 3 (D = 0, F = 3, P = 0, estado = 'reservado')
  store.update((db) => {
    db.records.push(
      {
        id: 'PED-103B', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 3, cantidadDespachada: 0,
        cantidadReservada: 3, pendienteAsignar: 0, pendienteEntregar: 3, estado: 'reservado',
      },
      { id: 'DON-103B', module: 'donations', scopeId: 'sede-central' },
      {
        id: 'UNI-B1', module: 'inventory', scopeId: 'sede-central', codigo: 'U-B1', donacionId: 'DON-103B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-103B', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'UNI-B2', module: 'inventory', scopeId: 'sede-central', codigo: 'U-B2', donacionId: 'DON-103B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-103B', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'UNI-B3', module: 'inventory', scopeId: 'sede-central', codigo: 'U-B3', donacionId: 'DON-103B',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-103B', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'RES-B1', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-B1',
        pedidoId: 'PED-103B', estado: 'reservada', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'RES-B2', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-B2',
        pedidoId: 'PED-103B', estado: 'reservada', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'RES-B3', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-B3',
        pedidoId: 'PED-103B', estado: 'reservada', fechaVencimiento: '2026-12-10',
      },
    );
  });

  // 1. Salida parcial de 2 unidades
  const r1 = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-103B', hoy: HOY, ahora: AHORA,
    datos: { tipo: 'programado', fechaPrevista: '2026-11-28', reservaIds: ['UNI-B1', 'UNI-B2'] },
  });
  assert.equal(r1.saldos.cantidadDespachada, 2);
  assert.equal(r1.saldos.cantidadReservada, 1);
  assert.equal(r1.saldos.pendienteEntregar, 1);
  assert.equal(r1.saldos.estado, 'parcial');

  // 2. Salida de la unidad restante (D = Q = 3) -> Cierre de pedido
  const r2 = await confirmarDespacho({
    store, user: USER_INV, pedidoId: 'PED-103B', hoy: HOY, ahora: AHORA,
    datos: { tipo: 'urgente', motivo: 'Entrega final', reservaIds: ['UNI-B3'] },
  });

  assert.equal(r2.saldos.cantidadDespachada, 3);
  assert.equal(r2.saldos.cantidadReservada, 0);
  assert.equal(r2.saldos.pendienteEntregar, 0);
  assert.equal(r2.saldos.pendienteAsignar, 0);
  assert.equal(r2.saldos.estado, 'completado');

  // Comprobar persistencia tras reiniciar la base SQLite
  store.close();
  store = new SqliteStore(dbPath);

  const db = store.read();
  const pedido = db.records.find((r) => r.id === 'PED-103B');
  assert.equal(pedido.estado, 'completado');
  assert.equal(pedido.cantidadDespachada, 3);
  assert.equal(pedido.cantidadReservada, 0);
  assert.equal(pedido.pendienteEntregar, 0);
  assert.equal(pedido.pendienteAsignar, 0);

  const userHospital = { id: 'hospital-demo', role: 'hospital', hospitalId: 'hospital-demo' };
  const ficha = obtenerFichaSolicitud(db, userHospital, 'PED-103B', { hoy: HOY });
  assert.equal(ficha.estado, 'completado');
  assert.equal(ficha.pendienteEntregar, 0);
  assert.equal(ficha.despachos.length, 2);
});

test('UT10.3-C: Hospital ajeno no recibe el comprobante', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'hemolink-disp-103c-'));
  const dbPath = join(dir, 'hemolink.sqlite');
  const application = createApplication({ databasePath: dbPath, seedDemo: true });

  await new Promise((resolve) => application.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${application.server.address().port}`;

  t.after(async () => {
    await new Promise((resolve) => application.server.close(resolve));
    rmSync(dir, { recursive: true, force: true });
  });

  // Registrar un segundo hospital en la base para verificar el aislamiento
  application.store.update((db) => {
    db.users.push({
      id: 'hosp-regional-user',
      email: 'hospital2@hemolink.test',
      role: 'hospital',
      isVerified: true,
      passwordHash: passwordHash('DemoHemoLink2026!'),
      siteId: null,
      hospitalId: 'hospital-regional',
    });

    db.records.push(
      {
        id: 'PED-103C', module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
        grupoAbo: 'O', factorRh: 'positivo', cantidadSolicitada: 2, cantidadDespachada: 0,
        cantidadReservada: 1, pendienteAsignar: 1, pendienteEntregar: 2, estado: 'parcial',
      },
      { id: 'DON-103C', module: 'donations', scopeId: 'sede-central' },
      {
        id: 'UNI-C103', module: 'inventory', scopeId: 'sede-central', codigo: 'U-C103', donacionId: 'DON-103C',
        grupoAbo: 'O', factorRh: 'positivo', estado: 'reservada', pedidoId: 'PED-103C', fechaVencimiento: '2026-12-10',
      },
      {
        id: 'RES-C103', module: 'reservations', scopeId: 'sede-central', unidadId: 'UNI-C103',
        pedidoId: 'PED-103C', estado: 'reservada', fechaVencimiento: '2026-12-10',
      },
    );
  });

  const request = async (path, { token, body, method = 'GET' } = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, data: res.status === 204 ? null : await res.json() };
  };

  const tokenHospital1 = (await request('/api/login', {
    method: 'POST', body: { email: 'hospital@hemolink.test', password: 'DemoHemoLink2026!' },
  })).data.token;

  const tokenHospital2 = (await request('/api/login', {
    method: 'POST', body: { email: 'hospital2@hemolink.test', password: 'DemoHemoLink2026!' },
  })).data.token;

  const tokenInventario = (await request('/api/login', {
    method: 'POST', body: { email: 'inventario@hemolink.test', password: 'DemoHemoLink2026!' },
  })).data.token;

  const tokenEnfermeria = (await request('/api/login', {
    method: 'POST', body: { email: 'enfermeria@hemolink.test', password: 'DemoHemoLink2026!' },
  })).data.token;

  // Inventario emite despacho para PED-103C
  const despachoRes = await request('/api/requests/PED-103C/dispatches', {
    method: 'POST',
    token: tokenInventario,
    body: { tipo: 'urgente', motivo: 'Emergencia 103C', reservaIds: ['UNI-C103'] },
  });
  assert.equal(despachoRes.status, 201);
  const comprobanteId = despachoRes.data.item.id;

  // 1. Hospital titular (Hospital 1) consulta ficha: recibe 200 con el comprobante en despachos
  const fichaH1 = await request('/api/requests/PED-103C', { token: tokenHospital1 });
  assert.equal(fichaH1.status, 200);
  assert.equal(fichaH1.data.item.id, 'PED-103C');
  assert.equal(fichaH1.data.item.despachos.length, 1);
  assert.equal(fichaH1.data.item.despachos[0].id, comprobanteId);

  // 2. Personal de inventario consulta ficha: recibe 200 con el comprobante
  const fichaInv = await request('/api/requests/PED-103C', { token: tokenInventario });
  assert.equal(fichaInv.status, 200);
  assert.equal(fichaInv.data.item.despachos.length, 1);
  assert.equal(fichaInv.data.item.despachos[0].id, comprobanteId);

  // 3. Hospital ajeno (Hospital 2) intenta consultar ficha: recibe 404 (bloqueado)
  const fichaH2 = await request('/api/requests/PED-103C', { token: tokenHospital2 });
  assert.equal(fichaH2.status, 404);
  assert.equal(fichaH2.data.message, 'Solicitud no encontrada.');

  // Hospital 2 consulta bandeja global de solicitudes: no incluye PED-103C
  const bandejaH2 = await request('/api/requests', { token: tokenHospital2 });
  assert.equal(bandejaH2.status, 200);
  assert.ok(!bandejaH2.data.items.some((r) => r.id === 'PED-103C'));

  // 4. Hospital 2 intenta acceder directamente a /api/dispatches: recibe 403 (solo inventario)
  const directDispH2 = await request('/api/dispatches', { token: tokenHospital2 });
  assert.equal(directDispH2.status, 403);

  const directDispItemH2 = await request(`/api/dispatches/${comprobanteId}`, { token: tokenHospital2 });
  assert.equal(directDispItemH2.status, 403);

  // 5. Usuario sin sesión o rol sin permiso (enfermería) no pueden consultar la ficha (401 / 403)
  assert.equal((await request('/api/requests/PED-103C')).status, 401);
  assert.equal((await request('/api/requests/PED-103C', { token: tokenEnfermeria })).status, 403);
});





