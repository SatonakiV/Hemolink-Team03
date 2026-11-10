import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApplication } from '../src/app.mjs';

test('T02.1: la evaluación persiste al reiniciar el servidor', async () => {
  // Base temporal: no modifica los datos del proyecto.
  const carpeta = await mkdtemp(join(tmpdir(), 'hemolink-reinicio-'));
  const archivo = join(carpeta, 'hemolink.json');
  const fecha = new Date('2026-11-08T15:00:00Z').getTime();

  let servidor;

  async function iniciar(crearSemillas) {
    const app = createApplication({
      databasePath: archivo,
      seedDemo: crearSemillas,
      clock: () => fecha,
    });

    servidor = app.server;

    await new Promise(resolve =>
      servidor.listen(0, '127.0.0.1', resolve),
    );

    return {
      url: `http://127.0.0.1:${servidor.address().port}`,
      store: app.store,
    };
  }

  async function detener() {
    if (servidor?.listening) {
      await new Promise((resolve, reject) =>
        servidor.close(error => error ? reject(error) : resolve()),
      );
    }
    servidor = null;
  }

  try {
    // 1. Iniciamos el backend y creamos un donante ficticio.
    const primera = await iniciar(true);

    primera.store.update(db => {
      db.records.push({
        id: 'D_T021',
        module: 'donors',
        scopeId: 'sede-central',
      });
    });

    // 2. Iniciamos sesión como enfermería.
    const login = await fetch(`${primera.url}/api/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'enfermeria@hemolink.test',
        password: 'DemoHemoLink2026!',
      }),
    });

    assert.equal(login.status, 200);
    const { token } = await login.json();

    // 3. Registramos una evaluación utilizando la API.
    const registro = await fetch(`${primera.url}/api/evaluations`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        id: 'EV_T021',
        donanteId: 'D_T021',
        resultado: 'apto',
        fechaEvaluacion: '2026-11-08',
        fechaFinVigencia: '2026-11-20',
      }),
    });

    assert.equal(registro.status, 201);

    // Una evaluación registrada después queda actual aunque sea retroactiva.
    const segundaEvaluacion = await fetch(`${primera.url}/api/evaluations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        id: 'EV_T021_NUEVA', donanteId: 'D_T021', resultado: 'rechazado',
        fechaEvaluacion: '2026-11-07',
      }),
    });
    assert.equal(segundaEvaluacion.status, 201);

    // 4. Apagamos completamente el servidor.
    await detener();

    // 5. Iniciamos otra instancia utilizando el mismo archivo.
    const segunda = await iniciar(false);

    // 6. Recuperamos la evaluación después del reinicio.
    const consulta = await fetch(
      `${segunda.url}/api/evaluations/EV_T021`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    );

    assert.equal(consulta.status, 200);

    const { item } = await consulta.json();

    assert.equal(item.id, 'EV_T021');
    assert.equal(item.donanteId, 'D_T021');
    assert.equal(item.resultado, 'apto');
    assert.equal(item.fechaFinVigencia, '2026-11-20');

    const historial = await fetch(`${segunda.url}/api/evaluations?donanteId=D_T021`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal(historial.status, 200);
    assert.deepEqual((await historial.json()).items.map(evaluacion => evaluacion.id),
      ['EV_T021_NUEVA', 'EV_T021']);

  } finally {
    await detener();
    await rm(carpeta, { recursive: true, force: true });
  }
});
