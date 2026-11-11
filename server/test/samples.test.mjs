import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';

async function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-samples-'));
  const databasePath = join(directory, 'db.json');
  let app, base;
  async function start(seedDemo) {
    app = createApplication({ databasePath, seedDemo });
    await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${app.server.address().port}`;
  }
  await start(true);
  app.store.update(db => {
    db.records.find(item => item.id === 'demo-inventory').donacionId = 'DON001';
    db.records.push(
    { id: 'DON001', module: 'donations', donanteId: 'demo-donors', scopeId: 'sede-central' },
    { id: 'DON_AJENA', module: 'donations', donanteId: 'D_AJENO', scopeId: 'otra-sede' },
    { id: 'D_AJENO', module: 'donors', scopeId: 'otra-sede' },
    { id: 'DON_SIN_DONANTE', module: 'donations', donanteId: 'no-existe', scopeId: 'sede-central' },
    );
  });
  t.after(async () => {
    await new Promise(resolve => app.server.close(resolve));
    rmSync(directory, { recursive: true, force: true });
  });
  const f = {
    get store() { return app.store; },
    async restart() {
      await new Promise(resolve => app.server.close(resolve));
      await start(false);
    },
    async request(path, { token, body, method = 'GET' } = {}) {
      const response = await fetch(base + path, {
        method, headers: {
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      return { status: response.status, data: await response.json() };
    },
    async login(role = 'enfermeria') {
      const r = await this.request('/api/login', { method: 'POST', body: {
        email: `${role}@hemolink.test`, password: 'DemoHemoLink2026!',
      } });
      assert.equal(r.status, 200);
      return r.data.token;
    },
  };
  return f;
}

test('PR17: persiste muestra con origen y responsable del servidor; consulta tras reinicio sin mezclar inventario', async t => {
  const f = await fixture(t);
  const token = await f.login();
  const inventoryToken = await f.login('inventario');
  const stock = await f.request('/api/inventory', { token: inventoryToken });
  assert.equal(stock.data.items[0].donacionId, 'DON001');
  const r = await f.request('/api/samples', { token, method: 'POST', body: {
    codigo: ' m-001 ', donacionId: ' DON001 ',
    scopeId: 'otra-sede', donanteId: 'D_FALSO', responsableId: 'FALSO', module: 'inventory',
  } });
  assert.equal(r.status, 201);
  assert.equal(r.data.item.codigo, 'M-001');
  assert.equal(r.data.item.donanteId, 'demo-donors');
  assert.equal(r.data.item.scopeId, 'sede-central');
  assert.equal(r.data.item.responsableId, 'nursing-demo');
  assert.equal(r.data.item.module, 'samples');
  await f.restart();
  const ficha = await f.request(`/api/samples/${r.data.item.id}`, { token });
  assert.deepEqual(ficha.data.item, r.data.item);
  const muestras = await f.request('/api/samples?donacionId=DON001', { token });
  assert.deepEqual(muestras.data.items, [r.data.item]);
  assert.deepEqual(await f.request('/api/inventory', { token: inventoryToken }), stock);
  const duplicada = await f.request('/api/samples', { token, method: 'POST', body: { codigo: 'm-001', donacionId: 'DON001' } });
  assert.equal(duplicada.status, 409);
  assert.equal(f.store.read().records.filter(i => i.module === 'samples').length, 1);
});

test('PR17: rechaza duplicados concurrentes, origen inexistente o ajeno y datos vacíos sin huérfanos', async t => {
  const f = await fixture(t);
  const token = await f.login();
  const antes = f.store.read().records;
  for (const [donacionId, codigo, status] of [
    ['DON-INEXISTENTE', 'M001', 404], ['DON_AJENA', 'M001', 404],
    ['DON_SIN_DONANTE', 'M001', 404], ['', 'M001', 400], ['DON001', ' ', 400],
  ]) {
    assert.equal((await f.request('/api/samples', { token, method: 'POST', body: { donacionId, codigo } })).status, status);
  }
  assert.deepEqual(f.store.read().records, antes);
  const resultados = await Promise.all(['M001', ' m001 '].map(codigo => f.request('/api/samples', {
    token, method: 'POST', body: { codigo, donacionId: 'DON001' },
  })));
  assert.deepEqual(resultados.map(r => r.status).sort(), [201, 409]);
  assert.equal(f.store.read().records.filter(i => i.module === 'samples').length, 1);
});

test('PR17: autorización real, aislamiento de sede y fallo de escritura conservan registros', async t => {
  const f = await fixture(t);
  const token = await f.login();
  const guardada = await f.request('/api/samples', { token, method: 'POST', body: { codigo: 'M001', donacionId: 'DON001' } });
  f.store.update(db => db.records.push({ ...guardada.data.item, id: 'M_AJENA', codigo: 'AJENA', scopeId: 'otra-sede' }));
  const antes = f.store.read().records;
  for (const [otroToken, status] of [[undefined, 401], [await f.login('hospital'), 403], [await f.login('inventario'), 403]]) {
    for (const path of ['/api/samples', `/api/samples/${guardada.data.item.id}`, '/api/samples?donacionId=DON001']) {
      const r = await f.request(path, { token: otroToken });
      assert.equal(r.status, status);
      assert.equal(r.data.items, undefined);
      assert.equal(r.data.item, undefined);
    }
    assert.equal((await f.request('/api/samples', { token: otroToken, method: 'POST', body: { codigo: 'M002', donacionId: 'DON001' } })).status, status);
  }
  assert.equal((await f.request('/api/samples/M_AJENA', { token })).status, 404);
  assert.equal((await f.request('/api/samples?donacionId=DON_AJENA', { token })).status, 404);
  assert.equal((await f.request('/api/samples', { token })).data.items.length, 1);
  const update = f.store.update;
  f.store.update = () => { throw new Error('Disco no disponible'); };
  try {
    assert.equal((await f.request('/api/samples', { token, method: 'POST', body: { codigo: 'M002', donacionId: 'DON001' } })).status, 500);
  } finally { f.store.update = update; }
  assert.deepEqual(f.store.read().records, antes);
});
