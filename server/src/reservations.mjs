import { createHash } from 'node:crypto';

import { activeSession } from './auth.mjs';
import { FACTORES_RH, GRUPOS_ABO } from './blood-groups.mjs';
import { fechaLocal } from './dates.mjs';
import { registrarUnidadesReservadas } from './inventory.mjs';
import { calcularSaldosPedidoConReservas, obtenerReservasPedido } from './order-balances.mjs';
import { calcularPropuestaFefo } from './reservation-preview.mjs';
import { SolicitudError } from './requests.mjs';

function buscarPedido(db, pedidoId) {
  const pedido = db.records.find(item => item.module === 'requests' && item.id === pedidoId);
  if (!pedido) throw new SolicitudError(404, 'Solicitud no encontrada.');
  if (!GRUPOS_ABO.includes(pedido.grupoAbo) || !FACTORES_RH.includes(pedido.factorRh) ||
      !Number.isSafeInteger(pedido.cantidadSolicitada) || pedido.cantidadSolicitada < 1) {
    throw new SolicitudError(409, 'La solicitud no tiene los datos necesarios para reservar.');
  }
  return pedido;
}

function detalleReserva(db, pedido, hoy) {
  const reservas = obtenerReservasPedido(db, pedido);
  const saldos = calcularSaldosPedidoConReservas({
    cantidadSolicitada: pedido.cantidadSolicitada,
    cantidadDespachada: pedido.cantidadDespachada ?? 0,
    reservas,
    hoy,
  });
  const propuesta = calcularPropuestaFefo({ read: () => db }, {
    grupoAbo: pedido.grupoAbo,
    factorRh: pedido.factorRh,
    pendienteAsignar: saldos.pendienteAsignar,
    hoy,
  });
  // La huella identifica la propuesta mostrada y mantiene acotado el cuerpo de confirmación.
  const version = propuesta.estado === 'completa'
    ? createHash('sha256').update(JSON.stringify([pedido.id, saldos, propuesta.unidades])).digest('hex')
    : null;
  return {
    saldos,
    reservas: reservas.filter(reserva => hoy < reserva.fechaVencimiento)
      .sort((a, b) => a.fechaVencimiento.localeCompare(b.fechaVencimiento) || a.id.localeCompare(b.id, 'en')),
    propuesta: { ...propuesta, version },
  };
}

export function consultarReservaCompleta(store, pedidoId, hoy) {
  const db = store.read({ records: {} });
  return detalleReserva(db, buscarPedido(db, pedidoId), hoy);
}

export function confirmarReservaCompleta({ store, sessionTokenHash, clock, pedidoId, version }) {
  if (typeof version !== 'string' || !/^[a-f0-9]{64}$/.test(version)) {
    throw new SolicitudError(400, 'Se requiere una propuesta FEFO válida.');
  }

  let resultado;
  store.update(db => {
    const instante = clock();
    const sesion = activeSession(db, sessionTokenHash, instante);
    if (!sesion) throw new SolicitudError(401, 'La sesión no es válida. Inicia sesión nuevamente.');
    const { user } = sesion;
    if (user.role !== 'inventory') {
      throw new SolicitudError(403, 'Solo inventario puede reservar unidades.');
    }
    const hoy = fechaLocal(() => instante);
    const ahora = new Date(instante).toISOString();
    const pedido = buscarPedido(db, pedidoId);
    const { propuesta } = detalleReserva(db, pedido, hoy);
    if (propuesta.version !== version) {
      throw new SolicitudError(409, 'Cambió el stock o el saldo de la solicitud. Recalcula la propuesta.');
    }

    const ids = new Set(propuesta.unidades.map(unidad => unidad.id));
    const unidades = db.records.filter(item => item.module === 'inventory' && ids.has(item.id));
    registrarUnidadesReservadas(unidades, pedido, user, { hoy, ahora });
    resultado = detalleReserva(db, pedido, hoy);
    Object.assign(pedido, resultado.saldos, {
      usuarioModificacionId: user.id,
      fechaModificacion: ahora,
    });
  });
  return resultado;
}
