import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';

const password = 'DemoHemoLink2026!';

async function fixture(t, options = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-'));
  const databasePath = join(directory, 'database.json');
  let now = Date.now();
  let application;
  let base;
  async function start(seedDemo) {
    application = createApplication({ databasePath, seedDemo, clock: () => now, ...options });
    await new Promise(resolve => application.server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${application.server.address().port}`;
  }
  await start(true);
  t.after(async () => {
    await new Promise(resolve => application.server.close(resolve));
    rmSync(directory, { recursive: true, force: true });
  });
  return {
    databasePath,
    get store() { return application.store; },
    advance(ms) { now += ms; },
    async restart() {
      await new Promise(resolve => application.server.close(resolve));
      await start(false);
    },
    async request(path, { token, body, method = 'GET', origin } = {}) {
      const response = await fetch(base + path, {
        method,
        headers: {
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(body ? { 'Content-Type': 'application/json' } : {}),
          ...(origin ? { Origin: origin } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      return { status: response.status, data: await response.json() };
    },
    async login(email = 'enfermeria@hemolink.test', secret = password) {
      return this.request('/api/login', { method: 'POST', body: { email, password: secret } });
    },
  };
}

test('UT01.1-A: credenciales verificadas crean sesión con rol y sede', async t => {
  const f = await fixture(t);
  const result = await f.login(' ENFERMERIA@HEMOLINK.TEST ');
  assert.equal(result.status, 200);
  assert.equal(result.data.user.role, 'nursing');
  assert.equal(result.data.user.siteId, 'sede-central');
  assert.deepEqual(result.data.user.modules, ['donors', 'evaluations', 'donations']);
  assert.equal((await f.request('/api/me', { token: result.data.token })).status, 200);
  const file = readFileSync(f.databasePath, 'utf8');
  assert.ok(!file.includes(password));
  assert.ok(!file.includes(result.data.token));
  assert.ok(!JSON.stringify(result.data.user).includes('password'));
});

test('UT01.1-B: contraseña incorrecta, usuario inexistente y no verificado se rechazan', async t => {
  const f = await fixture(t);
  for (const [email, secret] of [
    ['enfermeria@hemolink.test', 'incorrecta'],
    ['ausente@hemolink.test', password],
    ['sin.verificar@hemolink.test', password],
  ]) {
    const result = await f.login(email, secret);
    assert.equal(result.status, 401);
    assert.equal(result.data.token, undefined);
  }
  assert.equal(f.store.read().sessions.length, 0);
});

test('UT01.1-C: servidor bloquea ausencia, falsificación, expiración y cierre de sesión', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/api/donors')).status, 401);
  assert.equal((await f.request('/api/donors', { token: 'inventado' })).status, 401);
  const { data } = await f.login();
  assert.equal((await f.request('/api/donors', { token: data.token })).status, 200);
  assert.equal((await f.request('/api/logout', { method: 'POST', token: data.token })).status, 200);
  assert.equal((await f.request('/api/donors', { token: data.token })).status, 401);
  const next = await f.login();
  f.advance(8 * 60 * 60 * 1000 + 1);
  assert.equal((await f.request('/api/me', { token: next.data.token })).status, 401);
});

test('UT01.1-D: roles y asociaciones se comprueban en cada operación', async t => {
  const f = await fixture(t);
  for (const [email, allowed, denied] of [
    ['inventario@hemolink.test', 'inventory', 'donors'],
    ['hospital@hemolink.test', 'requests', 'donors'],
    ['enfermeria@hemolink.test', 'donors', 'inventory'],
  ]) {
    const { data } = await f.login(email);
    assert.equal((await f.request(`/api/${allowed}`, { token: data.token })).status, 200);
    assert.equal((await f.request(`/api/${denied}`, { token: data.token })).status, 403);
  }
  const { data } = await f.login();
  f.store.update(db => {
    db.records.push({ id: 'ajeno', module: 'donors', scopeId: 'otra-sede', label: 'No visible' });
  });
  const result = await f.request('/api/donors?siteId=otra-sede&role=hospital', { token: data.token });
  assert.ok(!result.data.items.some(item => item.id === 'ajeno'));
  f.store.update(db => { db.users.find(user => user.id === data.user.id).isVerified = false; });
  assert.equal((await f.request('/api/donors', { token: data.token })).status, 401);
});

test('JSON: cuentas, sesión y datos sobreviven a reiniciar sin duplicar semillas', async t => {
  const f = await fixture(t);
  const { data } = await f.login();
  const original = await f.request('/api/donors', { token: data.token });
  assert.ok(original.data.items.length > 0);
  await f.restart();
  assert.deepEqual((await f.request('/api/donors', { token: data.token })).data, original.data);
  assert.equal(f.store.read().users.length, 4);
  assert.equal((await f.login()).status, 200);
});

test('API: limita intentos, valida JSON y rechaza orígenes ajenos', async t => {
  const f = await fixture(t, { maxLoginAttempts: 2 });
  assert.equal((await f.login('nadie', 'incorrecta')).status, 401);
  assert.equal((await f.login('nadie', 'incorrecta')).status, 401);
  assert.equal((await f.login()).status, 429);
  f.advance(15 * 60 * 1000 + 1);
  assert.equal((await f.login()).status, 200);
  assert.equal((await f.request('/api/login', { method: 'POST', body: { email: [] } })).status, 400);
  assert.equal((await f.request('/api/me', { origin: 'https://ajeno.test' })).status, 403);
});
