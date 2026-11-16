import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { JsonStore } from '../src/json-store.mjs';

// Comparación reproducible con el patrón anterior: clonar toda la base y
// buscar con find. No ejecuta SQL ni modifica datos reales del proyecto.
const count = Number(process.argv[2] ?? 10000);
const iterations = Number(process.argv[3] ?? 300);
if (!Number.isSafeInteger(count) || count < 1 || count > 1000000 ||
    !Number.isSafeInteger(iterations) || iterations < 1 || iterations > 100000) {
  throw new Error('Uso: node server/bench/json-store.bench.mjs [registros:1..1000000] [consultas:1..100000]');
}
const directory = mkdtempSync(join(tmpdir(), 'hemolink-bench-'));
let store;
try {
  const path = join(directory, 'benchmark.json');
  store = new JsonStore(path);
  store.update(db => {
    for (let i = 0; i < count; i++) db.records.push({
      id: `D${i}`, module: 'donors', scopeId: `sede-${i % 10}`,
      nombre: `Persona ficticia ${i}`, telefono: '900000000',
      pesoKg: 70, grupoAbo: 'O', factorRh: 'positivo',
    });
  });
  store.checkpoint();
  const before = store.read();
  const last = `D${count - 1}`;
  const measure = fn => {
    const start = performance.now();
    for (let i = 0; i < iterations; i++) assert.equal(fn().id, last);
    return performance.now() - start;
  };
  store.read({ records: { id: last } }); // Calentar índice fuera de la medición.
  const previousReadMs = measure(() => structuredClone(before).records.find(row => row.id === last));
  const indexedReadMs = measure(() => store.read({ records: { id: last } }).records[0]);
  const beforeSize = statSync(`${path}.wal`).size;
  const writeStart = performance.now();
  store.update(db => { db.records.at(-1).nombre = 'Corrección ficticia'; });
  const updateMs = performance.now() - writeStart;
  const journalBytes = statSync(`${path}.wal`).size - beforeSize;
  const previousSnapshotBytes = Buffer.byteLength(JSON.stringify(store.read(), null, 2) + '\n');
  console.log(JSON.stringify({
    records: count, queries: iterations,
    previousReadMs: +previousReadMs.toFixed(2), indexedReadMs: +indexedReadMs.toFixed(2),
    readSpeedup: +(previousReadMs / indexedReadMs).toFixed(2),
    updateMs: +updateMs.toFixed(2), journalBytes, previousSnapshotBytes,
    writeBytesReductionPercent: +((1 - journalBytes / previousSnapshotBytes) * 100).toFixed(3),
    note: 'Índice caliente; tiempos locales. La reducción de bytes excluye checkpoints. La escritura aún procesa la base completa en memoria.',
  }, null, 2));
} finally {
  store?.close();
  rmSync(directory, { recursive: true, force: true });
}
