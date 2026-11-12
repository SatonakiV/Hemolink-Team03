import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';

const now = Date.parse('2026-11-09T15:00:00Z');
const donor = {
  rut: '12.345.678-5', nombre: 'Donante Prueba',
  fechaNacimiento: '1998-05-10', pesoKg: 70,
  grupoAbo: 'O', factorRh: 'positivo', telefono: '912345678',
};

async function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-donors-'));
  const databasePath = join(directory, 'local.json');
  let app;
  let base;
  async function start(seedDemo) {
    app = createApplication({ databasePath, seedDemo, clock: () => now });
    await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${app.server.address().port}`;
  }
  await start(true);
  t.after(async () => {
    await new Promise(resolve => app.server.close(resolve));
    rmSync(directory, { recursive: true, force: true });
  });
  async function request(path, { method = 'GET', body, token } = {}) {
    const response = await fetch(base + path, {
      method,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, data: await response.json() };
  }
  async function login(email = 'enfermeria@hemolink.test') {
    const result = await request('/api/login', {
      method: 'POST', body: { email, password: 'DemoHemoLink2026!' },
    });
    assert.equal(result.status, 200);
    return result.data.token;
  }
  const token = await login();
  return {
    databasePath, token, login, request,
    get store() { return app.store; },
    api: (path, options = {}) => request(path, { ...options, token }),
    async restart() {
      await new Promise(resolve => app.server.close(resolve));
      await start(false);
    },
  };
}

test('T01.2: guarda todos los campos y metadatos del servidor; recupera la ficha al reiniciar', async t => {
  const f = await fixture(t);
  const result = await f.api('/api/donors', {
    method: 'POST', body: {
      ...donor, nombre: ' Donante Prueba ', grupoAbo: ' o ', factorRh: ' POSITIVO ',
      id: 'suplantado', scopeId: 'otra-sede', usuarioRegistroId: 'otro',
      fechaRegistro: '1900-01-01', cuestionario: { pregunta: 'respuesta' },
    },
  });
  assert.equal(result.status, 201, JSON.stringify(result.data));
  const { item } = result.data;
  assert.match(item.id, /^[A-Za-z0-9_-]{1,64}$/);
  assert.notEqual(item.id, 'suplantado');
  assert.equal(item.rut, '12345678-5');
  assert.equal(item.nombre, donor.nombre);
  assert.equal(item.fechaNacimiento, donor.fechaNacimiento);
  assert.equal(item.pesoKg, donor.pesoKg);
  assert.equal(item.grupoAbo, 'O');
  assert.equal(item.factorRh, 'positivo');
  assert.equal(item.telefono, donor.telefono);
  assert.equal(item.usuarioRegistroId, 'nursing-demo');
  assert.equal(item.fechaRegistro, new Date(now).toISOString());
  assert.equal(item.scopeId, 'sede-central');
  assert.equal(item.label, donor.nombre); // Compatible con la consulta de T01.1.
  assert.equal(item.cuestionario, undefined);
  await f.restart();
  const detail = await f.api(`/api/donors/${item.id}`);
  assert.equal(detail.status, 200);
  assert.deepEqual(detail.data.item, item);
  const list = await f.api('/api/donors');
  assert.ok(list.data.items.some(row => row.id === item.id));
});

test('UT01.2-A/C: RUT equivalentes, K y 0 no generan duplicados', async t => {
  const f = await fixture(t);
  for (const [rut, normalized, duplicate] of [
    ['12.345.678-5', '12345678-5', ' 12345678 - 5 '],
    ['6.000.000-k', '6000000-K', '06.000.000-K'],
    ['10.000.004-0', '10000004-0', '100000040'],
  ]) {
    const first = await f.api('/api/donors', { method: 'POST', body: { ...donor, rut } });
    assert.equal(first.status, 201);
    assert.equal(first.data.item.rut, normalized);
    const repeated = await f.api('/api/donors', { method: 'POST', body: { ...donor, rut: duplicate } });
    assert.equal(repeated.status, 409);
    assert.ok(repeated.data.errors.rut);
    const result = await f.api(`/api/donors?rut=${encodeURIComponent(duplicate)}`);
    assert.equal(result.data.items.length, 1);
    assert.equal(result.data.items[0].id, first.data.item.id);
  }
});

test('UT01.2-B: campos ausentes, tipos incorrectos y límites se rechazan sin guardar', async t => {
  const f = await fixture(t);
  const before = f.store.read().records;
  for (const field of Object.keys(donor)) {
    for (const value of [null, '', '   ', {}, []]) {
      const result = await f.api('/api/donors', { method: 'POST', body: { ...donor, [field]: value } });
      assert.equal(result.status, 400, `${field}: ${JSON.stringify(value)}`);
      assert.ok(result.data.errors[field]);
    }
    const body = { ...donor };
    delete body[field];
    assert.equal((await f.api('/api/donors', { method: 'POST', body })).status, 400);
  }
  for (const [field, value] of [
    ['rut', '12.345.678-9'], ['rut', '0-0'], ['rut', '12345678--5'], ['rut', '123456789-0'],
    ['fechaNacimiento', '2026-11-10'], ['fechaNacimiento', '2026-02-30'],
    ['fechaNacimiento', '2026-11-09T00:00:00Z'], ['pesoKg', 0], ['pesoKg', -1],
    ['pesoKg', '70'], ['pesoKg', true], ['grupoAbo', 'C'], ['factorRh', 'desconocido'],
  ]) {
    const result = await f.api('/api/donors', { method: 'POST', body: { ...donor, [field]: value } });
    assert.equal(result.status, 400, `${field}: ${JSON.stringify(value)}`);
    assert.ok(result.data.errors[field]);
  }
  assert.deepEqual(f.store.read().records, before);
  const empty = await f.api('/api/donors', { method: 'POST', body: {} });
  assert.deepEqual(Object.keys(empty.data.errors).sort(), Object.keys(donor).sort());
  const valid = await f.api('/api/donors', { method: 'POST', body: { ...donor, fechaNacimiento: '2026-11-09', pesoKg: 0.1 } });
  assert.equal(valid.status, 201);
});

test('UT01.2-C: confirmaciones simultáneas y reinicio dejan un solo RUT', async t => {
  const f = await fixture(t);
  const results = await Promise.all([
    f.api('/api/donors', { method: 'POST', body: donor }),
    f.api('/api/donors', { method: 'POST', body: { ...donor, rut: '123456785' } }),
  ]);
  assert.deepEqual(results.map(result => result.status).sort(), [201, 409]);
  await f.restart();
  const repeated = await f.api('/api/donors', { method: 'POST', body: donor });
  assert.equal(repeated.status, 409);
  const result = await f.api('/api/donors?rut=12345678-5');
  assert.equal(result.data.items.length, 1);
});

test('UT01.2-C: unicidad global también compara RUT existentes con otro formato', async t => {
  const f = await fixture(t);
  f.store.update(db => db.records.push({
    ...donor, id: 'otro', module: 'donors', scopeId: 'otra-sede',
  }));
  const result = await f.api('/api/donors', { method: 'POST', body: { ...donor, rut: '123456785' } });
  assert.equal(result.status, 409);
  assert.equal(result.data.item, undefined);
  const hidden = await f.api('/api/donors?rut=12345678-5');
  assert.deepEqual(hidden.data.items, []);
});

test('UT01.2-D: busca por RUT equivalente y nombre parcial sin distinguir mayúsculas', async t => {
  const f = await fixture(t);
  const saved = await f.api('/api/donors', { method: 'POST', body: { ...donor, nombre: 'María Prueba & Soto' } });
  assert.equal(saved.status, 201);
  for (const query of ['rut=12.345.678-5', 'rut=123456785', `nombre=${encodeURIComponent(' MARÍA PRUEBA & ')}`]) {
    const result = await f.api(`/api/donors?${query}`);
    assert.equal(result.status, 200);
    assert.deepEqual(result.data.items.map(row => row.id), [saved.data.item.id]);
  }
  assert.deepEqual((await f.api('/api/donors?nombre=sin-coincidencias')).data.items, []);
  assert.deepEqual((await f.api('/api/donors?rut=6000000-K')).data.items, []);
  assert.equal((await f.api('/api/donors?rut=invalido')).status, 400);
  assert.equal((await f.api('/api/donors/no-existe')).status, 404);
});

test('CP01-08/09: permisos en alta, listado y ficha; cierre y sede no se pueden eludir', async t => {
  const f = await fixture(t);
  const saved = await f.api('/api/donors', { method: 'POST', body: donor });
  assert.equal(saved.status, 201);
  const paths = ['/api/donors', `/api/donors/${saved.data.item.id}`];
  for (const [token, status] of [
    [undefined, 401], ['inventado', 401],
    [await f.login('inventario@hemolink.test'), 403],
    [await f.login('hospital@hemolink.test'), 403],
  ]) {
    for (const path of paths) {
      const result = await f.request(path, { token });
      assert.equal(result.status, status);
      assert.equal(result.data.item, undefined);
      assert.equal(result.data.items, undefined);
    }
    assert.equal((await f.request('/api/donors', { token, method: 'POST', body: donor })).status, status);
  }
  f.store.update(db => db.records.push({
    ...donor, id: 'ajeno', module: 'donors', scopeId: 'otra-sede',
  }));
  assert.equal((await f.api('/api/donors/ajeno?siteId=otra-sede')).status, 404);
  assert.ok(!(await f.api('/api/donors?siteId=otra-sede')).data.items.some(row => row.id === 'ajeno'));
  assert.equal((await f.api('/api/logout', { method: 'POST' })).status, 200);
  assert.equal((await f.api(paths[1])).status, 401);
  assert.equal((await f.api('/api/donors', { method: 'POST', body: donor })).status, 401);
});

test('UT01.2-E: fallo real de escritura no confirma ni deja donante parcial; permite reintentar', async t => {
  const f = await fixture(t);
  const previous = readFileSync(f.databasePath, 'utf8');
  const before = f.store.read();
  f.store.path = join(f.databasePath, 'destino-invalido.json');
  const result = await f.api('/api/donors', { method: 'POST', body: donor });
  assert.equal(result.status, 500);
  assert.equal(result.data.item, undefined);
  assert.deepEqual(f.store.read(), before);
  assert.equal(readFileSync(f.databasePath, 'utf8'), previous);
  f.store.path = f.databasePath;
  assert.equal((await f.api('/api/donors', { method: 'POST', body: donor })).status, 201);
});

test('UT01.2-E: fallo de lectura no se informa como lista vacía ni ficha ausente', async t => {
  const f = await fixture(t);
  const original = f.store.read;
  let reads = 0;
  f.store.read = function () {
    if (++reads % 2 === 0) throw new Error('detalle interno no publicable');
    return original.call(this); // Primera lectura: autenticación.
  };
  try {
    for (const path of ['/api/donors', '/api/donors/demo-donors']) {
      const result = await f.api(path);
      assert.equal(result.status, 500);
      assert.equal(result.data.items, undefined);
      assert.equal(result.data.item, undefined);
      assert.ok(!JSON.stringify(result.data).includes('detalle interno'));
    }
  } finally {
    f.store.read = original;
  }
});

test('T01.2/HU02: un donante creado por API admite una evaluación de aptitud', async t => {
  const f = await fixture(t);
  const saved = await f.api('/api/donors', { method: 'POST', body: donor });
  assert.equal(saved.status, 201);
  const evaluation = await f.api('/api/evaluations', {
    method: 'POST', body: {
      id: 'EV_DONANTE', donanteId: saved.data.item.id, resultado: 'apto',
      fechaEvaluacion: '2026-11-09', fechaFinVigencia: '2026-11-20',
    },
  });
  assert.equal(evaluation.status, 201);
  await f.restart();
  const result = await f.api(`/api/evaluations?donanteId=${saved.data.item.id}`);
  assert.equal(result.data.items[0].id, 'EV_DONANTE');
});

test('T04.4: PUT /api/donors/:id actualiza datos, conserva id y metadatos, registra modificador y verifica unicidad de RUT', async t => {
  const f = await fixture(t);
  // Crear donante 1
  const d1 = await f.api('/api/donors', { method: 'POST', body: donor });
  assert.equal(d1.status, 201);
  const id1 = d1.data.item.id;

  // Crear donante 2 con otro RUT (22.222.222-2)
  const d2 = await f.api('/api/donors', {
    method: 'POST',
    body: { ...donor, rut: '22.222.222-2', nombre: 'Segundo Donante' },
  });
  assert.equal(d2.status, 201);
  const id2 = d2.data.item.id;

  // UT04.4-B: Intentar actualizar d1 usando el RUT de d2 (o de la semilla) debe fallar con 409
  const conflicto = await f.api(`/api/donors/${id1}`, {
    method: 'PUT',
    body: { ...donor, rut: '22.222.222-2', nombre: 'Conflicto' },
  });
  assert.equal(conflicto.status, 409);
  assert.equal(conflicto.data.errors?.rut, 'Ya existe un donante con ese RUT.');

  // UT04.4-C: Campos inválidos se rechazan con 400 sin alterar la versión guardada
  const invalido = await f.api(`/api/donors/${id1}`, {
    method: 'PUT',
    body: { ...donor, pesoKg: -10, grupoAbo: 'INVALIDO' },
  });
  assert.equal(invalido.status, 400);

  // UT04.4-A: Actualización exitosa manteniendo el mismo RUT (incluso con otro formato)
  const actualizacion = await f.api(`/api/donors/${id1}`, {
    method: 'PUT',
    body: {
      ...donor,
      rut: ' 12345678-5 ', // Mismo RUT sin puntos y con espacios
      nombre: 'Donante Modificado',
      pesoKg: 75,
      grupoAbo: 'A',
      factorRh: 'positivo',
      telefono: '999888777',
    },
  });
  assert.equal(actualizacion.status, 200, JSON.stringify(actualizacion.data));
  const actualizado = actualizacion.data.item;
  assert.equal(actualizado.id, id1);
  assert.equal(actualizado.nombre, 'Donante Modificado');
  assert.equal(actualizado.pesoKg, 75);
  assert.equal(actualizado.grupoAbo, 'A');
  assert.equal(actualizado.usuarioRegistroId, d1.data.item.usuarioRegistroId);
  assert.equal(actualizado.fechaRegistro, d1.data.item.fechaRegistro);
  assert.equal(actualizado.usuarioModificacionId, 'nursing-demo');
  assert.ok(actualizado.fechaModificacion);

  // Reiniciar servidor y comprobar persistencia
  await f.restart();
  const recuperado = await f.api(`/api/donors/${id1}`);
  assert.equal(recuperado.status, 200);
  assert.equal(recuperado.data.item.nombre, 'Donante Modificado');
  assert.equal(recuperado.data.item.pesoKg, 75);
  assert.equal(recuperado.data.item.grupoAbo, 'A');
  assert.equal(recuperado.data.item.usuarioModificacionId, 'nursing-demo');
});

