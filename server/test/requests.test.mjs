import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';
import { passwordHash } from '../src/auth.mjs';

const password = 'DemoHemoLink2026!';

async function fixture(t, options = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'hemolink-requests-'));
  const databasePath = join(directory, 'test.sqlite');
  let now = Date.parse('2026-11-21T10:00:00.000Z');
  let application;
  let base;

  async function start(seedDemo) {
    application = createApplication({ databasePath, seedDemo, clock: () => now, ...options });
    await new Promise(resolve => application.server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${application.server.address().port}`;
  }

  await start(true);

  // Registrar un segundo hospital para pruebas de aislamiento entre hospitales
  application.store.update(db => {
    db.users.push({
      id: 'hospital-2-user',
      email: 'hospital2@hemolink.test',
      role: 'hospital',
      isVerified: true,
      passwordHash: passwordHash(password),
      siteId: null,
      hospitalId: 'hospital-regional',
    });
  });

  t.after(async () => {
    await new Promise(resolve => application.server.close(resolve));
    rmSync(directory, { recursive: true, force: true });
  });

  async function request(path, { token, body, method = 'GET' } = {}) {
    const response = await fetch(base + path, {
      method,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const data = response.status === 204 ? null : await response.json();
    return { status: response.status, data };
  }

  async function login(email = 'hospital@hemolink.test', secret = password) {
    const res = await request('/api/login', { method: 'POST', body: { email, password: secret } });
    assert.equal(res.status, 200);
    return res.data.token;
  }

  return {
    databasePath,
    get store() { return application.store; },
    advance(ms) { now += ms; },
    request,
    login,
    async restart() {
      await new Promise(resolve => application.server.close(resolve));
      await start(false);
    },
  };
}

test('UT06.1-A: payload válido genera estado pendiente y usa el hospital de la sesión', async t => {
  const f = await fixture(t);
  const token = await f.login('hospital@hemolink.test');

  const payload = {
    grupoAbo: 'O',
    factorRh: 'positivo',
    cantidad: 5,
    prioridad: 'urgente',
  };

  const res = await f.request('/api/requests', { method: 'POST', body: payload, token });
  assert.equal(res.status, 201);
  const item = res.data.item;

  assert.ok(item.id, 'Debe asignar un ID único');
  assert.equal(typeof item.numero, 'number', 'Debe asignar un número correlativo');
  assert.ok(item.numero > 0, 'El número correlativo debe ser positivo');
  assert.equal(item.estado, 'pendiente');
  assert.equal(item.hospitalId, 'hospital-demo');
  assert.equal(item.scopeId, 'hospital-demo');
  assert.equal(item.grupoAbo, 'O');
  assert.equal(item.factorRh, 'positivo');
  assert.equal(item.cantidadSolicitada, 5);
  assert.equal(item.cantidadDespachada, 0);
  assert.equal(item.cantidadReservada, 0);
  assert.equal(item.pendienteAsignar, 5);
  assert.equal(item.pendienteEntregar, 5);
  assert.equal(item.prioridad, 'urgente');
  assert.equal(item.responsableId, 'hospital-demo');
  assert.ok(item.fechaRegistro, 'Debe registrar fecha y hora');

  // Recuperar al consultar por ID (ficha)
  const ficha = await f.request(`/api/requests/${item.id}`, { token });
  assert.equal(ficha.status, 200);
  assert.equal(ficha.data.item.id, item.id);
  assert.equal(ficha.data.item.numero, item.numero);
  assert.equal(ficha.data.item.estado, 'pendiente');

  // Persistencia tras reiniciar la aplicación y SQLite
  await f.restart();
  const tokenTrasReinicio = await f.login('hospital@hemolink.test');
  const fichaReiniciada = await f.request(`/api/requests/${item.id}`, { token: tokenTrasReinicio });
  assert.equal(fichaReiniciada.status, 200);
  assert.equal(fichaReiniciada.data.item.id, item.id);
  assert.equal(fichaReiniciada.data.item.numero, item.numero);
  assert.equal(fichaReiniciada.data.item.estado, 'pendiente');
});

test('UT06.1-B: cantidad 0, negativa, decimal, ABO/Rh o prioridad inválidos rechazan el alta', async t => {
  const f = await fixture(t);
  const token = await f.login('hospital@hemolink.test');

  const baseValida = {
    grupoAbo: 'A',
    factorRh: 'negativo',
    cantidad: 2,
    prioridad: 'normal',
  };

  const casosInvalidos = [
    { ...baseValida, cantidad: 0 },
    { ...baseValida, cantidad: -1 },
    { ...baseValida, cantidad: 2.5 },
    { ...baseValida, cantidad: '3' },
    { ...baseValida, cantidad: undefined },
    { ...baseValida, grupoAbo: 'Z' },
    { ...baseValida, grupoAbo: '' },
    { ...baseValida, grupoAbo: undefined },
    { ...baseValida, factorRh: 'neutro' },
    { ...baseValida, factorRh: '' },
    { ...baseValida, factorRh: undefined },
    { ...baseValida, prioridad: 'baja' },
    { ...baseValida, prioridad: '' },
    { ...baseValida, prioridad: undefined },
  ];

  for (const caso of casosInvalidos) {
    const res = await f.request('/api/requests', { method: 'POST', body: caso, token });
    assert.equal(res.status, 400, `Debe rechazar con 400: ${JSON.stringify(caso)}`);
  }

  // La base no debe contener solicitudes creadas por los casos rechazados
  const lista = await f.request('/api/requests', { token });
  assert.equal(lista.status, 200);
  const creadas = lista.data.items.filter(item => item.id !== 'demo-requests');
  assert.equal(creadas.length, 0);
});

test('UT06.1-C: sin sesión, rol ajeno e ID de otro hospital se rechazan', async t => {
  const f = await fixture(t);
  const tokenHospital1 = await f.login('hospital@hemolink.test');
  const tokenHospital2 = await f.login('hospital2@hemolink.test');
  const tokenEnfermeria = await f.login('enfermeria@hemolink.test');
  const tokenInventario = await f.login('inventario@hemolink.test');

  // Crear pedido con hospital 1
  const alta = await f.request('/api/requests', {
    method: 'POST',
    body: { grupoAbo: 'B', factorRh: 'positivo', cantidad: 3, prioridad: 'normal' },
    token: tokenHospital1,
  });
  assert.equal(alta.status, 201);
  const pedidoId = alta.data.item.id;

  // 1. Sin sesión (401)
  assert.equal((await f.request('/api/requests')).status, 401);
  assert.equal((await f.request(`/api/requests/${pedidoId}`)).status, 401);
  assert.equal((await f.request('/api/requests', { method: 'POST', body: { cantidad: 1 } })).status, 401);

  // 2. Rol ajeno (nursing no puede gestionar solicitudes)
  assert.equal((await f.request('/api/requests', { token: tokenEnfermeria })).status, 403);
  assert.equal((await f.request(`/api/requests/${pedidoId}`, { token: tokenEnfermeria })).status, 403);
  assert.equal((await f.request('/api/requests', { method: 'POST', body: { cantidad: 1 }, token: tokenEnfermeria })).status, 403);

  // 3. Inventario no puede crear pedidos, solo consultarlos
  assert.equal((await f.request('/api/requests', {
    method: 'POST',
    body: { grupoAbo: 'B', factorRh: 'positivo', cantidad: 1, prioridad: 'normal' },
    token: tokenInventario,
  })).status, 403);

  // 4. Hospital 2 no puede consultar pedido de Hospital 1 ni en ficha ni en su listado
  const fichaAjena = await f.request(`/api/requests/${pedidoId}`, { token: tokenHospital2 });
  assert.equal(fichaAjena.status, 404, 'No debe acceder a ficha de otro hospital');

  const listaHosp2 = await f.request('/api/requests', { token: tokenHospital2 });
  assert.equal(listaHosp2.status, 200);
  assert.ok(!listaHosp2.data.items.some(item => item.id === pedidoId), 'Lista de hospital 2 no debe incluir pedidos de hospital 1');
});

test('UT06.1-D: urgentes primero, orden antiguo primero y desempate estable', async t => {
  const f = await fixture(t);
  const tokenHospital = await f.login('hospital@hemolink.test');
  const tokenInventario = await f.login('inventario@hemolink.test');

  // t0: normal
  const r1 = await f.request('/api/requests', {
    method: 'POST', body: { grupoAbo: 'O', factorRh: 'positivo', cantidad: 1, prioridad: 'normal' }, token: tokenHospital,
  });
  f.advance(1000);

  // t1: urgente
  const r2 = await f.request('/api/requests', {
    method: 'POST', body: { grupoAbo: 'O', factorRh: 'positivo', cantidad: 2, prioridad: 'urgente' }, token: tokenHospital,
  });
  f.advance(1000);

  // t2: normal
  const r3 = await f.request('/api/requests', {
    method: 'POST', body: { grupoAbo: 'O', factorRh: 'positivo', cantidad: 3, prioridad: 'normal' }, token: tokenHospital,
  });
  f.advance(1000);

  // t3: urgente
  const r4 = await f.request('/api/requests', {
    method: 'POST', body: { grupoAbo: 'O', factorRh: 'positivo', cantidad: 4, prioridad: 'urgente' }, token: tokenHospital,
  });

  const id1 = r1.data.item.id;
  const id2 = r2.data.item.id;
  const id3 = r3.data.item.id;
  const id4 = r4.data.item.id;

  // Consultar como inventario (ve todos los pedidos ordenados)
  const bandejaInv = await f.request('/api/requests', { token: tokenInventario });
  assert.equal(bandejaInv.status, 200);

  const idsFiltrados = bandejaInv.data.items
    .map(i => i.id)
    .filter(id => [id1, id2, id3, id4].includes(id));

  // Urgentes primero (r2, r4), orden antiguo primero (r2 antes que r4).
  // Luego normales (r1, r3), orden antiguo primero (r1 antes que r3).
  assert.deepEqual(idsFiltrados, [id2, id4, id1, id3]);
});

test('UT06.1-E: solo incluir avisos y despachos vinculados al propio pedido', async t => {
  const f = await fixture(t);
  const token = await f.login('hospital@hemolink.test');

  const p1 = await f.request('/api/requests', {
    method: 'POST', body: { grupoAbo: 'A', factorRh: 'positivo', cantidad: 2, prioridad: 'normal' }, token,
  });
  const p2 = await f.request('/api/requests', {
    method: 'POST', body: { grupoAbo: 'B', factorRh: 'negativo', cantidad: 3, prioridad: 'normal' }, token,
  });

  const id1 = p1.data.item.id;
  const id2 = p2.data.item.id;

  // Insertar avisos y despachos asociados a ambos pedidos
  f.store.update(db => {
    db.records.push(
      { id: 'aviso-p1', module: 'notices', pedidoId: id1, scopeId: 'hospital-demo', faltante: 1 },
      { id: 'aviso-p2', module: 'notices', pedidoId: id2, scopeId: 'hospital-demo', faltante: 2 },
      { id: 'despacho-p1', module: 'dispatches', pedidoId: id1, scopeId: 'sede-central', tipo: 'programado' },
      { id: 'despacho-p2', module: 'dispatches', pedidoId: id2, scopeId: 'sede-central', tipo: 'urgente' },
    );
  });

  const ficha1 = await f.request(`/api/requests/${id1}`, { token });
  assert.equal(ficha1.status, 200);
  assert.equal(ficha1.data.item.avisos.length, 1);
  assert.equal(ficha1.data.item.avisos[0].id, 'aviso-p1');
  assert.equal(ficha1.data.item.despachos.length, 1);
  assert.equal(ficha1.data.item.despachos[0].id, 'despacho-p1');

  const ficha2 = await f.request(`/api/requests/${id2}`, { token });
  assert.equal(ficha2.status, 200);
  assert.equal(ficha2.data.item.avisos.length, 1);
  assert.equal(ficha2.data.item.avisos[0].id, 'aviso-p2');
  assert.equal(ficha2.data.item.despachos.length, 1);
  assert.equal(ficha2.data.item.despachos[0].id, 'despacho-p2');
});
