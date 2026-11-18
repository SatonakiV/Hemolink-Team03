import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DispatchError,
  validarComandoDespacho,
  crearComprobanteDespacho,
} from '../src/dispatches.mjs';

test('UT10.1-A: programado acepta fecha civil válida', () => {
  const comandoValido = validarComandoDespacho({
    tipo: 'programado',
    fechaPrevista: '2026-12-01',
    reservaIds: ['RES-001', 'RES-002'],
  });

  assert.equal(comandoValido.tipo, 'programado');
  assert.equal(comandoValido.fechaPrevista, '2026-12-01');
  assert.equal(comandoValido.motivo, null);
  assert.deepEqual(comandoValido.reservaIds, ['RES-001', 'RES-002']);

  const comprobante = crearComprobanteDespacho(comandoValido, {
    clock: () => new Date('2026-11-20T10:00:00Z').getTime(),
  });
  assert.equal(comprobante.tipo, 'programado');
  assert.equal(comprobante.fechaPrevista, '2026-12-01');
  assert.deepEqual(comprobante.reservaIds, ['RES-001', 'RES-002']);

  // Rechaza fecha inválida (formato incorrecto o fecha imposible como 2026-02-30)
  for (const fechaInvalida of ['', '2026-13-01', '2026-02-30', 'invalida']) {
    assert.throws(
      () =>
        validarComandoDespacho({
          tipo: 'programado',
          fechaPrevista: fechaInvalida,
          reservaIds: ['RES-001'],
        }),
      (err) => err instanceof DispatchError && err.status === 400
    );
  }
});

test('UT10.1-B: urgente acepta motivo y rechaza blancos', () => {
  const comandoValido = validarComandoDespacho({
    tipo: 'urgente',
    motivo: '  Cirugía de emergencia  ',
    reservaIds: ['RES-003'],
  });

  assert.equal(comandoValido.tipo, 'urgente');
  assert.equal(comandoValido.fechaPrevista, null);
  assert.equal(comandoValido.motivo, 'Cirugía de emergencia');
  assert.deepEqual(comandoValido.reservaIds, ['RES-003']);

  const comprobante = crearComprobanteDespacho(comandoValido, {
    clock: () => new Date('2026-11-20T11:00:00Z').getTime(),
  });
  assert.equal(comprobante.tipo, 'urgente');
  assert.equal(comprobante.motivo, 'Cirugía de emergencia');
  assert.deepEqual(comprobante.reservaIds, ['RES-003']);

  // Rechaza motivo ausente, vacío o compuesto solo de espacios en blanco
  for (const motivoInvalido of [undefined, null, '', '   ', '\t\n']) {
    assert.throws(
      () =>
        validarComandoDespacho({
          tipo: 'urgente',
          motivo: motivoInvalido,
          reservaIds: ['RES-003'],
        }),
      (err) => err instanceof DispatchError && err.status === 400
    );
  }
});

test('UT10.1-C: selección vacía o con IDs repetidos se rechaza', () => {
  // Rechaza selección no proporcionada, vacía o nula
  for (const seleccionInvalida of [undefined, null, [], 'no-array', {}]) {
    assert.throws(
      () =>
        validarComandoDespacho({
          tipo: 'programado',
          fechaPrevista: '2026-12-01',
          reservaIds: seleccionInvalida,
        }),
      (err) => err instanceof DispatchError && err.status === 400
    );
  }

  // Rechaza IDs vacíos dentro del arreglo
  assert.throws(
    () =>
      validarComandoDespacho({
        tipo: 'programado',
        fechaPrevista: '2026-12-01',
        reservaIds: ['RES-001', '   '],
      }),
    (err) => err instanceof DispatchError && err.status === 400
  );

  // Rechaza IDs de reserva duplicados (e.g. ['RES-001', 'RES-001'])
  assert.throws(
    () =>
      validarComandoDespacho({
        tipo: 'programado',
        fechaPrevista: '2026-12-01',
        reservaIds: ['RES-001', 'RES-002', 'RES-001'],
      }),
    (err) =>
      err instanceof DispatchError &&
      err.status === 400 &&
      err.message.includes('duplicados')
  );

  // Admite propiedad alternativa 'unidades' si es un arreglo válido sin duplicados
  const comandoConUnidades = validarComandoDespacho({
    tipo: 'urgente',
    motivo: 'Traslado de emergencia',
    unidades: ['RES-010', 'RES-011'],
  });
  assert.deepEqual(comandoConUnidades.reservaIds, ['RES-010', 'RES-011']);
});
