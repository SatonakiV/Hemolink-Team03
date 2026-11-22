import test from 'node:test';
import assert from 'node:assert/strict';
import { calcularPropuestaFefo } from '../src/reservation-preview.mjs';
import { SqliteStore } from '../src/sqlite-store.mjs';

const hoy = '2026-11-21';
const pedido = { grupoAbo: 'O', factorRh: 'positivo', pendienteAsignar: 3 };

function inventario(t) {
  const store = new SqliteStore(':memory:');
  t.after(() => store.close());

  function unidad(id, cambios = {}) {
    const scopeId = cambios.scopeId ?? 'sede-central';
    return {
      id, module: 'inventory', scopeId, codigo: `U-${id}`, donacionId: `DON-${scopeId}`,
      grupoAbo: 'O', factorRh: 'positivo', estado: 'disponible', fechaVencimiento: '2026-11-24',
      ...cambios,
    };
  }

  store.update(db => db.records.push(
    { id: 'DON-sede-central', module: 'donations', scopeId: 'sede-central' },
    { id: 'DON-sede-norte', module: 'donations', scopeId: 'sede-norte' },
    unidad('D', { fechaVencimiento: '2026-11-25' }),
    unidad('B'),
    unidad('A', { scopeId: 'sede-norte' }),
    unidad('C', { scopeId: 'sede-norte', fechaVencimiento: '2026-11-22' }),
    unidad('OTRO-ABO', { grupoAbo: 'A', fechaVencimiento: '2026-11-22' }),
    unidad('OTRO-RH', { factorRh: 'negativo', fechaVencimiento: '2026-11-22' }),
    unidad('HOY', { fechaVencimiento: hoy }),
    unidad('VENCIDA', { fechaVencimiento: '2026-11-20' }),
    unidad('RESERVADA', { estado: 'reservada' }),
    unidad('DESCARTADA', { estado: 'descartada' }),
    unidad('DESPACHADA', { estado: 'despachada' }),
    { id: 'SEMILLA', module: 'inventory', scopeId: 'sede-central' },
    { ...unidad('MUESTRA'), module: 'samples', codigo: null },
  ));
  return store;
}

test('UT08.2-A/B / CP08-01: cubre el saldo por vencimiento e ID con el ABO/Rh exacto y conserva la sede', t => {
  const store = inventario(t);
  const inventarioAntes = store.read();

  const propuesta = calcularPropuestaFefo(store, { ...pedido, hoy });
  const { unidades, ...resumen } = propuesta;
  assert.deepEqual(resumen, {
    estado: 'completa', pendienteAsignar: 3, stockElegible: 4, faltante: 0,
  });
  assert.deepEqual(unidades.map(({ id, sedeId, codigo, fechaVencimiento }) => ({
    id, sedeId, codigo, fechaVencimiento,
  })), [
    { id: 'C', sedeId: 'sede-norte', codigo: 'U-C', fechaVencimiento: '2026-11-22' },
    { id: 'A', sedeId: 'sede-norte', codigo: 'U-A', fechaVencimiento: '2026-11-24' },
    { id: 'B', sedeId: 'sede-central', codigo: 'U-B', fechaVencimiento: '2026-11-24' },
  ]);
  assert.ok(unidades.every(({ grupoAbo, factorRh }) => grupoAbo === pedido.grupoAbo && factorRh === pedido.factorRh));
  assert.equal(calcularPropuestaFefo(store, { ...pedido, hoy, pendienteAsignar: 4 }).unidades.length, 4);
  assert.deepEqual(store.read(), inventarioAntes);
});

test('UT08.2-C: distingue stock insuficiente, stock cero y pedido sin saldo por asignar', t => {
  const store = inventario(t);

  assert.deepEqual(calcularPropuestaFefo(store, { ...pedido, hoy, pendienteAsignar: 5 }), {
    estado: 'stock_insuficiente', pendienteAsignar: 5, stockElegible: 4, faltante: 1, unidades: [],
  });
  assert.deepEqual(calcularPropuestaFefo(store, { ...pedido, hoy, grupoAbo: 'AB' }), {
    estado: 'stock_insuficiente', pendienteAsignar: 3, stockElegible: 0, faltante: 3, unidades: [],
  });
  assert.deepEqual(calcularPropuestaFefo(store, { ...pedido, hoy, pendienteAsignar: 0 }), {
    estado: 'sin_saldo', pendienteAsignar: 0, stockElegible: 4, faltante: 0, unidades: [],
  });
});

test('rechaza un pedido o fecha inválidos antes de consultar inventario', () => {
  const sinStore = undefined;
  for (const cambio of [
    { grupoAbo: undefined }, { grupoAbo: 'Z' },
    { factorRh: undefined }, { factorRh: '+' },
    { pendienteAsignar: undefined }, { pendienteAsignar: -1 }, { pendienteAsignar: 1.5 },
    { hoy: undefined }, { hoy: '2026-11-31' },
  ]) {
    assert.throws(() => calcularPropuestaFefo(sinStore, { ...pedido, hoy, ...cambio }), RangeError);
  }
});
