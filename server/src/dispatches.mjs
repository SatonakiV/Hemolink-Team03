import { randomUUID } from 'node:crypto';
import { fechaValida } from './dates.mjs';
import { calcularSaldosPedidoConReservas } from './order-balances.mjs';

const CLAVE = /^[A-Za-z0-9_-]{1,64}$/;

export class DispatchError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const huellaDespacho = (pedidoId, tipo, fechaPrevista, motivo, reservaIds) =>
  JSON.stringify([
    pedidoId,
    tipo,
    fechaPrevista ?? null,
    motivo ?? null,
    [...(reservaIds ?? [])].map(id => id.trim()).sort(),
  ]);

export function confirmacionPreviaDespacho(db, user, datos, pedidoId) {
  if (!datos?.claveConfirmacion) return null;
  const previa = db.records.find(
    r =>
      r.module === 'dispatches' &&
      r.scopeId === user.siteId &&
      r.claveConfirmacion === datos.claveConfirmacion,
  );
  if (!previa) return null;

  const huellaExistente = huellaDespacho(
    previa.pedidoId,
    previa.tipo,
    previa.fechaPrevista,
    previa.motivo,
    previa.reservaIds,
  );
  const huellaNueva = huellaDespacho(
    pedidoId ?? datos.pedidoId,
    datos.tipo,
    datos.fechaPrevista,
    datos.motivo,
    datos.reservaIds ?? datos.unidades,
  );

  if (huellaExistente !== huellaNueva) {
    throw new DispatchError(409, 'La clave de confirmación ya se usó con otros datos.');
  }
  return previa;
}

export function validarComandoDespacho(datos, hoy) {
  if (!datos || typeof datos !== 'object') {
    throw new DispatchError(400, 'Ingresa los datos del despacho.');
  }

  const tipo = typeof datos.tipo === 'string' ? datos.tipo.trim().toLowerCase() : '';
  if (tipo !== 'programado' && tipo !== 'urgente') {
    throw new DispatchError(400, 'El tipo de despacho debe ser programado o urgente.');
  }

  let fechaPrevista = null;
  let motivo = null;

  if (tipo === 'programado') {
    const rawFecha = typeof datos.fechaPrevista === 'string' ? datos.fechaPrevista.trim() : '';
    if (!fechaValida(rawFecha)) {
      throw new DispatchError(400, 'Ingresa una fecha prevista válida (AAAA-MM-DD).');
    }
    if (hoy && rawFecha < hoy) {
      throw new DispatchError(400, 'La fecha prevista no puede ser anterior a la fecha actual.');
    }
    fechaPrevista = rawFecha;
  } else if (tipo === 'urgente') {
    const rawMotivo = typeof datos.motivo === 'string' ? datos.motivo.trim() : '';
    if (rawMotivo.length === 0) {
      throw new DispatchError(400, 'Ingresa un motivo válido para el despacho urgente.');
    }
    motivo = rawMotivo;
  }

  const rawIds = Array.isArray(datos.reservaIds)
    ? datos.reservaIds
    : Array.isArray(datos.unidades)
    ? datos.unidades
    : null;

  if (!rawIds || rawIds.length === 0) {
    throw new DispatchError(400, 'Selecciona al menos una reserva para despachar.');
  }

  const reservaIds = rawIds.map(id => (typeof id === 'string' ? id.trim() : ''));
  if (reservaIds.some(id => id.length === 0)) {
    throw new DispatchError(400, 'Los identificadores de reserva no pueden estar vacíos.');
  }

  const conjuntoUnico = new Set(reservaIds);
  if (conjuntoUnico.size !== reservaIds.length) {
    throw new DispatchError(400, 'La selección no puede contener identificadores de reserva duplicados.');
  }

  let claveConfirmacion = undefined;
  if (datos.claveConfirmacion !== undefined) {
    if (typeof datos.claveConfirmacion !== 'string' || !CLAVE.test(datos.claveConfirmacion)) {
      throw new DispatchError(400, 'La clave de confirmación no es válida.');
    }
    claveConfirmacion = datos.claveConfirmacion;
  }

  let sedeId = undefined;
  if (datos.sedeId !== undefined) {
    if (typeof datos.sedeId !== 'string' || datos.sedeId.trim().length === 0) {
      throw new DispatchError(400, 'La sede no es válida.');
    }
    sedeId = datos.sedeId.trim();
  }

  return {
    tipo,
    fechaPrevista,
    motivo,
    reservaIds: Array.from(conjuntoUnico),
    ...(claveConfirmacion !== undefined ? { claveConfirmacion } : {}),
    ...(sedeId !== undefined ? { sedeId } : {}),
  };
}

export function crearComprobanteDespacho(comandoValido, opciones = {}) {
  const clock = opciones.clock || (() => Date.now());
  const item = {
    id: opciones.id || randomUUID(),
    module: 'dispatches',
    scopeId: opciones.scopeId || opciones.sedeId || 'sede-central',
    sedeId: opciones.sedeId || opciones.scopeId || 'sede-central',
    tipo: comandoValido.tipo,
    fechaPrevista: comandoValido.fechaPrevista || undefined,
    motivo: comandoValido.motivo || undefined,
    reservaIds: comandoValido.reservaIds,
    pedidoId: opciones.pedidoId || 'PED-DEMO-001',
    hospitalId: opciones.hospitalId || 'HOSP-DEMO',
    responsableId: opciones.responsableId || 'nursing-demo',
    fechaRegistro: new Date(clock()).toISOString(),
  };
  return item;
}

export function validarUnidadesDespacho(db, user, pedido, reservaIds) {
  const seleccionadas = [];
  for (const id of reservaIds) {
    let unidad = db.records.find((r) => r.module === 'inventory' && r.id === id);
    let reserva = null;

    if (!unidad) {
      reserva = db.records.find((r) => (r.module === 'reservations' || r.module === 'inventory') && r.id === id);
      if (reserva?.unidadId) {
        unidad = db.records.find((r) => r.module === 'inventory' && r.id === reserva.unidadId);
      }
    } else {
      reserva = db.records.find((r) => r.module === 'reservations' && (r.id === id || r.unidadId === id));
    }

    if (!unidad) throw new DispatchError(400, `La reserva o unidad ${id} no existe.`);
    if (unidad.scopeId !== user.siteId) throw new DispatchError(409, `La unidad ${unidad.id} pertenece a otra sede.`);
    if (unidad.pedidoId !== pedido.id && (!reserva || reserva.pedidoId !== pedido.id)) {
      throw new DispatchError(400, `La unidad ${unidad.id} no está reservada para este pedido.`);
    }
    if (unidad.estado !== 'reservada') throw new DispatchError(400, `La unidad ${unidad.id} no está en estado reservada.`);
    if (unidad.grupoAbo !== pedido.grupoAbo || unidad.factorRh !== pedido.factorRh) {
      throw new DispatchError(400, `El grupo sanguíneo de la unidad ${unidad.id} no coincide con el pedido.`);
    }
    seleccionadas.push({ unidad, reserva });
  }
  return seleccionadas;
}

export function invalidarReservasVencidas(db, user, pedido, vencidas, hoy, ahora) {
  for (const { unidad, reserva } of vencidas) {
    unidad.estado = 'vencida';
    unidad.usuarioModificacionId = user.id;
    unidad.fechaModificacion = ahora;
    if (reserva) {
      reserva.estado = 'vencida';
      reserva.usuarioModificacionId = user.id;
      reserva.fechaModificacion = ahora;
    }
  }
  const reservasRestantes = db.records.filter(
    (r) =>
      (r.module === 'reservations' || (r.module === 'inventory' && r.estado === 'reservada')) &&
      r.pedidoId === pedido.id,
  );
  const saldos = calcularSaldosPedidoConReservas({
    cantidadSolicitada: pedido.cantidadSolicitada,
    cantidadDespachada: pedido.cantidadDespachada ?? 0,
    reservas: reservasRestantes,
    hoy,
  });
  Object.assign(pedido, saldos, {
    usuarioModificacionId: user.id,
    fechaModificacion: ahora,
  });
  return vencidas.map(({ unidad }) => unidad.id);
}
