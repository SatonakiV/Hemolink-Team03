import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync, rmSync, readFileSync, writeFileSync, appendFileSync, existsSync, readdirSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { SqliteStore } from '../src/sqlite-store.mjs';
import { JsonStore } from '../src/json-store.mjs';
import { openStore } from '../src/store.mjs';
import { seedDemoData } from '../src/auth.mjs';

const moduleUrl = new URL('../src/sqlite-store.mjs', import.meta.url).href;
const donor = id => ({ id, module: 'donors', scopeId: 'sede', nombre: `Persona ${id}` });

function fixture(t, options) {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-sqlite-'));
  const path = join(directory, 'db.sqlite');
  const stores = [];
  t.after(() => {
    for (const store of stores) store.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const open = (path, options) => { const store = new SqliteStore(path, options); stores.push(store); return store; };
  return { directory, path, open, store: open(path, options) };
}

function worker(source, args) {
  const process = spawn(globalThis.process.execPath, ['--input-type=module', '-e', source, ...args], {
    stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
  });
  let stderr = '', stdout = '';
  process.stdout.on('data', chunk => { stdout += chunk; });
  process.stderr.on('data', chunk => { stderr += chunk; });
  const done = new Promise((resolve, reject) => {
    process.once('error', reject);
    process.once('close', (code, signal) => resolve({ code, signal, stderr, stdout }));
  });
  return { process, done };
}

async function ready(process) {
  for await (const chunk of process.stdout) if (chunk.toString().includes('READY')) return;
  throw new Error('El proceso no alcanzó el punto de prueba.');
}

test('SQLite: persiste JSON, campos adicionales y orden; lecturas y callbacks quedan aislados', t => {
  const { store, path, open } = fixture(t);
  let leaked;
  store.update(db => { db.extra = { enabled: true }; db.records.push(donor('A'), donor('B')); leaked = db; });
  leaked.records.length = 0;
  const copy = store.read(); copy.extra.enabled = false;
  store.update(db => { db.records[0].nombre = 'Corregida'; db.records.reverse(); });
  assert.deepEqual(open(path).read(), store.read());
  assert.deepEqual(store.read().records.map(r => r.id), ['B', 'A']);
  assert.equal(store.read().extra.enabled, true);
  assert.equal(store.verify().sequence, 2);
});

test('SQLite: rollback, funciones async, promesas, anidamiento y no-op', async t => {
  const { store } = fixture(t);
  store.update(db => db.records.push(donor('A')));
  const previous = store.read();
  assert.throws(() => store.update(db => { db.records.length = 0; throw new Error('cancelado'); }), /cancelado/);
  assert.throws(() => store.update(async () => {}), /síncrona/);
  assert.throws(() => store.update(db => { db.records.push(donor('B')); return Promise.resolve(); }), /promesa/);
  assert.throws(() => store.update(() => store.update(() => {})), /anidadas/);
  assert.throws(() => store.update(db => { db.records[0].pesoKg = NaN; }));
  store.update(() => {});
  await Promise.resolve();
  assert.deepEqual(store.read(), previous);
  assert.equal(store.verify().sequence, 1);
});

test('SQLite: consultas parametrizadas equivalen a filtrar JSON y distinguen null de ausente', t => {
  const { store } = fixture(t);
  store.update(db => db.records.push(donor('A'), { ...donor('B'), scopeId: 'otra', donanteId: null }));
  assert.deepEqual(store.read({ records: { scopeId: 'sede', id: 'A' } }).records, [donor('A')]);
  assert.equal(store.read({ records: { id: "' OR 1=1 --" } }).records.length, 0);
  assert.deepEqual(store.read({ records: { donanteId: null } }).records.map(r => r.id), ['B']);
  assert.deepEqual(store.read({ records: { donanteId: undefined } }).records.map(r => r.id), ['A']);
  assert.throws(() => store.read({ records: { 'id) OR 1=1 --': 'A' } }));
  assert.throws(() => store.read({ unknown: {} }));
});

test('SQLite: restricciones únicas de RUT y correos se cumplen sin depender de la API', t => {
  const { store } = fixture(t);
  store.update(db => db.records.push({ ...donor('A'), rut: '12.345.678-5' }));
  const before = store.read();
  assert.throws(() => store.update(db => db.records.push({ ...donor('B'), rut: '0123456785' })), { status: 409 });
  assert.deepEqual(store.read(), before);
  store.update(db => db.users.push({ id: 'u1', email: 'user@test' }));
  assert.throws(() => store.update(db => db.users.push({ id: 'u2', email: ' USER@test ' })), { status: 409 });
});

function chain(db) {
  db.records.push(donor('A'), donor('B'),
    { id: 'E', module: 'evaluations', scopeId: 'sede', donanteId: 'A', resultado: 'apto' },
    { id: 'D', module: 'donations', scopeId: 'sede', donanteId: 'A', evaluacionId: 'E', claveConfirmacion: 'confirmation' },
    { id: 'U', module: 'inventory', scopeId: 'sede', donacionId: 'D', codigo: 'UNIT' },
    { id: 'S', module: 'samples', scopeId: 'sede', donacionId: 'D', donanteId: 'A', codigo: 'SAMPLE' },
  );
}

test('SQLite: donación, evaluación, muestra y unidad son atómicas y mantienen referencias', t => {
  const { store } = fixture(t);
  store.update(chain);
  const before = store.read();
  const invalid = [
    db => { db.records.find(r => r.id === 'E').scopeId = 'otra'; },
    db => { db.records.find(r => r.id === 'D').donanteId = 'B'; },
    db => { db.records.find(r => r.id === 'S').donanteId = 'B'; },
    db => { db.records.find(r => r.id === 'U').donacionId = 'absent'; },
    db => { db.records = db.records.filter(r => r.id !== 'A'); },
    db => { db.records.find(r => r.id === 'E').responsableId = 'absent'; },
    db => { db.records.push({ ...db.records.find(r => r.id === 'U'), id: 'U2', codigo: ' unit ' }); },
    db => { db.records.push({ ...db.records.find(r => r.id === 'S'), id: 'S2', codigo: 'sample' }); },
    db => { db.records.push({ ...db.records.find(r => r.id === 'D'), id: 'D2' }); },
  ];
  for (const change of invalid) {
    assert.throws(() => store.update(change), { status: 409 });
    assert.deepEqual(store.read(), before);
  }
  assert.equal(store.verify({ references: true }).ok, true);
});

test('SQLite: FK diferidas admiten hijos antes de padres e intercambios de claves únicas', t => {
  const { store } = fixture(t);
  store.update(db => { chain(db); db.records.reverse(); });
  store.update(db => db.records.push({ id: 'U2', module: 'inventory', scopeId: 'sede', donacionId: 'D', codigo: 'UNIT2' }));
  store.update(db => {
    db.records.find(r => r.id === 'U').codigo = 'UNIT2';
    db.records.find(r => r.id === 'U2').codigo = 'UNIT';
  });
  assert.equal(store.verify().ok, true);
});

test('SQLite: sesión requiere usuario existente; eliminar usuario con sesión hace rollback', t => {
  const { store } = fixture(t);
  seedDemoData(store, 'test');
  store.update(db => db.sessions.push({ userId: 'nursing-demo', tokenHash: 'a'.repeat(64), expiresAt: 1000 }));
  assert.throws(() => store.update(db => { db.users = db.users.filter(user => user.id !== 'nursing-demo'); }));
  assert.equal(store.read().sessions.length, 1);
  assert.equal(store.verify().ok, true);
});

test('SQLite: importación incluye diario pendiente y deja intactos ambos archivos JSON', t => {
  const { store, directory, open } = fixture(t);
  store.close();
  const jsonPath = join(directory, 'legacy.json');
  const json = new JsonStore(jsonPath);
  seedDemoData(json, 'test');
  json.update(chain);
  // Una cola interrumpida no forma parte del estado confirmado ni se repara en
  // el original durante la importación.
  appendFileSync(`${jsonPath}.wal`, '{"partial":');
  const original = readFileSync(jsonPath), wal = readFileSync(`${jsonPath}.wal`);
  const imported = open(join(directory, 'imported.sqlite'), { importJsonPath: jsonPath });
  assert.equal(imported.read().records.length, 10);
  assert.deepEqual(readFileSync(jsonPath), original);
  assert.deepEqual(readFileSync(`${jsonPath}.wal`), wal);
  imported.update(db => db.records.push(donor('C')));
  const reopened = open(join(directory, 'imported.sqlite'), { importJsonPath: jsonPath });
  assert.equal(reopened.read().records.length, 11); // No reimporta ni elimina cambios.
});

test('SQLite: importación fallida revierte esquema y datos; permite reintentar sin perder JSON', t => {
  const { directory, open } = fixture(t);
  const source = join(directory, 'bad.json');
  const target = join(directory, 'retry.sqlite');
  const data = { version: 1, users: [], sessions: [], records: [
    { id: 'E', module: 'evaluations', scopeId: 'sede', donanteId: 'missing' },
  ] };
  writeFileSync(source, JSON.stringify(data));
  const original = readFileSync(source);
  assert.throws(() => open(target, { importJsonPath: source }), { status: 409 });
  assert.deepEqual(readFileSync(source), original);
  const inspection = new DatabaseSync(target);
  assert.equal(inspection.prepare('PRAGMA user_version').get().user_version, 0);
  inspection.close();
  data.records.push(donor('missing'));
  writeFileSync(source, JSON.stringify(data));
  assert.equal(open(target, { importJsonPath: source }).read().records.length, 2);
});

test('SQLite: exportación JSON permite volver al modo JSON sin perder campos ni orden', t => {
  const { store, directory, open } = fixture(t);
  seedDemoData(store, 'test');
  store.update(chain);
  store.update(db => { db.extra = { text: 'Ñandú 🩸' }; });
  const path = join(directory, 'export.json');
  store.exportJsonTo(path);
  const json = new JsonStore(path);
  assert.deepEqual(json.read(), store.read());
  json.update(db => db.records.push(donor('C')));
  assert.equal(json.read().records.length, store.read().records.length + 1);
  assert.throws(() => store.exportJsonTo(path), { code: 'EEXIST' });
  const imported = open(join(directory, 'roundtrip.sqlite'), { importJsonPath: path });
  assert.deepEqual(imported.read(), json.read());
});

test('SQLite: respaldo autónomo consistente no sobrescribe archivos y protege archivos activos', t => {
  const { store, directory, open, path } = fixture(t);
  store.update(chain);
  const backup = join(directory, 'backup.sqlite');
  store.backupTo(backup);
  assert.deepEqual(open(backup).read(), store.read());
  store.update(db => db.records.push(donor('C')));
  assert.equal(open(backup).read().records.length, 6);
  assert.throws(() => store.backupTo(backup), { code: 'EEXIST' });
  for (const target of [path, `${path}-wal`, `${path}-shm`]) {
    assert.throws(() => store.backupTo(target));
    assert.throws(() => store.exportJsonTo(target));
  }
  assert.equal(readdirSync(directory).some(name => name.endsWith('.tmp')), false);
});

test('SQLite: rechaza archivos ajenos, versión futura y destino existente sin sobrescribirlos', t => {
  const { directory, path } = fixture(t);
  assert.throws(() => new SqliteStore(path, { requireNew: true }), { code: 'EEXIST' });
  const foreign = join(directory, 'foreign.sqlite');
  const db = new DatabaseSync(foreign);
  db.exec('CREATE TABLE other(value TEXT); INSERT INTO other VALUES (\'preserved\')'); db.close();
  assert.throws(() => new SqliteStore(foreign), /ajena/);
  const reader = new DatabaseSync(foreign);
  assert.equal(reader.prepare('SELECT value FROM other').get().value, 'preserved'); reader.close();
  const future = join(directory, 'future.sqlite');
  const db2 = new DatabaseSync(future); db2.exec('PRAGMA user_version = 999'); db2.close();
  assert.throws(() => new SqliteStore(future), /versión/);
});

test('SQLite: las restricciones también rechazan SQL directo con payload inconsistente', t => {
  const { path, store } = fixture(t);
  const db = new DatabaseSync(path);
  db.exec('PRAGMA foreign_keys = ON');
  assert.throws(() => db.prepare('INSERT INTO users(id, position, payload) VALUES (?, ?, ?)').run('u', 0, '{"email":"a@test"}'));
  assert.throws(() => db.prepare('INSERT INTO records(module,id,position,payload) VALUES (?,?,?,?)')
    .run('donors', 'a', 0, JSON.stringify({ id: 'different', module: 'donors', scopeId: 'sede' })));
  db.close();
  assert.equal(store.verify().ok, true);
});

test('SQLite: cuatro procesos escriben sin pérdidas incluso con checkpoints', { timeout: 20000 }, async t => {
  const { store, path } = fixture(t);
  const children = Array.from({ length: 4 }, (_, index) => worker(`
    import {SqliteStore} from ${JSON.stringify(moduleUrl)};
    const s=new SqliteStore(process.argv[1]);
    for(let i=0;i<30;i++)s.update(db=>db.records.push({id:process.argv[2]+'-'+i,module:'donors',scopeId:'sede'}));
    s.close();`, [path, String(index)]));
  t.after(() => { for (const child of children) child.process.kill('SIGKILL'); });
  for (const result of await Promise.all(children.map(child => child.done))) assert.equal(result.code, 0, result.stderr);
  assert.equal(store.read().records.length, 120);
  assert.equal(store.verify().sequence, 120);
  store.checkpoint();
});

test('SQLite: muerte durante callback revierte; muerte tras COMMIT conserva datos', { timeout: 15000 }, async t => {
  const { store, path } = fixture(t);
  for (const commit of [false, true]) {
    const child = worker(`import {SqliteStore} from ${JSON.stringify(moduleUrl)};
      const s=new SqliteStore(process.argv[1]);
      ${commit ? "s.update(db=>db.records.push({id:'saved',module:'donors',scopeId:'sede'}));console.log('READY');setInterval(()=>{},1000);"
        : "s.update(db=>{db.records.push({id:'lost',module:'donors',scopeId:'sede'});console.log('READY');Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,30000);});"}`, [path]);
    t.after(() => child.process.kill('SIGKILL'));
    await ready(child.process);
    child.process.kill('SIGKILL'); await child.done;
  }
  assert.deepEqual(store.read().records.map(r => r.id), ['saved']);
  assert.equal(store.verify().ok, true);
});

test('SQLite: contención devuelve 503 y permite reintentar al liberarse', { timeout: 10000 }, async t => {
  const { path } = fixture(t);
  const writer = new DatabaseSync(path);
  writer.exec('BEGIN IMMEDIATE');
  assert.throws(() => new SqliteStore(path, { busyTimeoutMs: 5 }), { status: 503 });
  writer.exec('ROLLBACK'); writer.close();
  const reopened = new SqliteStore(path); reopened.close();
});

test('SQLite: selección de motor conserva .json y cierre idempotente', t => {
  const { store, directory } = fixture(t);
  const json = openStore(join(directory, 'file.json'));
  assert.ok(json instanceof JsonStore); json.close();
  const sql = openStore(join(directory, 'file.sqlite'));
  assert.ok(sql instanceof SqliteStore); sql.close(); sql.close();
  assert.throws(() => sql.read(), /cerrada/);
  assert.throws(() => store.update(() => store.backupTo(join(directory, 'invalid.sqlite'))), /transacción/);
});

test('SQLite: herramientas importan, auditan, exportan y respaldan con formatos correctos', { timeout: 15000 }, async t => {
  const { directory } = fixture(t);
  const jsonPath = join(directory, 'source.json');
  const json = new JsonStore(jsonPath); seedDemoData(json, 'test');
  const sqlitePath = join(directory, 'migrated.sqlite');
  const toolUrl = new URL('../src/database-tool.mjs', import.meta.url).href;
  const run = (...args) => worker(`process.argv=['node','tool',...process.argv.slice(1)];await import(${JSON.stringify(toolUrl)});`, args).done;
  let result = await run('import-json', jsonPath, sqlitePath);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).engine, 'sqlite');
  assert.equal((await run('import-json', jsonPath, sqlitePath)).code, 1);
  for (const command of ['verify', 'audit', 'checkpoint']) {
    result = await run(command, sqlitePath);
    assert.equal(result.code, 0, result.stderr);
  }
  const exported = join(directory, 'exported.json');
  assert.equal((await run('export-json', sqlitePath, exported)).code, 0);
  assert.deepEqual(new JsonStore(exported).read(), json.read());
  const backup = join(directory, 'backup.sqlite');
  assert.equal((await run('backup', sqlitePath, backup)).code, 0);
  const snapshot = join(directory, 'snapshot.json');
  assert.equal((await run('backup', sqlitePath, snapshot)).code, 0);
  assert.deepEqual(new JsonStore(snapshot).read(), json.read());
  const native = new SqliteStore(backup); assert.deepEqual(native.read(), json.read()); native.close();
  const missing = join(directory, 'missing.sqlite');
  assert.equal((await run('verify', missing)).code, 1);
  assert.equal(existsSync(missing), false);
  assert.equal((await run('import-json', jsonPath, join(directory, 'wrong.json'))).code, 2);
});

test('SQLite: arranque del ejecutable importa JSON una sola vez y mantiene la API JSON', { timeout: 15000 }, async t => {
  const { directory } = fixture(t);
  const jsonPath = join(directory, 'source.json');
  const json = new JsonStore(jsonPath); seedDemoData(json, 'test-password');
  const snapshot = readFileSync(jsonPath), wal = readFileSync(`${jsonPath}.wal`);
  const sqlitePath = join(directory, 'application.sqlite');
  const serverUrl = new URL('../src/server.mjs', import.meta.url).href;
  const child = spawn(process.execPath, ['--input-type=module', '-e', `
    process.env.PORT='0';process.env.HEMOLINK_DATABASE=process.argv[1];process.env.HEMOLINK_IMPORT_JSON=process.argv[2];
    const log=console.log;console.log=(message)=>{log(message);const match=message.match(/127\\.0\\.0\\.1:(\\d+)/);if(match)process.send({port:Number(match[1])});};
    await import(${JSON.stringify(serverUrl)});`, sqlitePath, jsonPath], {
    stdio: ['ignore', 'ignore', 'pipe', 'ipc'], windowsHide: true,
  });
  t.after(() => child.kill('SIGKILL'));
  const done = new Promise(resolve => child.once('close', resolve));
  const port = await new Promise((resolve, reject) => {
    child.once('error', reject); child.once('exit', code => reject(new Error(`Inicio falló: ${code}`)));
    child.once('message', value => resolve(value.port));
  });
  const response = await fetch(`http://127.0.0.1:${port}/api/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'enfermeria@hemolink.test', password: 'test-password' }),
  });
  assert.equal(response.status, 200);
  const { token } = await response.json();
  assert.equal((await fetch(`http://127.0.0.1:${port}/api/donors`, { headers: { Authorization: `Bearer ${token}` } })).status, 200);
  child.kill('SIGKILL'); await done;
  assert.deepEqual(readFileSync(jsonPath), snapshot);
  assert.deepEqual(readFileSync(`${jsonPath}.wal`), wal);
  const reopened = new SqliteStore(sqlitePath, { importJsonPath: jsonPath });
  assert.equal(reopened.read().sessions.length, 1);
  reopened.close();
});
