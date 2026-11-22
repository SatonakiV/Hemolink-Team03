import { fechaValida } from './dates.mjs';

/** Calcula los saldos de un pedido con la cantidad de reservas vigentes ya determinada. */
export function calcularSaldosPedido({ cantidadSolicitada, cantidadDespachada, cantidadReservada }) {
  if (!Number.isSafeInteger(cantidadSolicitada) || cantidadSolicitada < 1) {
    throw new RangeError('La cantidad solicitada debe ser un entero positivo.');
  }
  if (!Number.isSafeInteger(cantidadDespachada) || cantidadDespachada < 0) {
    throw new RangeError('La cantidad despachada debe ser un entero no negativo.');
  }
  if (!Number.isSafeInteger(cantidadReservada) || cantidadReservada < 0) {
    throw new RangeError('La cantidad reservada debe ser un entero no negativo.');
  }

  const pendienteEntregar = cantidadSolicitada - cantidadDespachada;
  const pendienteAsignar = pendienteEntregar - cantidadReservada;
  if (pendienteAsignar < 0) {
    throw new RangeError('Las cantidades despachadas y reservadas superan lo solicitado.');
  }

  let estado = 'parcial';
  if (pendienteEntregar === 0) {
    estado = 'completado';
  } else if (cantidadDespachada === 0) {
    if (cantidadReservada === 0) estado = 'pendiente';
    else if (pendienteAsignar === 0) estado = 'reservado';
  }

  return {
    cantidadSolicitada,
    cantidadDespachada,
    cantidadReservada,
    pendienteAsignar,
    pendienteEntregar,
    estado,
  };
}

/**
 * Recibe una entrada por unidad asociada al pedido, con su estado actual y
 * fecha de vencimiento. La API proporciona hoy como fecha civil local.
 */
export function calcularSaldosPedidoConReservas({ cantidadSolicitada, cantidadDespachada, reservas, hoy }) {
  if (!fechaValida(hoy)) throw new RangeError('Ingresa una fecha de corte válida (AAAA-MM-DD).');
  if (!Array.isArray(reservas)) throw new TypeError('Las reservas deben estar en un arreglo.');

  let cantidadReservada = 0;
  for (const { estado, fechaVencimiento } of reservas) {
    if (estado !== 'reservada') continue;
    if (!fechaValida(fechaVencimiento)) {
      throw new RangeError('Una unidad reservada tiene una fecha de vencimiento inválida.');
    }
    if (hoy < fechaVencimiento) cantidadReservada += 1;
  }

  return calcularSaldosPedido({ cantidadSolicitada, cantidadDespachada, cantidadReservada });
}
