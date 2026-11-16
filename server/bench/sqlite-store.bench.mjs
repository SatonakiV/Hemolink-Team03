import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { JsonStore } from '../src/json-store.mjs';
import { SqliteStore } from '../src/sqlite-store.mjs';

const count = Number(process.argv[2] ?? 10000);
const queries = Number(process.argv[3] ?? 300);
if (!Number.isSafeInteger(count) || count < 1 || count > 1000000 ||
    !Number.isSafeInteger(queries) || queries < 1 || queries > 100000) {
  throw new Error('Uso: node server/bench/sqlite-store.bench.mjs [registros:1..1000000] [consultas:1..100000]');
}
const directory = mkdtempSync(join(tmpdir(), 'hemolink-compare-'));
const stores = [];
try {
  const results = {};
  for (const [engine, Store] of [['json', JsonStore], ['sqlite', SqliteStore]]) {
    const store = new Store(join(directory, `db.${engine}`));
    stores.push(store);
    store.update(db => {
      for (let i = 0; i < count; i++) db.records.push({
        id: `D${i}`, module: 'donors', scopeId: `sede-${i % 10}`, nombre: `Persona ficticia ${i}`,
      });
    });
    store.checkpoint();
    const query = { records: { id: `D${count - 1}`, module: 'donors', scopeId: `sede-${(count - 1) % 10}` } };
    store.read(query);
    const start = performance.now();
    for (let i = 0; i < queries; i++) assert.equal(store.read(query).records[0].id, `D${count - 1}`);
    const readMs = performance.now() - start;
    const writeStart = performance.now();
    store.update(db => { db.records.at(-1).nombre = 'Nombre corregido'; });
    results[engine] = { readMs: +readMs.toFixed(2), updateMs: +(performance.now() - writeStart).toFixed(2) };
    assert.equal(store.verify().ok, true);
  }
  assert.deepEqual(stores[0].read(), stores[1].read());
  console.log(JSON.stringify({ records: count, queries, results,
    indexedReadSpeedup: +(results.json.readMs / results.sqlite.readMs).toFixed(2),
    note: 'Índices preparados en ambos motores; prueba local, sin HTTP. El contrato update aún lee y valida la base completa.',
  }, null, 2));
} finally {
  for (const store of stores) store.close();
  rmSync(directory, { recursive: true, force: true });
}
