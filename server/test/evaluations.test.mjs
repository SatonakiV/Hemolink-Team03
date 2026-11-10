import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';

const FECHA_FIJA = new Date('2026-11-08T15:00:00.000Z').getTime();

const BASE = {
  id: 'EV001',
  donanteId: 'D001',
  resultado: 'apto',
  fechaEvaluacion: '2026-11-05',
  fechaFinVigencia: '2026-11-20',
};

// Prepara una base temporal para cada prueba.
// Nunca modifica server/data/hemolink.json.
async function entorno(prueba) {
  const carpeta = await mkdtemp(join(tmpdir(), 'hemolink-t021-'));
  const archivo = join(carpeta, 'hemolink.json');

  const { server, store } = createApplication({
    databasePath: archivo,
    seedDemo: true,
    clock: () => FECHA_FIJA,
  });

  store.update(db => {
    db.records ??= [];
    db.records.push({
      module: 'donors',
      scopeId: 'sede-central',
      id: 'D001',
    });
  });

  await new Promise(resolve =>
    server.listen(0, '127.0.0.1', resolve)
  );

  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  async function solicitar(ruta, { metodo = 'GET', token, cuerpo } = {}) {
    const respuesta = await fetch(`${baseUrl}${ruta}`, {
      method: metodo,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(cuerpo ? { 'Content-Type': 'application/json' } : {}),
      },
      ...(cuerpo ? { body: JSON.stringify(cuerpo) } : {}),
    });

    return {
      estado: respuesta.status,
      datos: await respuesta.json(),
    };
  }

  try {
    const login = await solicitar('/api/login', {
      metodo: 'POST',
      cuerpo: {
        email: 'enfermeria@hemolink.test',
        password: 'DemoHemoLink2026!',
      },
    });

    assert.equal(login.estado, 200);
    assert.ok(login.datos.token);

    const token = login.datos.token;
    const api = (ruta, opciones = {}) =>
      solicitar(ruta, { ...opciones, token });

    await prueba({
      api,
      solicitar,
      store,
      archivo,
      usuarioId: login.datos.user.id,
    });
  } finally {
    await new Promise((resolve, reject) =>
      server.close(error => error ? reject(error) : resolve())
    );

    await rm(carpeta, { recursive: true, force: true });
  }
}

// UT1: comprueba los resultados permitidos y el responsable.
test('UT1: guarda los tres resultados y el responsable', async () => {
  await entorno(async ({ api, usuarioId }) => {
    const casos = [
      BASE,
      {
        id: 'EV002',
        donanteId: 'D001',
        resultado: 'diferido',
        fechaEvaluacion: '2026-11-06',
        fechaHabilitacion: '2026-11-15',
      },
      {
        id: 'EV003',
        donanteId: 'D001',
        resultado: 'rechazado',
        fechaEvaluacion: '2026-11-07',
      },
    ];

    for (const caso of casos) {
      const respuesta = await api('/api/evaluations', {
        metodo: 'POST',
        cuerpo: caso,
      });

      assert.equal(respuesta.estado, 201, JSON.stringify(respuesta.datos));
      assert.equal(respuesta.datos.item.resultado, caso.resultado);
      assert.equal(respuesta.datos.item.responsableId, usuarioId);
      assert.ok(respuesta.datos.item.fechaRegistro);
    }
  });
});

test('PR18: la última registrada es actual aunque su fecha clínica sea anterior y haya empate de registro', async () => {
  await entorno(async ({ api }) => {
    for (const caso of [
      { ...BASE, id: 'EV_Z', fechaEvaluacion: '2026-11-07' },
      { ...BASE, id: 'EV_A', fechaEvaluacion: '2026-11-05' },
      { ...BASE, id: 'EV_B', fechaEvaluacion: '2026-11-05' },
    ]) {
      const guardada = await api('/api/evaluations', { metodo: 'POST', cuerpo: caso });
      assert.equal(guardada.estado, 201);
    }
    const historial = await api('/api/evaluations?donanteId=D001');
    assert.deepEqual(historial.datos.items.map(item => item.id), ['EV_B', 'EV_A', 'EV_Z']);
    const historica = await api('/api/evaluations/EV_Z');
    assert.equal(historica.datos.item.fechaEvaluacion, '2026-11-07');
  });
});

test('PR18: servidor rechaza consultas y altas sin sesión o con rol ajeno sin alterar historial', async () => {
  await entorno(async ({ api, solicitar, store }) => {
    assert.equal((await api('/api/evaluations', { metodo: 'POST', cuerpo: BASE })).estado, 201);
    const registros = store.read().records;
    const accesos = [{ token: undefined, estado: 401 }];
    for (const email of ['inventario@hemolink.test', 'hospital@hemolink.test']) {
      const login = await solicitar('/api/login', {
        metodo: 'POST', cuerpo: { email, password: 'DemoHemoLink2026!' },
      });
      assert.equal(login.estado, 200);
      accesos.push({ token: login.datos.token, estado: 403 });
    }
    for (const { token, estado } of accesos) {
      for (const ruta of ['/api/evaluations', '/api/evaluations/EV001', '/api/evaluations?donanteId=D001']) {
        const respuesta = await solicitar(ruta, { token });
        assert.equal(respuesta.estado, estado);
        assert.equal(respuesta.datos.item, undefined);
        assert.equal(respuesta.datos.items, undefined);
      }
      assert.equal((await solicitar('/api/evaluations', {
        token, metodo: 'POST', cuerpo: { ...BASE, id: 'EV_DENEGADA' },
      })).estado, estado);
    }
    assert.deepEqual(store.read().records, registros);
  });
});

test('PR18: datos de otra sede no son consultables ni se aceptan como origen', async () => {
  await entorno(async ({ api, store }) => {
    store.update(db => db.records.push(
      { id: 'D_AJENO', module: 'donors', scopeId: 'otra-sede' },
      { ...BASE, id: 'EV_AJENA', donanteId: 'D_AJENO', module: 'evaluations', scopeId: 'otra-sede' },
    ));
    const registros = store.read().records;
    assert.equal((await api('/api/evaluations/EV_AJENA?siteId=otra-sede')).estado, 404);
    const listado = await api('/api/evaluations?donanteId=D_AJENO&siteId=otra-sede');
    assert.deepEqual(listado.datos.items, []);
    assert.equal((await api('/api/evaluations', {
      metodo: 'POST', cuerpo: { ...BASE, id: 'EV_NUEVA', donanteId: 'D_AJENO', scopeId: 'otra-sede' },
    })).estado, 404);
    assert.deepEqual(store.read().records, registros);
  });
});

// UT2: los intentos inválidos no deben alterar los registros.
test('UT2: rechaza registros incorrectos', async () => {
  await entorno(async ({ api }) => {
    // La base de demostración puede contener evaluaciones previas.
    const antes = await api('/api/evaluations');
    assert.equal(antes.estado, 200);

    const casos = [
      [{ ...BASE, donanteId: 'D999' }, 404],
      [{ ...BASE, resultado: 'desconocido' }, 400],
      [{ ...BASE, fechaFinVigencia: null }, 400],
      [{
        ...BASE,
        resultado: 'diferido',
        fechaFinVigencia: null,
      }, 400],
    ];

    for (const [cuerpo, esperado] of casos) {
      const respuesta = await api('/api/evaluations', {
        metodo: 'POST',
        cuerpo,
      });

      assert.equal(
        respuesta.estado,
        esperado,
        JSON.stringify(respuesta.datos),
      );
    }

    const despues = await api('/api/evaluations');
    assert.equal(despues.estado, 200);

    // Ningún intento inválido debió modificar el historial.
    assert.deepEqual(despues.datos.items, antes.datos.items);
  });
});

// UT3: comprueba restricciones de fechas.
test('UT3: rechaza fechas inconsistentes', async () => {
  await entorno(async ({ api }) => {
    const casos = [
      { ...BASE, fechaEvaluacion: '2026-11-09' },
      { ...BASE, fechaEvaluacion: '2026-02-30' },
      { ...BASE, fechaFinVigencia: '2026-11-04' },
      {
        ...BASE,
        resultado: 'diferido',
        fechaFinVigencia: null,
        fechaHabilitacion: '2026-11-04',
      },
    ];

    for (const cuerpo of casos) {
      const respuesta = await api('/api/evaluations', {
        metodo: 'POST',
        cuerpo,
      });

      assert.equal(
        respuesta.estado,
        400,
        JSON.stringify(respuesta.datos),
      );
    }
  });
});

// UT4: conserva registros anteriores y devuelve el más reciente primero.
test('UT4: conserva el historial y recupera la evaluación actual', async () => {
  await entorno(async ({ api }) => {
    const primera = await api('/api/evaluations', {
      metodo: 'POST',
      cuerpo: BASE,
    });
    assert.equal(primera.estado, 201);

    const segunda = await api('/api/evaluations', {
      metodo: 'POST',
      cuerpo: {
        id: 'EV002',
        donanteId: 'D001',
        resultado: 'rechazado',
        fechaEvaluacion: '2026-11-07',
      },
    });
    assert.equal(segunda.estado, 201);

    const historial = await api('/api/evaluations?donanteId=D001');

    assert.equal(historial.estado, 200);
    assert.equal(historial.datos.items.length, 2);

    // El historial está ordenado desde la evaluación más reciente.
    const actual = historial.datos.items[0];
    assert.equal(actual.id, 'EV002');
    assert.equal(actual.resultado, 'rechazado');

    // La evaluación anterior debe continuar almacenada.
    const anterior = await api('/api/evaluations/EV001');
    assert.equal(anterior.estado, 200);
    assert.equal(anterior.datos.item.resultado, 'apto');
  });
});

// UT5: comprueba que un fallo no destruya los registros previos.
test('UT5: un fallo de escritura conserva los datos anteriores', async () => {
  await entorno(async ({ api, store }) => {
    const primera = await api('/api/evaluations', {
      metodo: 'POST',
      cuerpo: BASE,
    });
    assert.equal(primera.estado, 201);

    const actualizarOriginal = store.update;

    // Simulamos un error en el almacenamiento.
    store.update = () => {
      throw new Error('Fallo de escritura simulado');
    };

    try {
      const fallo = await api('/api/evaluations', {
        metodo: 'POST',
        cuerpo: {
          id: 'EV002',
          donanteId: 'D001',
          resultado: 'rechazado',
          fechaEvaluacion: '2026-11-07',
        },
      });

      assert.equal(fallo.estado, 500);
    } finally {
      store.update = actualizarOriginal;
    }

    const historial = await api('/api/evaluations?donanteId=D001');

    assert.deepEqual(
      historial.datos.items.map(evaluacion => evaluacion.id),
      ['EV001'],
    );
  });
});
