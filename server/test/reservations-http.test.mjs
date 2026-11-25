import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { createApplication } from '../src/app.mjs';

test('HU08 confirma FEFO entre sedes, rechaza conflictos y conserva el resultado en SQLite', async t => {
  const carpeta = mkdtempSync(join(tmpdir(), 'hemolink-reserva-'));
  const databasePath = join(carpeta, 'reservas.sqlite');
  const clock = () => Date.parse('2026-11-24T15:00:00.000Z');
  let app;
  let baseUrl;

  async function iniciar(seedDemo) {
    app = createApplication({ databasePath, clock, seedDemo });
    await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
    baseUrl = `http://127.0.0.1:${app.server.address().port}`;
  }
  const cerrar = () => new Promise(resolve => app.server.close(resolve));
  t.after(async () => {
    if (app?.server.listening) await cerrar();
    rmSync(carpeta, { recursive: true, force: true });
  });

  async function api(path, token, body) {
    const response = await fetch(baseUrl + '/api' + path, {
      method: body ? 'POST' : 'GET',
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, data: await response.json() };
  }

  async function login(nombre) {
    const resultado = await api('/login', null, {
      email: `${nombre}@hemolink.test`, password: 'DemoHemoLink2026!',
    });
    assert.equal(resultado.status, 200);
    return resultado.data.token;
  }

  await iniciar(true);
  const [inventario, colega, hospital] = await Promise.all([
    login('inventario'), login('inventario'), login('hospital'),
  ]);
  const crear = async cantidadSolicitada => {
    const { status, data } = await api('/requests', hospital, {
      grupoAbo: 'O', factorRh: 'negativo', cantidadSolicitada, prioridad: 'normal',
    });
    assert.equal(status, 201);
    return `/requests/${data.item.id}/reservations`;
  };
  const primero = await crear(2);
  const segundo = await crear(2);
  const parcial = await crear(3);
  const idParcial = parcial.split('/')[2];
  const unidad = (id, scopeId, fechaVencimiento, factorRh = 'negativo') => ({
    id, module: 'inventory', scopeId, codigo: id, donacionId: `don-${scopeId}`,
    grupoAbo: 'O', factorRh, estado: 'disponible', fechaVencimiento,
  });
  app.store.update(db => {
    db.records.find(record => record.id === idParcial).cantidadDespachada = 1;
    db.records.push(
      { id: 'don-sede-central', module: 'donations', scopeId: 'sede-central' },
      { id: 'don-sede-norte', module: 'donations', scopeId: 'sede-norte' },
      unidad('u-b', 'sede-central', '2026-11-25'),
      unidad('u-a', 'sede-norte', '2026-11-25'),
      unidad('u-c', 'sede-central', '2026-11-26'),
      unidad('u-hoy', 'sede-norte', '2026-11-24'),
      unidad('u-otro-rh', 'sede-norte', '2026-11-25', 'positivo'),
    );
  });

  assert.equal((await api(primero, hospital)).status, 403);
  const original = await api(primero, inventario);
  const competidora = await api(segundo, colega);
  const { propuesta } = original.data;
  const ubicaciones = unidades => unidades.map(({ codigo, sedeId }) => [codigo, sedeId]);
  assert.equal(original.status, 200);
  assert.equal(propuesta.stockElegible, 3);
  assert.deepEqual(ubicaciones(propuesta.unidades), [['u-a', 'sede-norte'], ['u-b', 'sede-central']]);
  assert.equal((await api(primero, hospital, { version: propuesta.version })).status, 403);
  assert.equal((await api(primero, inventario, { version: '' })).status, 400);

  // Capturar una segunda propuesta para el mismo saldo, con unidades diferentes.
  app.store.update(db => {
    db.records.push(
      unidad('u-nueva-a', 'sede-central', '2026-11-25'),
      unidad('u-nueva-b', 'sede-norte', '2026-11-25'),
    );
    db.records.find(record => record.id === 'u-a').estado = 'descartada';
    db.records.find(record => record.id === 'u-b').estado = 'descartada';
  });
  const vigente = await api(primero, colega);
  const loteVigente = ubicaciones(vigente.data.propuesta.unidades);
  assert.deepEqual(loteVigente, [['u-nueva-a', 'sede-central'], ['u-nueva-b', 'sede-norte']]);

  const [antigua, actual, otroPedido] = await Promise.all([
    api(primero, inventario, { version: propuesta.version }),
    api(primero, colega, { version: vigente.data.propuesta.version }),
    api(segundo, colega, { version: competidora.data.propuesta.version }),
  ]);
  assert.deepEqual([antigua.status, actual.status, otroPedido.status], [409, 200, 409]);
  assert.equal(actual.data.saldos.estado, 'reservado');
  assert.equal(actual.data.saldos.pendienteAsignar, 0);
  assert.equal(actual.data.saldos.pendienteEntregar, 2);
  assert.deepEqual(ubicaciones(actual.data.reservas), loteVigente);
  assert.equal(actual.data.propuesta.estado, 'sin_saldo');

  const stock = await api('/inventory', inventario);
  assert.deepEqual(stock.data.items.map(x => x.id), ['u-otro-rh', 'u-c']);
  const sinStock = await api(segundo, colega);
  assert.equal(sinStock.data.saldos.pendienteAsignar, 2);
  assert.equal(sinStock.data.propuesta.estado, 'stock_insuficiente');
  assert.equal(sinStock.data.propuesta.faltante, 1);
  assert.equal(sinStock.data.propuesta.version, null);

  app.store.update(db => {
    db.records.push(unidad('u-d', 'sede-norte', '2026-11-27'));
  });
  const p = await api(parcial, inventario);
  const s = await api(segundo, colega);
  const resultados = await Promise.all([
    api(parcial, inventario, { version: p.data.propuesta.version }),
    api(segundo, colega, { version: s.data.propuesta.version }),
  ]);
  assert.deepEqual(resultados.map(r => r.status).sort(), [200, 409]);
  if (resultados[0].status === 200) {
    assert.equal(resultados[0].data.saldos.estado, 'parcial');
    assert.equal(resultados[0].data.saldos.pendienteEntregar, 2);
  } else {
    app.store.update(db => {
      db.records.push(
        unidad('u-e', 'sede-norte', '2026-11-28'),
        unidad('u-f', 'sede-central', '2026-11-29'),
      );
    });
    const nueva = await api(parcial, inventario);
    const confirmada = await api(parcial, inventario, { version: nueva.data.propuesta.version });
    assert.equal(confirmada.status, 200);
    assert.equal(confirmada.data.saldos.estado, 'parcial');
    assert.equal(confirmada.data.saldos.pendienteEntregar, 2);
  }

  await cerrar();
  await iniciar(false);
  const persistida = await api(primero, inventario);
  assert.equal(persistida.status, 200);
  assert.deepEqual(persistida.data.saldos, actual.data.saldos);
  assert.deepEqual(persistida.data.reservas, actual.data.reservas);
  assert.equal((await api(primero, inventario, { version: vigente.data.propuesta.version })).status, 409);
  assert.equal(app.store.read().records.filter(item => item.module === 'notices').length, 0);
});
