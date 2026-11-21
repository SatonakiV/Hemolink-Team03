import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';

test('UT08.1-A/B: la API consulta stock elegible por sede y ABO/Rh en SQLite', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-inventory-'));
  const { server, store } = createApplication({
    databasePath: join(directory, 'stock.sqlite'),
    seedDemo: true,
    clock: () => new Date(2026, 10, 19, 12).getTime(),
  });
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    rmSync(directory, { recursive: true, force: true });
  });

  const unidad = (id, cambios = {}) => ({
    id, module: 'inventory', scopeId: 'sede-central', codigo: `U-${id}`,
    donacionId: 'DON-CENTRAL', grupoAbo: 'O', factorRh: 'positivo',
    estado: 'disponible', fechaVencimiento: '2026-11-21', ...cambios,
  });
  store.update(db => db.records.push(
    { id: 'DON-CENTRAL', module: 'donations', scopeId: 'sede-central', donanteId: 'demo-donors' },
    { id: 'DON-NORTE', module: 'donations', scopeId: 'sede-norte' },
    unidad('B'),
    unidad('A', { donanteId: 'demo-donors', label: 'Dato fuera de la proyección' }),
    unidad('C', { fechaVencimiento: '2026-11-20' }),
    unidad('NORTE', { scopeId: 'sede-norte', donacionId: 'DON-NORTE' }),
    unidad('ABO', { grupoAbo: 'A' }),
    unidad('RH', { factorRh: 'negativo' }),
    unidad('HOY', { fechaVencimiento: '2026-11-19' }),
    unidad('VENCIDA', { fechaVencimiento: '2026-11-18' }),
    unidad('FECHA-INVALIDA', { fechaVencimiento: '2026-11-31' }),
    unidad('INCOMPLETA', { grupoAbo: null }),
    unidad('DESCARTADA', { estado: 'descartada' }),
    unidad('RESERVADA', { estado: 'reservada' }),
    unidad('DESPACHADA', { estado: 'despachada' }),
    unidad('MUESTRA', { module: 'samples', donanteId: 'demo-donors' }),
  ));

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/`;
  async function login(role) {
    const response = await fetch(base + 'login', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: `${role}@hemolink.test`, password: 'DemoHemoLink2026!' }),
    });
    assert.equal(response.status, 200);
    return (await response.json()).token;
  }
  const token = await login('inventario');
  async function stock(filtros = '') {
    const response = await fetch(base + 'inventory' + filtros, {
      headers: { Authorization: `Bearer ${token}` },
    });
    return { status: response.status, data: await response.json() };
  }

  const global = await stock();
  assert.equal(global.status, 200);
  assert.deepEqual(global.data.items.map(({ id }) => id), ['C', 'A', 'ABO', 'B', 'NORTE', 'RH']);
  assert.equal(global.data.total, 6);

  const filtrado = await stock('?sedeId=sede-central&grupoAbo=o&factorRh=Positivo');
  assert.equal(filtrado.status, 200);
  assert.deepEqual(filtrado.data.items.map(({ id }) => id), ['C', 'A', 'B']);
  assert.equal(filtrado.data.total, 3);
  assert.deepEqual(filtrado.data.items[1], {
    id: 'A', sedeId: 'sede-central', codigo: 'U-A', donacionId: 'DON-CENTRAL', grupoAbo: 'O',
    factorRh: 'positivo', estado: 'disponible', fechaVencimiento: '2026-11-21', label: 'U-A · O+',
  });
  const norte = await stock('?sedeId=sede-norte');
  assert.equal(norte.data.items[0].sedeId, 'sede-norte');
  assert.equal(norte.data.total, 1);

  store.update(db => { db.records.find(({ id }) => id === 'NORTE').estado = 'reservada'; });
  assert.deepEqual(await stock('?sedeId=sede-norte'), { status: 200, data: { items: [], total: 0 } });

  for (const filtros of ['?sedeId=', '?grupoAbo=Z', '?factorRh=indefinido']) {
    const invalido = await stock(filtros);
    assert.equal(invalido.status, 400);
    assert.equal(invalido.data.total, undefined);
  }
  const hospital = await login('hospital');
  assert.equal((await fetch(base + 'inventory')).status, 401);
  assert.equal((await fetch(base + 'inventory', {
    headers: { Authorization: `Bearer ${hospital}` },
  })).status, 403);

  const read = store.read.bind(store);
  t.mock.method(store, 'read', query => {
    if (query?.records?.module === 'inventory') throw new Error('Fallo de lectura simulado');
    return read(query);
  });
  const fallo = await stock();
  assert.equal(fallo.status, 500);
  assert.equal(fallo.data.total, undefined);
});
