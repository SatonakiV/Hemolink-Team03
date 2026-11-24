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

// Las reservas antiguas pueden omitir su fecha y usar el vencimiento de la unidad.
export function fechaLimiteReserva(unidad, reserva) {
  const fechaUnidad = unidad?.fechaVencimiento;
  const fechaReserva = reserva?.fechaVencimiento;
  if (unidad && !fechaValida(fechaUnidad)) return null;
  if (fechaReserva === undefined) return fechaUnidad ?? null;
  if (!fechaValida(fechaReserva)) return null;
  return fechaUnidad && fechaUnidad < fechaReserva ? fechaUnidad : fechaReserva;
}

export function calcularSaldosPedidoActuales(db, pedido, hoy) {
  const unidades = new Map();
  const vencimientos = new Map();
  for (const registro of db.records) {
    if (registro.module !== 'inventory') continue;
    unidades.set(registro.id, registro);
    if (registro.estado === 'reservada' && registro.pedidoId === pedido.id) {
      vencimientos.set(registro.id, fechaLimiteReserva(registro));
    }
  }

  for (const reserva of db.records) {
    if (reserva.module !== 'reservations' || reserva.estado !== 'reservada' ||
        reserva.pedidoId !== pedido.id) continue;
    const unidad = unidades.get(reserva.unidadId);
    if (unidad && (unidad.estado !== 'reservada' || unidad.scopeId !== reserva.scopeId ||
        (unidad.pedidoId != null && unidad.pedidoId !== pedido.id))) continue;

    const unidadId = reserva.unidadId ?? reserva.id;
    const fecha = fechaLimiteReserva(unidad, reserva);
    const anterior = vencimientos.get(unidadId);
    if (anterior === undefined || fecha === null || (anterior !== null && fecha < anterior)) {
      vencimientos.set(unidadId, fecha);
    }
  }

  return calcularSaldosPedidoConReservas({
    cantidadSolicitada: pedido.cantidadSolicitada,
    cantidadDespachada: pedido.cantidadDespachada ?? 0,
    reservas: Array.from(vencimientos.values(), fechaVencimiento => ({
      estado: 'reservada', fechaVencimiento,
    })),
    hoy,
  });
}
