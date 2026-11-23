import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';

// Reloj fijo: 19-11-2026 12:00 hora local.
const CLOCK = () => new Date(2026, 10, 19, 12).getTime();

const unidad = (id, cambios = {}) => ({
  id, module: 'inventory', scopeId: 'sede-central', codigo: `U-${id}`,
  donacionId: 'DON-CENTRAL', grupoAbo: 'O', factorRh: 'positivo',
  estado: 'disponible', fechaVencimiento: '2026-12-10', ...cambios,
});

const pedido = (id, cambios = {}) => ({
  id, module: 'requests', scopeId: 'hospital-demo', hospitalId: 'hospital-demo',
  grupoAbo: 'O', factorRh: 'positivo', prioridad: 'normal',
  cantidadSolicitada: 3, cantidadDespachada: 1, ...cambios,
});

const reserva = (id, unidadId, pedidoId, cambios = {}) => ({
  id, module: 'reservations', scopeId: 'sede-central', sedeId: 'sede-central',
  unidadId, pedidoId, estado: 'reservada', ...cambios,
});

/**
 * Datos precargados:
 * - PED-1 (Q=3, D=1) con dos reservas registradas válidas: R=2, P=0, F=2.
 * - PED-2 (Q=2, D=0) con una unidad marcada como reservada (forma de la PR de HU09).
 * - PED-3 (Q=2, D=0) con una reserva sobre una unidad ya vencida (no cuenta en R).
 */
function precargar(store) {
  store.update(db => db.records.push(
    { id: 'DON-CENTRAL', module: 'donations', scopeId: 'sede-central' },
    { id: 'DON-NORTE', module: 'donations', scopeId: 'sede-norte' },
    unidad('DISP'),
    unidad('RES1', { estado: 'reservada' }),
    unidad('RES2', { estado: 'reservada' }),
    unidad('MARC', { estado: 'reservada', pedidoId: 'PED-2' }),
    unidad('VENC', { estado: 'reservada', fechaVencimiento: '2026-11-18' }),
    unidad('DESP', { estado: 'despachada' }),
    unidad('NORTE', { scopeId: 'sede-norte', donacionId: 'DON-NORTE' }),
    pedido('PED-1', { cantidadReservada: 2, pendienteAsignar: 0, pendienteEntregar: 2, estado: 'parcial' }),
    pedido('PED-2', { cantidadSolicitada: 2, cantidadDespachada: 0, cantidadReservada: 1, pendienteAsignar: 1, pendienteEntregar: 2, estado: 'parcial' }),
    pedido('PED-3', { cantidadSolicitada: 2, cantidadDespachada: 0, cantidadReservada: 0, pendienteAsignar: 2, pendienteEntregar: 2, estado: 'pendiente' }),
    reserva('R-1', 'RES1', 'PED-1'),
    reserva('R-2', 'RES2', 'PED-1'),
    reserva('R-3', 'VENC', 'PED-3'),
  ));
}

async function entorno(t) {
  const directorio = mkdtempSync(join(tmpdir(), 'hemolink-t071-'));
  const databasePath = join(directorio, 'descartes.sqlite');
  let app;
  async function iniciar() {
    app = createApplication({ databasePath, seedDemo: true, clock: CLOCK });
    await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  }
  async function detener() {
    if (app?.server.listening) await new Promise(resolve => app.server.close(resolve));
  }
  t.after(async () => {
    await detener();
    rmSync(directorio, { recursive: true, force: true });
  });
  await iniciar();
  precargar(app.store);
  async function solicitar(ruta, { token, metodo = 'GET', cuerpo } = {}) {
    const respuesta = await fetch(`http://127.0.0.1:${app.server.address().port}${ruta}`, {
      method: metodo,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(cuerpo ? { 'Content-Type': 'application/json' } : {}),
      },
      ...(cuerpo ? { body: JSON.stringify(cuerpo) } : {}),
    });
    return { estado: respuesta.status, datos: await respuesta.json() };
  }
  async function entrar(email) {
    const { datos } = await solicitar('/api/login', {
      metodo: 'POST', cuerpo: { email, password: 'DemoHemoLink2026!' },
    });
    return datos.token;
  }
  let token = await entrar('inventario@hemolink.test');
  const descartar = (id, cuerpo = { motivo: 'Bolsa dañada' }, tk = token) =>
    solicitar(`/api/inventory/${id}/discard`, { token: tk, metodo: 'POST', cuerpo });
  const buscar = (codigo, tk = token) =>
    solicitar(`/api/inventory/lookup?codigo=${encodeURIComponent(codigo)}`, { token: tk });
  const registro = id => app.store.read().records.find(r => r.id === id);
  return {
    get store() { return app.store; },
    solicitar, entrar, descartar, buscar, registro,
    get token() { return token; },
    async reiniciar() {
      await detener();
      await iniciar();
      token = await entrar('inventario@hemolink.test');
    },
  };
}

test('UT07.1-A: unidad válida guarda motivo, autor y fecha, conserva su donación y persiste', async t => {
  const f = await entorno(t);
  const encontrada = await f.buscar('  u-disp ');
  assert.equal(encontrada.estado, 200);
  assert.equal(encontrada.datos.item.id, 'DISP');
  assert.equal(encontrada.datos.item.estado, 'disponible');
  assert.equal(encontrada.datos.item.donanteId, undefined, 'no expone datos del donante');
  const r = await f.descartar('DISP', { motivo: '  Bolsa dañada  ' });
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  assert.equal(r.datos.repetido, false);
  const { item } = r.datos;
  assert.equal(item.estado, 'descartada');
  assert.equal(item.donacionId, 'DON-CENTRAL');
  assert.equal(item.sedeId, 'sede-central');
  assert.equal(item.codigo, 'U-DISP');
  assert.deepEqual(
    { ...item.descarte, fechaRegistro: undefined },
    {
      motivo: 'Bolsa dañada', fecha: '2026-11-19', fechaRegistro: undefined,
      usuarioId: 'inventory-demo', estadoAnterior: 'disponible', reservasInvalidadas: [],
    },
  );
  assert.ok(Date.parse(item.descarte.fechaRegistro));
  assert.equal(item.historial.length, 1);
  assert.equal(item.historial[0].evento, 'descarte');
  // Excluida del stock utilizable (HU05).
  const stock = await f.solicitar('/api/inventory', { token: f.token });
  assert.equal(stock.datos.items.some(u => u.id === 'DISP'), false);
  // Origen y descarte se recuperan tras reiniciar la API.
  await f.reiniciar();
  const recargada = await f.buscar('U-DISP');
  assert.equal(recargada.datos.item.estado, 'descartada');
  assert.equal(recargada.datos.item.descarte.motivo, 'Bolsa dañada');
  assert.equal(recargada.datos.item.donacionId, 'DON-CENTRAL');
});

test('UT07.1-B: motivo vacío, sede ajena, unidad despachada y roles ajenos se rechazan sin cambios', async t => {
  const f = await entorno(t);
  const antes = JSON.stringify(f.store.read().records);

  for (const cuerpo of [{}, { motivo: '' }, { motivo: '   ' }, { motivo: 42 }, { motivo: 'x'.repeat(301) }]) {
    const r = await f.descartar('DISP', cuerpo);
    assert.equal(r.estado, 400, JSON.stringify(cuerpo));
    assert.ok(r.datos.errors?.motivo);
  }
  const ajena = await f.descartar('NORTE');
  assert.equal(ajena.estado, 404, 'otra sede responde como inexistente');
  assert.equal((await f.buscar('U-NORTE')).estado, 404);
  const despachada = await f.descartar('DESP');
  assert.equal(despachada.estado, 409);
  assert.match(despachada.datos.message, /despachada/);
  assert.equal((await f.descartar('NO-EXISTE')).estado, 404);
  assert.equal((await f.buscar('código inválido')).estado, 400);

  // Sin sesión y con roles ajenos (el servidor lo verifica aunque se llame directo).
  assert.equal((await f.solicitar('/api/inventory/DISP/discard', {metodo: 'POST', cuerpo: { motivo: 'x' },
  })).estado, 401);
  for (const email of ['hospital@hemolink.test', 'enfermeria@hemolink.test']) {
    const ajeno = await f.entrar(email);
    assert.equal((await f.descartar('DISP', { motivo: 'x' }, ajeno)).estado, 403, email);
    assert.equal((await f.buscar('U-DISP', ajeno)).estado, 403, email);
  }
  assert.equal(JSON.stringify(f.store.read().records), antes, 'ningún rechazo modifica datos');
});

test('UT07.1-C: repetir el descarte conserva el primer registro', async t => {
  const f = await entorno(t);
  const primero = await f.descartar('DISP', { motivo: 'Bolsa dañada' });
  assert.equal(primero.estado, 200);
  const repetido = await f.descartar('DISP', { motivo: 'Otro motivo' });
  assert.equal(repetido.estado, 200);
  assert.equal(repetido.datos.repetido, true);
  assert.deepEqual(repetido.datos.item.descarte, primero.datos.item.descarte);
  assert.equal(repetido.datos.item.historial.length, 1);
  assert.equal(f.registro('DISP').descarte.motivo, 'Bolsa dañada');
});

test('UT07.1-D: reserva válida pasa a inválida y libera una unidad por asignar sin aumentar despachos', async t => {
  const f = await entorno(t);
  const fichaAntes = (await f.solicitar('/api/requests/PED-1', { token: f.token })).datos.item;
  assert.equal(fichaAntes.pendienteAsignar, 0);
  const r = await f.descartar('RES1', { motivo: 'Rotura en traslado' });
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  assert.deepEqual(r.datos.reservasInvalidadas, [{ reservaId: 'R-1', pedidoId: 'PED-1' }]);
  assert.deepEqual(r.datos.pedidos, [{
    id: 'PED-1', cantidadSolicitada: 3, cantidadDespachada: 1, cantidadReservada: 1,
    pendienteAsignar: 1, pendienteEntregar: 2, estado: 'parcial',
  }]);
  // La reserva se conserva como historial, invalidada; la otra sigue activa.
  const r1 = f.registro('R-1');
  assert.equal(r1.estado, 'invalidada');
  assert.equal(r1.motivoInvalidacion, 'Unidad descartada');
  assert.equal(r1.usuarioModificacionId, 'inventory-demo');
  assert.equal(f.registro('R-2').estado, 'reservada');
  assert.equal(f.registro('RES1').descarte.estadoAnterior, 'reservada');
  const pedido = f.registro('PED-1');
  assert.equal(pedido.cantidadDespachada, 1, 'D no cambia');
  assert.equal(pedido.cantidadReservada, 1);
  assert.equal(pedido.pendienteAsignar, 1);
  // La ficha del pedido (HU06) muestra el saldo abierto tras reiniciar.
  await f.reiniciar();
  const ficha = (await f.solicitar('/api/requests/PED-1', { token: f.token })).datos.item;
  assert.equal(ficha.pendienteAsignar, 1);
  assert.equal(ficha.cantidadDespachada, 1);
});

test('UT07.1-D: también libera una unidad marcada como reservada (forma de HU09)', async t => {
  const f = await entorno(t);
  const r = await f.descartar('MARC');
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  assert.deepEqual(r.datos.reservasInvalidadas, [{ reservaId: null, pedidoId: 'PED-2' }]);
  assert.equal(r.datos.pedidos[0].cantidadReservada, 0);
  assert.equal(r.datos.pedidos[0].pendienteAsignar, 2);
  assert.equal(r.datos.pedidos[0].estado, 'pendiente');
  assert.equal(f.registro('MARC').pedidoId, 'PED-2', 'conserva el vínculo como historial');
});

test('UT07.1-D: una reserva que ya no era válida (vencida) no cambia el saldo', async t => {
  const f = await entorno(t);
  const r = await f.descartar('VENC', { motivo: 'Vencida' });
  assert.equal(r.estado, 200, JSON.stringify(r.datos));
  assert.equal(f.registro('R-3').estado, 'invalidada');
  assert.equal(r.datos.pedidos[0].pendienteAsignar, 2);
  assert.equal(r.datos.pedidos[0].cantidadReservada, 0);
});

test('T07.1 integración: un fallo de escritura conserva unidad, reserva y pedido', async t => {
  const f = await entorno(t);
  const antes = JSON.stringify(f.store.read().records);
  const original = f.store.update.bind(f.store);
  // Simula que la escritura falla después de aplicar todos los cambios en memoria.
  f.store.update = fn => original(db => {fn(db);throw new Error('fallo de escritura simulado');});
  const fallo = await f.descartar('RES1');
  f.store.update = original;
  assert.equal(fallo.estado, 500);
  assert.equal(JSON.stringify(fallo.datos).includes('simulado'), false, 'no expone detalles internos');
  assert.equal(JSON.stringify(f.store.read().records), antes);
  assert.equal(f.registro('RES1').estado, 'reservada');
  assert.equal(f.registro('R-1').estado, 'reservada');
  assert.equal(f.registro('PED-1').pendienteAsignar, 0);
  const reintento = await f.descartar('RES1');
  assert.equal(reintento.estado, 200, 'se puede reintentar');
  assert.equal(f.registro('R-1').estado, 'invalidada');
});