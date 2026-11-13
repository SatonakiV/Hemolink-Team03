import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openStore } from '../src/store.mjs';
import { seedDemoData } from '../src/auth.mjs';

const appUrl = new URL('../src/app.mjs', import.meta.url).href;

async function startServer(t, path) {
  const worker = spawn(process.execPath, ['--input-type=module', '-e', `
    import {createApplication} from ${JSON.stringify(appUrl)};
    const {server}=createApplication({databasePath:process.argv[1],clock:()=>Date.parse('2026-11-09T15:00:00Z')});
    server.listen(0,'127.0.0.1',()=>process.send({port:server.address().port}));
    process.on('message',message=>{if(message==='stop')server.close(()=>process.disconnect());});`, path], {
    stdio: ['ignore', 'ignore', 'pipe', 'ipc'], windowsHide: true,
  });
  let stderr = '';
  worker.stderr.on('data', chunk => { stderr += chunk; });
  t.after(() => worker.kill('SIGKILL'));
  const done = new Promise((resolve, reject) => {
    worker.once('error', reject);
    worker.once('close', code => resolve({ code, stderr }));
  });
  const port = await new Promise((resolve, reject) => {
    worker.once('error', reject);
    worker.once('exit', code => reject(new Error(`Servidor terminó (${code}): ${stderr}`)));
    worker.once('message', message => resolve(message.port));
  });
  return {
    async request(path, { token, method = 'GET', body } = {}) {
      const response = await fetch(`http://127.0.0.1:${port}${path}`, {
        method, headers: {
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        }, ...(body ? { body: JSON.stringify(body) } : {}),
      });
      return { status: response.status, data: await response.json() };
    },
    async stop() {
      worker.send('stop');
      const result = await done;
      assert.equal(result.code, 0, result.stderr);
    },
  };
}

for (const extension of ['json', 'sqlite']) test(`${extension}: dos servidores comparten sesiones, unicidad e idempotencia sin duplicar registros`, { timeout: 20000 }, async t => {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-multiprocess-api-'));
  const path = join(directory, `db.${extension}`);
  let store;
  t.after(() => { store?.close(); rmSync(directory, { recursive: true, force: true }); });
  store = openStore(path);
  seedDemoData(store, 'test-password');
  const [a, b] = await Promise.all([startServer(t, path), startServer(t, path)]);
  const login = await a.request('/api/login', {
    method: 'POST', body: { email: 'enfermeria@hemolink.test', password: 'test-password' },
  });
  assert.equal(login.status, 200);
  const token = login.data.token;
  assert.equal((await b.request('/api/me', { token })).status, 200);
  const donor = {
    rut: '12345678-5', nombre: 'Persona ficticia', fechaNacimiento: '1990-01-01',
    pesoKg: 70, grupoAbo: 'O', factorRh: 'positivo', telefono: '900000000',
  };
  const donors = await Promise.all([a, b].map(server => server.request('/api/donors', { token, method: 'POST', body: donor })));
  assert.deepEqual(donors.map(result => result.status).sort(), [201, 409]);
  const donorId = donors.find(result => result.status === 201).data.item.id;
  assert.equal((await b.request(`/api/donors/${donorId}`, { token })).data.item.id, donorId);
  const evaluation = await a.request('/api/evaluations', { token, method: 'POST', body: {
    id: 'E_SHARED', donanteId: donorId, resultado: 'apto', fechaEvaluacion: '2026-11-09', fechaFinVigencia: '2026-11-20',
  } });
  assert.equal(evaluation.status, 201);
  const body = {
    claveConfirmacion: 'confirmation-shared-0001', donanteId: donorId, evaluacionId: 'E_SHARED',
    fechaExtraccion: '2026-11-09', volumenMl: 450, unidades: [{ codigo: 'SHARED-UNIT' }],
  };
  const donations = await Promise.all([a, b].map(server => server.request('/api/donations', { token, method: 'POST', body })));
  assert.deepEqual(donations.map(result => result.status).sort(), [200, 201]);
  assert.equal(donations[0].data.item.id, donations[1].data.item.id);
  assert.equal(store.read({ records: { module: 'donations' } }).records.length, 1);
  assert.equal(store.read({ records: { codigo: 'SHARED-UNIT' } }).records.length, 1);
  assert.equal(store.verify({ references: true }).ok, true);
  assert.equal((await b.request('/api/logout', { token, method: 'POST' })).status, 200);
  assert.equal((await a.request('/api/me', { token })).status, 401);
  await Promise.all([a.stop(), b.stop()]);
});
