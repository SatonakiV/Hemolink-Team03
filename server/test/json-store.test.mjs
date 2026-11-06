import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { JsonStore } from '../src/json-store.mjs';
import { seedDemoData } from '../src/auth.mjs';

function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-json-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return join(directory, 'local.json');
}

test('fallo de escritura conserva el archivo y el estado anterior', t => {
  const path = fixture(t);
  const store = new JsonStore(path);
  const previous = readFileSync(path, 'utf8');
  store.path = join(path, 'destino-invalido.json');
  assert.throws(() => store.update(db => db.records.push({ id: 'no-guardado' })));
  assert.deepEqual(store.read().records, []);
  assert.equal(readFileSync(path, 'utf8'), previous);
});

test('JSON dañado no se reemplaza por una base vacía', t => {
  const path = fixture(t);
  writeFileSync(path, '{dañado');
  assert.throws(() => new JsonStore(path));
  assert.equal(readFileSync(path, 'utf8'), '{dañado');
});

test('sembrar dos veces conserva cuentas, contraseñas y datos sin duplicarlos', t => {
  const store = new JsonStore(fixture(t));
  seedDemoData(store, 'original');
  const before = store.read();
  seedDemoData(store, 'otra-clave');
  assert.deepEqual(store.read(), before);
});
