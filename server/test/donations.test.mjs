import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';
import { JsonStore } from '../src/json-store.mjs';

// Reloj fijo: 2026-11-08. Nunca toca server/data/hemolink.json.
const FECHA_FIJA = new Date('2026-11-08T15:00:00.000Z').getTime();

const DONANTE = {
  rut: '12.345.678-5', nombre: 'Donante Prueba', fechaNacimiento: '1998-05-10',
  pesoKg: 70, grupoAbo: 'O', factorRh: 'positivo', telefono: '912345678',
};
const EVALUACION = {
  id: 'EV001', resultado: 'apto',
  fechaEvaluacion: '2026-11-02', fechaFinVigencia: '2026-11-13',
};
const DONACION = {
  evaluacionId: 'EV001', fechaExtraccion: '2026-11-03', volumenMl: 450,
  unidades: [{ codigo: 'U-001' }],
};

async function entorno(prueba) {
  const carpeta = await mkdtemp(join(tmpdir(), 'hemolink-t031-'));
  const archivo = join(carpeta, 'hemolink.json');
  const { server, store } = createApplication({
    databasePath: archivo, seedDemo: true, clock: () => FECHA_FIJA,
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
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
    return { estado: respuesta.status, datos: await respuesta.json() };
  }
  const entrar = async email => (await solicitar('/api/login', {
    metodo: 'POST', cuerpo: { email, password: 'DemoHemoLink2026!' },
  })).datos;

  try {
    const sesion = await entrar('enfermeria@hemolink.test');
    const api = (ruta, opciones = {}) => solicitar(ruta, { ...opciones, token: sesion.token });
    const donante = (await api('/api/donors', { metodo: 'POST', cuerpo: DONANTE })).datos.item;
    assert.ok(donante?.id, 'el donante de prueba debe crearse');
    const evaluacion = await api('/api/evaluations', {
      metodo: 'POST', cuerpo: { ...EVALUACION, donanteId: donante.id },
    });
    assert.equal(evaluacion.estado, 201);
    const donar = (cambios = {}) => api('/api/donations', {
      metodo: 'POST', cuerpo: { ...DONACION, donanteId: donante.id, ...cambios },
    });
    const registros = () => store.read().records.length;
    await prueba({ api, donar, donante, store, archivo, entrar, solicitar, registros, sesion });
  } finally {
    await new Promise((resolve, reject) =>
      server.close(error => error ? reject(error) : resolve()));
    await rm(carpeta, { recursive: true, force: true });
  }
}

test('UT03.1-A: registro válido conserva relaciones, metadatos y persiste en disco', async () => {
  await entorno(async ({ api, donar, donante, archivo, sesion }) => {
    const creada = await donar();
    assert.equal(creada.estado, 201, JSON.stringify(creada.datos));

    const detalle = (await api(`/api/donations/${creada.datos.item.id}`)).datos.item;
    assert.equal(detalle.donanteId, donante.id);
    assert.equal(detalle.donante.id, donante.id);
    assert.equal(detalle.evaluacionId, 'EV001');
    assert.equal(detalle.evaluacion.id, 'EV001');
    assert.equal(detalle.fechaExtraccion, '2026-11-03');
    assert.equal(detalle.volumenMl, 450);
    assert.equal(detalle.sedeId, 'sede-central');
    assert.equal(detalle.responsableId, sesion.user.id);
    assert.ok(detalle.fechaRegistro);

    assert.equal(detalle.unidades.length, 1);
    const [unidad] = detalle.unidades;
    assert.ok(unidad.id);
    assert.equal(unidad.codigo, 'U-001');
    assert.equal(unidad.donacionId, detalle.id);
    assert.equal(unidad.grupoAbo, 'O');
    assert.equal(unidad.factorRh, 'positivo');
    assert.equal(unidad.sedeId, 'sede-central');
    assert.equal(unidad.estado, 'disponible');
    assert.equal(unidad.fechaVencimiento, '2026-12-15'); // 3-nov + 42 días

    // Recarga: una base nueva sobre el mismo archivo ve lo confirmado.
    const recargada = new JsonStore(archivo).read().records;
    assert.ok(recargada.some(r => r.module === 'donations' && r.id === detalle.id));
    assert.ok(recargada.some(r => r.module === 'inventory' && r.codigo === 'U-001'));
  });
});

test('UT03.1-B: relaciones obligatorias; cada rechazo no deja registros', async () => {
  await entorno(async ({ donar, registros }) => {
    const casos = [
      ['sin donante', { donanteId: undefined }, 400],
      ['donante inexistente', { donanteId: 'NO_EXISTE' }, 404],
      ['sin evaluación', { evaluacionId: undefined }, 400],
      ['evaluación inexistente', { evaluacionId: 'EV999' }, 404],
      ['sin unidades', { unidades: [] }, 400],
      ['unidades ausentes', { unidades: undefined }, 400],
      ['sede ajena enviada', { sedeId: 'sede-b' }, 409],
    ];
    const antes = registros();
    for (const [nombre, cambios, estado] of casos) {
      const r = await donar(cambios);
      assert.equal(r.estado, estado, `${nombre}: ${JSON.stringify(r.datos)}`);
    }
    assert.equal(registros(), antes, 'ningún rechazo puede dejar registros');
  });
});

test('UT03.1-B: evaluación de otro donante se rechaza', async () => {
  await entorno(async ({ api, donar, registros }) => {
    const otro = (await api('/api/donors', {
      metodo: 'POST', cuerpo: { ...DONANTE, rut: '7.654.321-6', nombre: 'Otro' },
    })).datos.item;
    await api('/api/evaluations', {
      metodo: 'POST', cuerpo: { ...EVALUACION, id: 'EV_OTRO', donanteId: otro.id },
    });
    const antes = registros();
    const r = await donar({ evaluacionId: 'EV_OTRO' });
    assert.equal(r.estado, 404);
    assert.equal(registros(), antes);
  });
});

test('UT03.1-C: código de unidad duplicado se rechaza sin confirmación parcial', async () => {
  await entorno(async ({ donar, registros }) => {
    assert.equal((await donar()).estado, 201);
    const antes = registros();

    // Mismo código en otra donación, aunque venga con otra capitalización.
    const repetida = await donar({ unidades: [{ codigo: 'U-002' }, { codigo: 'u-001' }] });
    assert.equal(repetida.estado, 409);
    // Repetido dentro de la misma solicitud.
    const interno = await donar({ unidades: [{ codigo: 'U-005' }, { codigo: 'U-005' }] });
    assert.equal(interno.estado, 400);

    assert.equal(registros(), antes, 'ni la donación ni U-002 quedaron guardadas');
    assert.equal((await donar({ unidades: [{ codigo: 'U-002' }] })).estado, 201,
      'U-002 no quedó reservado por el intento fallido');
  });
});

test('UT03.1-D: cambiar el grupo del donante no altera las unidades anteriores', async () => {
  await entorno(async ({ api, donar, donante, store }) => {
    const { datos } = await donar();
    // HU04 aún no expone la corrección por API: se simula sobre el registro del donante.
    store.update(db => {
      const registro = db.records.find(r => r.id === donante.id);
      registro.grupoAbo = 'A';
      registro.factorRh = 'negativo';
    });
    const detalle = (await api(`/api/donations/${datos.item.id}`)).datos.item;
    assert.equal(detalle.donante.grupoAbo, 'A');
    assert.equal(detalle.unidades[0].grupoAbo, 'O');
    assert.equal(detalle.unidades[0].factorRh, 'positivo');
  });
});

test('CP03-06: grupo contradictorio y vencimiento manual no se guardan', async () => {
  await entorno(async ({ donar, registros }) => {
    const antes = registros();
    const grupo = await donar({ unidades: [{ codigo: 'U-010', grupoAbo: 'A', factorRh: 'negativo' }] });
    assert.equal(grupo.estado, 409);
    const manual = await donar({ unidades: [{ codigo: 'U-011', fechaVencimiento: '2030-01-01' }] });
    assert.equal(manual.estado, 400);
    const global = await donar({ fechaVencimiento: '2030-01-01' });
    assert.equal(global.estado, 400);
    assert.equal(registros(), antes);
  });
});

test('CP03-03/05: extracción futura, volumen inválido y aptitud inválida se rechazan', async () => {
  await entorno(async ({ api, donar, donante, registros }) => {
    const antes = registros();
    for (const cambios of [
      { fechaExtraccion: '2026-11-09' },            // futura respecto del reloj
      { volumenMl: 0 }, { volumenMl: -1 }, { volumenMl: 450.5 },
      { fechaExtraccion: '2026-11-01' },            // antes de la evaluación
    ]) {
      const r = await donar(cambios);
      assert.ok([400, 409].includes(r.estado), JSON.stringify([cambios, r.datos]));
    }
    // Un diferido como evaluación vigente impide donar.
    await api('/api/evaluations', { metodo: 'POST', cuerpo: {
      id: 'EV002', donanteId: donante.id, resultado: 'diferido',
      fechaEvaluacion: '2026-11-04', fechaHabilitacion: '2026-11-20',
    } });
    assert.equal((await donar({ evaluacionId: 'EV002' })).estado, 409);
    // Y la evaluación apta anterior ya no es la vigente.
    assert.equal((await donar()).estado, 409);
    assert.equal(registros() - antes, 1, 'solo la evaluación diferida; ninguna donación');
  });
});

test('CP03-11: sin sesión o con rol ajeno el servidor rechaza sin crear registros', async () => {
  await entorno(async ({ entrar, solicitar, donante, registros }) => {
    const antes = registros();
    const cuerpo = { ...DONACION, donanteId: donante.id };
    const sinSesion = await solicitar('/api/donations', { metodo: 'POST', cuerpo });
    assert.equal(sinSesion.estado, 401);
    for (const email of ['inventario@hemolink.test', 'hospital@hemolink.test']) {
      const { token } = await entrar(email);
      const escritura = await solicitar('/api/donations', { metodo: 'POST', token, cuerpo });
      const lectura = await solicitar('/api/donations', { token });
      assert.equal(escritura.estado, 403, email);
      assert.equal(lectura.estado, 403, email);
      assert.equal(JSON.stringify(lectura.datos).includes('Donante Prueba'), false);
    }
    assert.equal(registros(), antes);
  });
});
