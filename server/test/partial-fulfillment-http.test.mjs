
import test from 'node:test';
import assert from 'node:assert/strict';

import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createApplication } from '../src/app.mjs';

const AHORA = Date.parse('2026-11-22T15:00:00.000Z');
const PASSWORD = 'DemoHemoLink2026!';
const PEDIDO = 'PED-T092';
const IDS = ['UNI-T092-A', 'UNI-T092-B'];

async function fixture(t) {
  const carpeta = mkdtempSync(
    join(tmpdir(), 'hemolink-t092-http-'),
  );
  const databasePath = join(carpeta, 'pruebas.sqlite');

  const opciones = {
    databasePath,
    seedDemo: true,
    clock: () => AHORA,
  };

  let app = createApplication(opciones);
  let base;

  app.store.update(db => {
    db.records.push(
      {
        id: PEDIDO,
        module: 'requests',
        scopeId: 'hospital-demo',
        hospitalId: 'hospital-demo',
        grupoAbo: 'O',
        factorRh: 'positivo',
        prioridad: 'normal',
        cantidadSolicitada: 5,
        cantidadDespachada: 0,
        cantidadReservada: 0,
        pendienteAsignar: 5,
        pendienteEntregar: 5,
        estado: 'pendiente',
      },
      {
        id: 'DON-T092',
        module: 'donations',
        scopeId: 'sede-central',
      },
      ...IDS.map((id, index) => ({
        id,
        module: 'inventory',
        scopeId: 'sede-central',
        codigo: `COD-T092-${index + 1}`,
        donacionId: 'DON-T092',
        grupoAbo: 'O',
        factorRh: 'positivo',
        estado: 'disponible',
        fechaVencimiento:
          index === 0 ? '2026-11-28' : '2026-12-10',
      })),
    );
  });

  async function iniciar() {
    await new Promise(resolve =>
      app.server.listen(0, '127.0.0.1', resolve),
    );

    base = `http://127.0.0.1:${app.server.address().port}`;
  }

  await iniciar();

  t.after(async () => {
    if (app.server.listening) {
      await new Promise(resolve =>
        app.server.close(resolve),
      );
    }
    rmSync(carpeta, {
      recursive: true,
      force: true,
    });
  });

  async function request(
    path,
    { method = 'GET', token, body } = {},
  ) {
    const response = await fetch(base + path, {
      method,
      headers: {
        ...(token
          ? { Authorization: `Bearer ${token}` }
          : {}),
        ...(body !== undefined
          ? { 'Content-Type': 'application/json' }
          : {}),
      },
      ...(body !== undefined
        ? { body: JSON.stringify(body) }
        : {}),
    });

    return {
      status: response.status,
      data: await response.json(),
    };
  }

  async function login(email) {
    const resultado = await request('/api/login', {
      method: 'POST',
      body: { email, password: PASSWORD },
    });

    assert.equal(resultado.status, 200);
    return resultado.data.token;
  }

  async function reiniciar() {
    await new Promise(resolve =>
      app.server.close(resolve),
    );

    app = createApplication({
      ...opciones,
      seedDemo: false,
    });

    await iniciar();
  }

  return {
    get store() {
      return app.store;
    },
    request,
    login,
    reiniciar,
  };
}

const ruta = `/api/requests/${PEDIDO}/partial-fulfillment`;

test('HTTP T09.2: aceptar persiste reservas, aviso y saldos', async t => {
  const f = await fixture(t);
  const inventario = await f.login(
    'inventario@hemolink.test',
  );

  const resultado = await f.request(ruta, {
    method: 'POST',
    token: inventario,
    body: {
      decision: 'aceptar',
      unidadesPropuestas: IDS,
    },
  });

  assert.equal(resultado.status, 200);
  assert.deepEqual(resultado.data.reservaIds, IDS);
  assert.equal(resultado.data.aviso.cantidadFaltante, 3);
  assert.equal(resultado.data.saldos.pendienteAsignar, 3);

  const hospital = await f.login(
    'hospital@hemolink.test',
  );

  const ficha = await f.request(
    `/api/requests/${PEDIDO}`,
    { token: hospital },
  );

  assert.equal(ficha.status, 200);
  assert.equal(ficha.data.item.cantidadReservada, 2);
  assert.equal(ficha.data.item.pendienteAsignar, 3);
  assert.equal(ficha.data.item.pendienteEntregar, 5);
  assert.equal(ficha.data.item.avisos.length, 1);

  await f.reiniciar();

  const hospitalNuevo = await f.login(
    'hospital@hemolink.test',
  );

  const reiniciada = await f.request(
    `/api/requests/${PEDIDO}`,
    { token: hospitalNuevo },
  );

  assert.equal(reiniciada.status, 200);
  assert.equal(reiniciada.data.item.avisos.length, 1);
  assert.equal(reiniciada.data.item.cantidadReservada, 2);
});

test('HTTP T09.2: rechazar no genera reservas', async t => {
  const f = await fixture(t);
  const token = await f.login(
    'inventario@hemolink.test',
  );

  const resultado = await f.request(ruta, {
    method: 'POST',
    token,
    body: {
      decision: 'rechazar',
      unidadesPropuestas: [],
    },
  });

  assert.equal(resultado.status, 200);
  assert.deepEqual(resultado.data.reservaIds, []);
  assert.equal(resultado.data.aviso.cantidadFaltante, 5);

  const db = f.store.read();
  assert.equal(
    db.records.filter(
      r => r.module === 'inventory' &&
        r.pedidoId === PEDIDO,
    ).length,
    0,
  );
});

test('HTTP T09.2: stock cero registra el aviso', async t => {
  const f = await fixture(t);

  f.store.update(db => {
    for (const unidad of db.records) {
      if (IDS.includes(unidad.id)) {
        unidad.estado = 'descartada';
      }
    }
  });

  const token = await f.login(
    'inventario@hemolink.test',
  );

  const resultado = await f.request(ruta, {
    method: 'POST',
    token,
    body: {
      decision: 'aceptar',
      unidadesPropuestas: [],
    },
  });

  assert.equal(resultado.status, 200);
  assert.deepEqual(resultado.data.reservaIds, []);
  assert.equal(resultado.data.aviso.cantidadFaltante, 5);
});

test('HTTP T09.2: propuesta obsoleta devuelve 409', async t => {
  const f = await fixture(t);
  const token = await f.login(
    'inventario@hemolink.test',
  );

  f.store.update(db => {
    const unidad = db.records.find(
      r => r.module === 'inventory' &&
        r.id === IDS[1],
    );
    unidad.estado = 'descartada';
  });

  const anterior = f.store.read();

  const resultado = await f.request(ruta, {
    method: 'POST',
    token,
    body: {
      decision: 'aceptar',
      unidadesPropuestas: IDS,
    },
  });

  assert.equal(resultado.status, 409);
  assert.deepEqual(f.store.read(), anterior);
});

test('HTTP T09.2: rechaza roles ajenos y datos invalidos', async t => {
  const f = await fixture(t);

  const hospital = await f.login(
    'hospital@hemolink.test',
  );
  const enfermeria = await f.login(
    'enfermeria@hemolink.test',
  );
  const inventario = await f.login(
    'inventario@hemolink.test',
  );

  const body = {
    decision: 'aceptar',
    unidadesPropuestas: IDS,
  };

  assert.equal(
    (await f.request(ruta, {
      method: 'POST',
      body,
    })).status,
    401,
  );

  for (const token of [hospital, enfermeria]) {
    assert.equal(
      (await f.request(ruta, {
        method: 'POST',
        token,
        body,
      })).status,
      403,
    );
  }

  assert.equal(
    (await f.request(ruta, {
      method: 'POST',
      token: inventario,
      body: {
        decision: 'incorrecta',
        unidadesPropuestas: IDS,
      },
    })).status,
    400,
  );
});

test('HTTP T09.2: dos confirmaciones concurrentes no duplican reservas', async t => {
  const f = await fixture(t);
  const token = await f.login(
    'inventario@hemolink.test',
  );

  const opciones = {
    method: 'POST',
    token,
    body: {
      decision: 'aceptar',
      unidadesPropuestas: IDS,
    },
  };

  const resultados = await Promise.all([
    f.request(ruta, opciones),
    f.request(ruta, opciones),
  ]);

  assert.deepEqual(
    resultados.map(r => r.status).sort((a, b) => a - b),
    [200, 409],
  );

  const db = f.store.read();

  assert.equal(
    db.records.filter(
      r => r.module === 'inventory' &&
        r.estado === 'reservada' &&
        r.pedidoId === PEDIDO,
    ).length,
    2,
  );

  assert.equal(
    db.records.filter(
      r => r.module === 'notices' &&
        r.pedidoId === PEDIDO,
    ).length,
    1,
  );
});
