import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync, rmSync, readFileSync, writeFileSync, appendFileSync,
  statSync, mkdirSync, readdirSync, existsSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { JsonStore } from '../src/json-store.mjs';
import { digest } from '../src/json-journal.mjs';
import { StoreBusyError } from '../src/file-lock.mjs';
import { createApplication } from '../src/app.mjs';

const moduleUrl = new URL('../src/json-store.mjs', import.meta.url).href;
const row = id => ({ id, module: 'donors', scopeId: 'sede', nombre: `Nombre ${id}` });

function fixture(t, options) {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-storage-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const path = join(directory, 'db.json');
  return { directory, path, store: new JsonStore(path, options) };
}

function child(source, args = []) {
  const process = spawn(globalThis.process.execPath, ['--input-type=module', '-e', source, ...args], {
    stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
  });
  let stdout = '', stderr = '';
  process.stdout.on('data', chunk => { stdout += chunk; });
  process.stderr.on('data', chunk => { stderr += chunk; });
  const done = new Promise((resolve, reject) => {
    process.once('error', reject);
    process.once('close', (code, signal) => resolve({ code, signal, stdout, stderr }));
  });
  return { process, done };
}

async function waitForOutput(process, text) {
  let output = '';
  for await (const chunk of process.stdout) {
    output += chunk;
    if (output.includes(text)) return;
  }
  throw new Error('El proceso terminó antes del punto de prueba.');
}

test('diario incremental: recuperación, modificaciones, borrado y orden tras reinicio', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A'), row('B'), row('C')));
  store.update(db => { db.records[1].nombre = 'Corregido'; });
  store.update(db => { db.records.splice(0, 1); });
  assert.deepEqual(new JsonStore(path).read(), store.read());
  assert.deepEqual(store.read().records.map(item => item.id), ['B', 'C']);
  assert.equal(store.read().records[0].nombre, 'Corregido');
  assert.equal(store.verify().sequence, 3);
});

test('las lecturas y referencias retenidas por el callback no modifican datos confirmados', t => {
  const { path, store } = fixture(t);
  let leaked;
  store.update(db => { leaked = db; db.records.push(row('A')); });
  leaked.records[0].nombre = 'Mutación tardía';
  leaked.records.push(row('B'));
  const selected = store.read({ records: { id: 'A' } });
  selected.records[0].nombre = 'Mutación de lectura';
  assert.deepEqual(store.read().records, [row('A')]);
  assert.deepEqual(new JsonStore(path).read(), store.read());
});

test('rollback del callback no escribe y una transacción sin cambios no crece', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const before = readFileSync(`${path}.wal`);
  assert.throws(() => store.update(db => { db.records.length = 0; throw new Error('cancelado'); }), /cancelado/);
  store.update(() => {});
  assert.deepEqual(readFileSync(`${path}.wal`), before);
  assert.deepEqual(store.read().records, [row('A')]);
});

test('transacciones async, promesas, anidadas y cierre durante callback se rechazan', async t => {
  const { store } = fixture(t);
  assert.throws(() => store.update(async db => { db.records.push(row('A')); }), /síncrona/);
  assert.throws(() => store.update(db => {
    db.records.push(row('B'));
    return Promise.resolve().then(() => db.records.push(row('C')));
  }), /promesa/);
  assert.throws(() => store.update(() => store.update(() => {})), /anidadas/);
  assert.throws(() => store.update(() => store.close()), /transacción/);
  await Promise.resolve();
  assert.deepEqual(store.read().records, []);
});

test('valores no JSON, arreglos dispersos y claves duplicadas hacen rollback', t => {
  const { store } = fixture(t);
  for (const value of [undefined, NaN, Infinity, 1n, new Date(), () => {}, Symbol('x')]) {
    assert.throws(() => store.update(db => db.records.push({ ...row('A'), value })));
  }
  assert.throws(() => store.update(db => { db.records.length = 2; }));
  assert.throws(() => store.update(db => db.records.push(row('A'), row('A'))), { status: 409 });
  assert.throws(() => store.update(db => { db.version = 2; }));
  assert.throws(() => store.update(db => {
    const item = row('A'); item.cycle = item; db.records.push(item);
  }));
  assert.throws(() => store.update(db => {
    const item = row('A'); Object.defineProperty(item, 'getter', { enumerable: true, get: () => 'x' });
    db.records.push(item);
  }));
  assert.deepEqual(store.read().records, []);
});

test('sesiones huérfanas, correos equivalentes e identificadores inválidos se rechazan', t => {
  const { store } = fixture(t);
  assert.throws(() => store.update(db => db.users.push({ id: 'u' })));
  assert.throws(() => store.update(db => db.users.push(
    { id: 'u1', email: 'USER@test' }, { id: 'u2', email: 'user@test' },
  )), { status: 409 });
  assert.throws(() => store.update(db => db.sessions.push({ tokenHash: 'a'.repeat(64), userId: 'absent', expiresAt: 1000 })));
  assert.throws(() => store.update(db => db.records.push({ id: 'x' })));
  assert.deepEqual(store.read().users, []);
});

test('consultas indexadas filtran por sede, conservan orden y actualizan índices', t => {
  const { store } = fixture(t);
  store.update(db => db.records.push(row('A'), { ...row('B'), scopeId: 'otra' }, row('C')));
  assert.deepEqual(store.read({ records: { module: 'donors', scopeId: 'sede' } }).records.map(r => r.id), ['A', 'C']);
  store.update(db => { db.records[0].scopeId = 'otra'; db.records.reverse(); });
  assert.deepEqual(store.read({ records: { scopeId: 'otra' } }).records.map(r => r.id), ['B', 'A']);
  assert.equal(store.read({ records: { id: 'missing' } }).records.length, 0);
  assert.throws(() => store.read({ absent: {} }));
  assert.throws(() => store.read({ records: { unindexed: 'value' } }));
});

test('índices de registros siguen válidos al modificar solo sesiones o usuarios', t => {
  const { store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  store.read({ records: { id: 'A' } });
  store.update(db => db.users.push({ id: 'u', email: 'u@test' }));
  assert.deepEqual(store.read({ records: { id: 'A' } }).records, [row('A')]);
  store.update(db => db.sessions.push({ tokenHash: 'a'.repeat(64), userId: 'u', expiresAt: 1000 }));
  assert.equal(store.read({ sessions: { tokenHash: 'a'.repeat(64) } }).sessions.length, 1);
  assert.deepEqual(store.read({ records: { id: 'A' } }).records, [row('A')]);
});

test('dos instancias ven cambios nuevos y nunca sobrescriben un estado antiguo', t => {
  const { path, store: a } = fixture(t);
  const b = new JsonStore(path);
  a.update(db => db.records.push(row('A')));
  assert.deepEqual(b.read({ records: { id: 'A' } }).records, [row('A')]);
  b.update(db => db.records.push(row('B')));
  a.checkpoint();
  b.update(db => db.records.push(row('C')));
  assert.deepEqual(a.read().records.map(r => r.id), ['A', 'B', 'C']);
});

test('checksum detecta corrupción incluso si el JSON sigue siendo válido', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const corrupted = readFileSync(`${path}.wal`, 'utf8').replace('Nombre A', 'Nombre X');
  writeFileSync(`${path}.wal`, corrupted);
  assert.throws(() => new JsonStore(path), /integridad/);
  assert.throws(() => store.verify(), /integridad/);
  assert.equal(readFileSync(`${path}.wal`, 'utf8'), corrupted);
});

test('snapshot alterado, truncado o sin versión no se reemplaza silenciosamente', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  store.checkpoint();
  const snapshot = readFileSync(path, 'utf8');
  for (const invalid of [snapshot.replace('Nombre A', 'Nombre X'), '{', '{"version":2,"users":[],"sessions":[],"records":[]}']) {
    writeFileSync(path, invalid);
    assert.throws(() => new JsonStore(path));
    assert.equal(readFileSync(path, 'utf8'), invalid);
  }
});

test('una cola interrumpida se descarta conservando todas las transacciones completas', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const size = statSync(`${path}.wal`).size;
  appendFileSync(`${path}.wal`, '{"version":1,"sequence":2,"texto":"ñ');
  const reopened = new JsonStore(path);
  assert.deepEqual(reopened.read().records, [row('A')]);
  assert.equal(statSync(`${path}.wal`).size, size);
  reopened.update(db => db.records.push(row('B')));
  assert.equal(new JsonStore(path).read().records.length, 2);
});

test('línea completa corrupta no se descarta como si fuera una cola incompleta', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  appendFileSync(`${path}.wal`, '{"malformado":true}\n');
  const before = readFileSync(`${path}.wal`);
  assert.throws(() => new JsonStore(path));
  assert.deepEqual(readFileSync(`${path}.wal`), before);
});

test('eliminar o reordenar transacciones detecta una discontinuidad', t => {
  const { path, store } = fixture(t);
  for (const id of ['A', 'B', 'C']) store.update(db => db.records.push(row(id)));
  const lines = readFileSync(`${path}.wal`, 'utf8').trimEnd().split('\n');
  for (const altered of [[lines[0], lines[2]], [lines[1], lines[0], lines[2]], [lines[0], lines[0], lines[1]]]) {
    writeFileSync(`${path}.wal`, altered.join('\n') + '\n');
    assert.throws(() => new JsonStore(path));
  }
});

test('una transacción con checksum recalculado pero delta inválido se rechaza', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const { checksum, ...entry } = JSON.parse(readFileSync(`${path}.wal`, 'utf8'));
  entry.changes.records.set[0][0] = -1;
  writeFileSync(`${path}.wal`, JSON.stringify({ ...entry, checksum: digest(JSON.stringify(entry)) }) + '\n');
  assert.throws(() => new JsonStore(path), /inválido/);
});

test('checkpoint deja snapshot autónomo y un diario vacío; acepta un diario viejo tras caída', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  store.update(db => db.records.push(row('B')));
  const wal = readFileSync(`${path}.wal`);
  store.checkpoint();
  assert.equal(statSync(`${path}.wal`).size, 0);
  assert.equal(JSON.parse(readFileSync(path, 'utf8')).records.length, 2);
  // Caída después de rename(snapshot), antes de truncar el diario.
  writeFileSync(`${path}.wal`, wal);
  const recovered = new JsonStore(path);
  assert.deepEqual(recovered.read(), store.read());
  recovered.update(db => db.records.push(row('C')));
  assert.equal(new JsonStore(path).verify().sequence, 3);
});

test('compactación automática mantiene el orden y permite nuevos commits', t => {
  const { path, store } = fixture(t, { checkpointBytes: 1 });
  for (const id of ['A', 'B', 'C', 'D']) store.update(db => db.records.push(row(id)));
  assert.equal(readFileSync(`${path}.wal`, 'utf8').trim().split('\n').length, 1);
  assert.deepEqual(new JsonStore(path).read(), store.read());
  assert.equal(store.verify().sequence, 4);
});

test('respaldo autónomo consistente, exclusivo y sin alterar la base activa', t => {
  const { directory, path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const backup = join(directory, 'backup.json');
  store.backupTo(backup);
  assert.equal(existsSync(`${backup}.wal`), false);
  assert.deepEqual(new JsonStore(backup).read(), store.read());
  store.update(db => db.records.push(row('B')));
  assert.equal(new JsonStore(backup).read().records.length, 1);
  assert.throws(() => store.backupTo(backup), { code: 'EEXIST' });
  assert.throws(() => store.backupTo(path));
  assert.throws(() => store.backupTo(`${path}.wal`));
  assert.equal(store.read().records.length, 2);
});

test('archivos JSON originales sin metadatos se leen sin migración destructiva', t => {
  const { path, store } = fixture(t);
  const legacy = JSON.stringify({ version: 1, users: [], sessions: [], records: [row('A')] });
  writeFileSync(path, legacy);
  const migrated = new JsonStore(path);
  assert.equal(readFileSync(path, 'utf8'), legacy);
  migrated.update(db => db.records.push(row('B')));
  assert.deepEqual(new JsonStore(path).read(), migrated.read());
  store.close();
});

test('diario sin snapshot y retroceso de transacciones no generan bases vacías', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  rmSync(path);
  assert.throws(() => new JsonStore(path), /Falta la instantánea/);
  assert.equal(existsSync(path), false);
});

test('bloqueo de proceso vivo devuelve 503, y se recupera al morir el propietario', { timeout: 15000 }, async t => {
  const { path, store } = fixture(t, { busyTimeoutMs: 20 });
  const held = child(`import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const store = new JsonStore(process.argv[1]);
    store.update(db => { db.records.push({id:'incompleto',module:'donors'});
      console.log('LOCKED'); Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,30000); });`, [path]);
  t.after(() => held.process.kill('SIGKILL'));
  await waitForOutput(held.process, 'LOCKED');
  assert.throws(() => store.read(), StoreBusyError);
  assert.throws(() => store.update(() => {}), { status: 503 });
  held.process.kill('SIGKILL');
  await held.done;
  store.update(db => db.records.push(row('A')));
  assert.deepEqual(store.read().records, [row('A')]);
  assert.equal(existsSync(`${path}.lock`), false);
});

test('bloqueo vacío de una caída al adquirirlo se recupera', t => {
  const { path, store } = fixture(t);
  mkdirSync(`${path}.lock`);
  assert.deepEqual(store.read().records, []);
  assert.equal(existsSync(`${path}.lock`), false);
});

test('procesos concurrentes no pierden cambios y las lecturas observan commits completos', { timeout: 30000 }, async t => {
  const { path, store } = fixture(t, { checkpointBytes: 4000 });
  const children = Array.from({ length: 4 }, (_, index) => child(`
    import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const store = new JsonStore(process.argv[1], {checkpointBytes:4000,busyTimeoutMs:5000});
    for(let i=0;i<60;i++) {
      store.update(db=>db.records.push({id:process.argv[2]+'-'+i,module:'donors',scopeId:'sede'}));
      if(i%10===0)store.read({records:{module:'donors'}});
    }
    console.log(store.verify().ok);`, [path, String(index)]));
  t.after(() => { for (const item of children) item.process.kill('SIGKILL'); });
  const results = await Promise.all(children.map(item => item.done));
  for (const result of results) assert.equal(result.code, 0, result.stderr);
  assert.equal(store.read().records.length, 240);
  assert.equal(new Set(store.read().records.map(r => r.id)).size, 240);
  assert.equal(store.verify().sequence, 240);
});

test('muerte después de un COMMIT recupera datos sin ejecutar cierre ni checkpoint', { timeout: 10000 }, async t => {
  const { path, store } = fixture(t);
  const writer = child(`import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const s=new JsonStore(process.argv[1]);
    s.update(db=>db.records.push({id:'committed',module:'donors',nombre:'Ñandú 🩸'}));
    console.log('COMMITTED'); setInterval(()=>{},1000);`, [path]);
  t.after(() => writer.process.kill('SIGKILL'));
  await waitForOutput(writer.process, 'COMMITTED');
  writer.process.kill('SIGKILL');
  await writer.done;
  assert.equal(new JsonStore(path).read().records[0].nombre, 'Ñandú 🩸');
  assert.equal(store.read().records[0].id, 'committed');
});

test('fallo de fsync revierte los bytes del diario y permite reintentar', { timeout: 10000 }, async t => {
  const { path, store } = fixture(t);
  const writer = child(`import fs from 'node:fs'; import {syncBuiltinESMExports} from 'node:module';
    import assert from 'node:assert/strict'; import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const s=new JsonStore(process.argv[1]); const original=fs.fsyncSync; let failed=false;
    fs.fsyncSync=fd=>{if(!failed){failed=true;throw new Error('fsync-inyectado');}return original(fd);};
    syncBuiltinESMExports();
    assert.throws(()=>s.update(db=>db.records.push({id:'failed',module:'donors'})),/fsync-inyectado/);
    fs.fsyncSync=original;syncBuiltinESMExports();
    assert.equal(s.read().records.length,0);
    s.update(db=>db.records.push({id:'retry',module:'donors'}));`, [path]);
  const result = await writer.done;
  assert.equal(result.code, 0, result.stderr);
  assert.deepEqual(store.read().records.map(r => r.id), ['retry']);
});

test('un fallo al compactar conserva el diario y la siguiente transacción no se confirma', t => {
  const { path, store } = fixture(t, { checkpointBytes: 1 });
  store.update(db => db.records.push(row('A')));
  // Un directorio en el destino de la instantánea provoca un fallo real.
  const original = readFileSync(path);
  rmSync(path);
  mkdirSync(path);
  assert.throws(() => store.update(db => db.records.push(row('B'))));
  rmSync(path, { recursive: true });
  writeFileSync(path, original);
  assert.deepEqual(new JsonStore(path).read().records, [row('A')]);
});

test('cerrar es idempotente y puede compactar explícitamente', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  store.close({ checkpoint: true });
  store.close();
  assert.throws(() => store.read(), /cerrada/);
  assert.throws(() => store.update(() => {}), /cerrada/);
  assert.equal(statSync(`${path}.wal`).size, 0);
  assert.equal(readdirSync(join(path, '..')).filter(name => name.endsWith('.tmp')).length, 0);
});

test('matar durante una escritura parcial recupera solo los commits anteriores', { timeout: 10000 }, async t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const writer = child(`import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';
    import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const s=new JsonStore(process.argv[1]);const original=fs.writeSync;
    fs.writeSync=(fd,buffer,offset,length,position)=>{
      original(fd,buffer,offset,Math.floor(length/2),position);
      process.kill(process.pid,'SIGKILL');
    };syncBuiltinESMExports();
    s.update(db=>db.records.push({id:'partial',module:'donors'}));`, [path]);
  const result = await writer.done;
  assert.ok(result.signal || result.code !== 0);
  const reopened = new JsonStore(path);
  assert.deepEqual(reopened.read().records, [row('A')]);
  reopened.update(db => db.records.push(row('B')));
  assert.deepEqual(store.read().records.map(r => r.id), ['A', 'B']);
});

test('matar entre reemplazar snapshot y truncar diario mantiene todos los commits', { timeout: 10000 }, async t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A'), row('B')));
  const writer = child(`import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';
    import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const s=new JsonStore(process.argv[1]);const original=fs.renameSync;
    fs.renameSync=(...args)=>{original(...args);process.kill(process.pid,'SIGKILL');};
    syncBuiltinESMExports();s.checkpoint();`, [path]);
  const result = await writer.done;
  assert.ok(result.signal || result.code !== 0);
  const reopened = new JsonStore(path);
  assert.deepEqual(reopened.read().records, [row('A'), row('B')]);
  reopened.update(db => db.records.push(row('C')));
  assert.equal(reopened.verify().sequence, 2);
});

test('error de escritura tras bytes parciales revierte hasta el último commit', { timeout: 10000 }, async t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const writer = child(`import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';
    import assert from 'node:assert/strict';import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const s=new JsonStore(process.argv[1]);const original=fs.writeSync;let calls=0;
    fs.writeSync=(fd,buffer,offset,length,position)=>{
      if(++calls===1)return original(fd,buffer,offset,10,position);
      throw new Error('disco-lleno');
    };syncBuiltinESMExports();
    assert.throws(()=>s.update(db=>db.records.push({id:'failed',module:'donors'})),/disco-lleno/);
    fs.writeSync=original;syncBuiltinESMExports();
    assert.deepEqual(s.read().records.map(r=>r.id),['A']);`, [path]);
  const result = await writer.done;
  assert.equal(result.code, 0, result.stderr);
  assert.deepEqual(store.read().records, [row('A')]);
});

test('fallo al escribir y al revertir obliga a reabrir antes de seguir', { timeout: 10000 }, async t => {
  const { path } = fixture(t);
  const writer = child(`import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';
    import assert from 'node:assert/strict';import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const s=new JsonStore(process.argv[1]);const sync=fs.fsyncSync,truncate=fs.ftruncateSync;
    fs.fsyncSync=()=>{throw new Error('disco');};fs.ftruncateSync=()=>{throw new Error('disco');};
    syncBuiltinESMExports();
    assert.throws(()=>s.update(db=>db.records.push({id:'uncertain',module:'donors'})),/disco/);
    fs.fsyncSync=sync;fs.ftruncateSync=truncate;syncBuiltinESMExports();
    assert.throws(()=>s.read(),/reabra/);assert.throws(()=>s.update(()=>{}),/reabra/);
    s.close();new JsonStore(process.argv[1]).verify();`, [path]);
  const result = await writer.done;
  assert.equal(result.code, 0, result.stderr);
});

test('fallo del reemplazo atómico durante compactación conserva el diario', { timeout: 10000 }, async t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const writer = child(`import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';
    import assert from 'node:assert/strict';import {JsonStore} from ${JSON.stringify(moduleUrl)};
    const s=new JsonStore(process.argv[1],{checkpointBytes:1});const original=fs.renameSync;
    fs.renameSync=()=>{throw new Error('rename-fallido');};syncBuiltinESMExports();
    assert.throws(()=>s.update(db=>db.records.push({id:'failed',module:'donors'})),/rename-fallido/);
    fs.renameSync=original;syncBuiltinESMExports();
    assert.deepEqual(s.read().records.map(r=>r.id),['A']);
    s.update(db=>db.records.push({id:'retry',module:'donors'}));`, [path]);
  const result = await writer.done;
  assert.equal(result.code, 0, result.stderr);
  assert.deepEqual(store.read().records.map(r => r.id), ['A', 'retry']);
});

test('snapshot faltante con diario vacío también falla sin crear una base', t => {
  const { path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  store.checkpoint();
  rmSync(path);
  assert.throws(() => new JsonStore(path), /Falta la instantánea/);
  assert.equal(existsSync(path), false);
});

test('metadatos presentes pero inválidos no se aceptan como formato heredado', t => {
  const { path } = fixture(t);
  const data = JSON.parse(readFileSync(path, 'utf8'));
  for (const metadata of [null, false, 0, {}]) {
    data.__hemolink_storage = metadata;
    writeFileSync(path, JSON.stringify(data));
    assert.throws(() => new JsonStore(path), /integridad/);
  }
});

test('auditoría clínica informa referencias, sedes, usuarios y claves de negocio sin modificar datos', t => {
  const { store } = fixture(t);
  store.update(db => db.records.push(
    { ...row('A'), rut: '12.345.678-5' },
    { ...row('B'), rut: '12345678-5', scopeId: 'otra' },
    { id: 'E', module: 'evaluations', scopeId: 'otra', donanteId: 'A', resultado: 'apto' },
    { id: 'D', module: 'donations', scopeId: 'sede', donanteId: 'absent', evaluacionId: 'E', responsableId: 'absent' },
    { id: 'S', module: 'samples', scopeId: 'sede', donanteId: 'A', donacionId: 'missing', codigo: 'M' },
  ));
  const before = store.read();
  const result = store.verify({ references: true });
  assert.equal(result.ok, false);
  for (const code of ['duplicate_key', 'missing_target', 'scope_mismatch', 'missing_user']) {
    assert.ok(result.issues.some(issue => issue.code === code), code);
  }
  assert.deepEqual(store.read(), before);
  assert.equal(store.verify().ok, true); // Integridad física y referencias se distinguen.
});

test('apagado configurado compacta el JSON para herramientas que solo leen la instantánea', async t => {
  const { path } = fixture(t);
  const { server, store } = createApplication({ databasePath: path, checkpointOnClose: true });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  store.update(db => db.records.push(row('A')));
  await new Promise(resolve => server.close(resolve));
  assert.equal(JSON.parse(readFileSync(path, 'utf8')).records[0].id, 'A');
  assert.equal(statSync(`${path}.wal`).size, 0);
});

test('herramienta verifica, audita, respalda y compacta sin crear orígenes inexistentes', { timeout: 15000 }, async t => {
  const { directory, path, store } = fixture(t);
  store.update(db => db.records.push(row('A')));
  const tool = new URL('../src/database-tool.mjs', import.meta.url).href;
  const run = (command, source, target) => child(`process.argv=['node','tool',...process.argv.slice(1)];await import(${JSON.stringify(tool)});`,
    [command, source, ...(target ? [target] : [])]).done;
  for (const command of ['verify', 'audit', 'checkpoint']) {
    const result = await run(command, path);
    assert.equal(result.code, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).ok, true);
  }
  const backup = join(directory, 'backup.json');
  assert.equal((await run('backup', path, backup)).code, 0);
  assert.deepEqual(new JsonStore(backup).read().records, [row('A')]);
  assert.equal((await run('backup', path, backup)).code, 1);
  const missing = join(directory, 'missing.json');
  assert.equal((await run('verify', missing)).code, 1);
  assert.equal(existsSync(missing), false);
  assert.equal((await run('invalid', path)).code, 2);
});
