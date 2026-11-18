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
