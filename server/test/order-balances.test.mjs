import test from 'node:test';
import assert from 'node:assert/strict';
import { calcularSaldosPedido, calcularSaldosPedidoConReservas } from '../src/order-balances.mjs';

const hoy = '2026-11-21';
const reservaVigente = () => ({ estado: 'reservada', fechaVencimiento: '2026-11-22' });

test('UT09.1-A: deriva saldos y los cuatro estados del pedido', () => {
  const casos = [
    { despachada: 0, reservada: 0, asignar: 8, entregar: 8, estado: 'pendiente' },
    { despachada: 0, reservada: 8, asignar: 0, entregar: 8, estado: 'reservado' },
    { despachada: 0, reservada: 3, asignar: 5, entregar: 8, estado: 'parcial' },
    { despachada: 2, reservada: 0, asignar: 6, entregar: 6, estado: 'parcial' },
    { despachada: 2, reservada: 6, asignar: 0, entregar: 6, estado: 'parcial' },
    { despachada: 8, reservada: 0, asignar: 0, entregar: 0, estado: 'completado' },
  ];

  for (const { despachada, reservada, asignar, entregar, estado } of casos) {
    const cantidades = { cantidadSolicitada: 8, cantidadDespachada: despachada, cantidadReservada: reservada };
    assert.deepEqual(calcularSaldosPedido(cantidades), {
      ...cantidades,
      pendienteAsignar: asignar,
      pendienteEntregar: entregar,
      estado,
    });
  }
});

test('UT09.1-B / CP09-02: vencer o descartar una reserva libera saldo para inventario', () => {
  const pedido = { cantidadSolicitada: 8, cantidadDespachada: 2 };
  const reservas = [reservaVigente(), reservaVigente(), reservaVigente()];
  const saldo = calcularSaldosPedidoConReservas({ ...pedido, hoy, reservas });
  assert.deepEqual(saldo, {
    ...pedido,
    cantidadReservada: 3,
    pendienteAsignar: 3,
    pendienteEntregar: 6,
    estado: 'parcial',
  });

  for (const cambio of [
    { fechaVencimiento: hoy },
    { fechaVencimiento: '2026-11-20' },
    { estado: 'vencida' },
    { estado: 'descartada' },
  ]) {
    const actualizadas = [{ ...reservas[0], ...cambio }, ...reservas.slice(1)];
    assert.deepEqual(calcularSaldosPedidoConReservas({ ...pedido, hoy, reservas: actualizadas }), {
      ...saldo,
      cantidadReservada: 2,
      pendienteAsignar: 4,
    });
  }

  const sinReservas = calcularSaldosPedidoConReservas({
    cantidadSolicitada: 1,
    cantidadDespachada: 0,
    hoy,
    reservas: [{ ...reservaVigente(), estado: 'descartada' }],
  });
  assert.equal(sinReservas.estado, 'pendiente');
});

test('UT09.1-C: rechaza cantidades inválidas y sobreasignaciones', () => {
  const cantidades = { cantidadSolicitada: 8, cantidadDespachada: 2, cantidadReservada: 3 };
  for (const campo of Object.keys(cantidades)) {
    for (const invalida of [-1, 1.5, '2', NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
      assert.throws(() => calcularSaldosPedido({ ...cantidades, [campo]: invalida }), RangeError);
    }
  }

  assert.throws(() => calcularSaldosPedido({
    cantidadSolicitada: 0, cantidadDespachada: 0, cantidadReservada: 0,
  }), RangeError);
  for (const sobreasignacion of [
    { cantidadDespachada: 9, cantidadReservada: 0 },
    { cantidadDespachada: 0, cantidadReservada: 9 },
    { cantidadDespachada: 6, cantidadReservada: 3 },
  ]) {
    assert.throws(() => calcularSaldosPedido({ ...cantidades, ...sobreasignacion }), RangeError);
  }

  assert.throws(() => calcularSaldosPedidoConReservas({
    cantidadSolicitada: 1, cantidadDespachada: 1, hoy, reservas: [reservaVigente()],
  }), RangeError);
});

test('despacho: una unidad entregada deja de contar como reserva y reduce el saldo por entregar', () => {
  const pedido = { cantidadSolicitada: 2, cantidadDespachada: 0, hoy };
  const reservas = [reservaVigente(), reservaVigente()];
  const antes = calcularSaldosPedidoConReservas({ ...pedido, reservas });
  assert.equal(antes.estado, 'reservado');
  assert.equal(antes.pendienteEntregar, 2);

  const despues = calcularSaldosPedidoConReservas({
    ...pedido,
    cantidadDespachada: 1,
    reservas: [{ ...reservas[0], estado: 'despachada' }, reservas[1]],
  });
  assert.deepEqual(despues, {
    cantidadSolicitada: 2,
    cantidadDespachada: 1,
    cantidadReservada: 1,
    pendienteAsignar: 0,
    pendienteEntregar: 1,
    estado: 'parcial',
  });
});

test('rechaza una fecha de corte o de vencimiento inválida', () => {
  const pedido = { cantidadSolicitada: 1, cantidadDespachada: 0, hoy, reservas: [reservaVigente()] };
  assert.throws(() => calcularSaldosPedidoConReservas({ ...pedido, hoy: '2026-11-31' }), RangeError);
  assert.throws(() => calcularSaldosPedidoConReservas({
    ...pedido, reservas: [{ estado: 'reservada', fechaVencimiento: undefined }],
  }), RangeError);
});
