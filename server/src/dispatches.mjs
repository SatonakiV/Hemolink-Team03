import { randomUUID } from 'node:crypto';
import { activeSession } from './auth.mjs';
import { fechaLocal, fechaValida } from './dates.mjs';
import { calcularSaldosPedidoActuales, fechaLimiteReserva } from './order-balances.mjs';

const CLAVE = /^[A-Za-z0-9_-]{1,64}$/;

export class DispatchError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function validarFechaPrevista(fechaPrevista, hoy) {
  if (fechaPrevista && hoy && fechaPrevista < hoy) {
    throw new DispatchError(400, 'La fecha prevista no puede ser anterior a la fecha actual.');
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
    validarFechaPrevista(rawFecha, hoy);
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
  const unidadesSeleccionadas = new Set();
  const unidades = new Map(db.records.filter(r => r.module === 'inventory').map(r => [r.id, r]));
  const reservas = db.records.filter(r => r.module === 'reservations');

  for (const id of reservaIds) {
    const unidadDirecta = unidades.get(id);
    const reservaExplicita = unidadDirecta ? undefined : reservas.find(r => r.id === id);
    const unidad = unidadDirecta ?? unidades.get(reservaExplicita?.unidadId);
    if (!unidad) throw new DispatchError(400, `La reserva o unidad ${id} no existe.`);
    if (unidad.scopeId !== user.siteId) throw new DispatchError(409, `La unidad ${unidad.id} pertenece a otra sede.`);

    const activas = reservas.filter(r => r.unidadId === unidad.id && r.estado === 'reservada');
    const reserva = reservaExplicita ?? activas[0];
    if (reserva && reserva.scopeId !== user.siteId) {
      throw new DispatchError(409, `La reserva ${reserva.id} pertenece a otra sede.`);
    }
    if (reserva && reserva.estado !== 'reservada') {
      throw new DispatchError(400, `La reserva ${reserva.id} ya no está activa.`);
    }
    if (activas.length > 1) {
      throw new DispatchError(409, `La unidad ${unidad.id} tiene más de una reserva activa.`);
    }
    const pedidoReserva = reserva ? reserva.pedidoId : unidad.pedidoId;
    if (pedidoReserva !== pedido.id || (unidad.pedidoId != null && unidad.pedidoId !== pedido.id)) {
      throw new DispatchError(400, `La unidad ${unidad.id} no está reservada para este pedido.`);
    }
    if (unidad.estado !== 'reservada') throw new DispatchError(400, `La unidad ${unidad.id} no está en estado reservada.`);
    if (unidad.grupoAbo !== pedido.grupoAbo || unidad.factorRh !== pedido.factorRh) {
      throw new DispatchError(400, `El grupo sanguíneo de la unidad ${unidad.id} no coincide con el pedido.`);
    }
    if (unidadesSeleccionadas.has(unidad.id)) {
      throw new DispatchError(400, `La unidad ${unidad.id} está repetida en la selección.`);
    }
    const fechaLimite = fechaLimiteReserva(unidad, reserva);
    if (!fechaValida(fechaLimite)) {
      throw new DispatchError(400, `La unidad ${unidad.id} o su reserva tiene una fecha de vencimiento inválida.`);
    }
    unidadesSeleccionadas.add(unidad.id);
    seleccionadas.push({ unidad, reserva, fechaLimite });
  }
  return seleccionadas;
}

export function invalidarReservasVencidas(db, user, pedido, vencidas, hoy, ahora) {
  for (const { unidad, reserva } of vencidas) {
    unidad.estado = hoy >= unidad.fechaVencimiento ? 'vencida' : 'disponible';
    unidad.usuarioModificacionId = user.id;
    unidad.fechaModificacion = ahora;
    if (reserva) {
      reserva.estado = 'vencida';
      reserva.usuarioModificacionId = user.id;
      reserva.fechaModificacion = ahora;
    }
  }
  const saldos = calcularSaldosPedidoActuales(db, pedido, hoy);
  Object.assign(pedido, saldos, {
    usuarioModificacionId: user.id,
    fechaModificacion: ahora,
  });
  return vencidas.map(({ unidad }) => unidad.id);
}

export function registrarSalidaDespacho(db, user, pedido, comando, seleccionadas, hoy, ahora) {
  const comprobanteId = randomUUID();
  for (const { unidad, reserva } of seleccionadas) {
    Object.assign(unidad, {
      estado: 'despachada', despachoId: comprobanteId, fechaDespacho: ahora,
      usuarioDespachoId: user.id, usuarioModificacionId: user.id, fechaModificacion: ahora,
    });
    if (reserva) {
      Object.assign(reserva, {
        estado: 'cerrada', despachoId: comprobanteId,
        usuarioModificacionId: user.id, fechaModificacion: ahora,
      });
    }
  }

  pedido.cantidadDespachada = (pedido.cantidadDespachada ?? 0) + seleccionadas.length;
  const saldos = calcularSaldosPedidoActuales(db, pedido, hoy);
  Object.assign(pedido, saldos, {
    usuarioModificacionId: user.id,
    fechaModificacion: ahora,
  });

  const comprobante = {
    id: comprobanteId,
    module: 'dispatches',
    scopeId: user.siteId,
    sedeId: user.siteId,
    pedidoId: pedido.id,
    hospitalId: pedido.hospitalId,
    tipo: comando.tipo,
    ...(comando.fechaPrevista ? { fechaPrevista: comando.fechaPrevista } : {}),
    ...(comando.motivo ? { motivo: comando.motivo } : {}),
    reservaIds: comando.reservaIds,
    unidades: seleccionadas.map(({ unidad }) => unidad.id),
    cantidad: seleccionadas.length,
    ...(comando.claveConfirmacion ? { claveConfirmacion: comando.claveConfirmacion } : {}),
    responsableId: user.id,
    usuarioRegistroId: user.id,
    fechaRegistro: ahora,
  };
  db.records.push(comprobante);

  return { item: comprobante, comprobante, saldos, pedido, existente: false };
}

export async function confirmarDespacho({
  store,
  user: usuarioInterno,
  sessionTokenHash,
  clock = Date.now,
  pedidoId,
  datos,
  hoy,
  ahora,
}) {
  if (!store || typeof store.update !== 'function') {
    throw new TypeError('Se requiere un almacén con el método update.');
  }

  let resultadoFinal;
  let invalidacionVencidas;

  await store.update((db) => {
    const instante = clock();
    const fechaHoy = hoy || fechaLocal(() => instante);
    const fechaAhora = ahora || new Date(instante).toISOString();
    let user = usuarioInterno;
    if (sessionTokenHash !== undefined) {
      const sesion = activeSession(db, sessionTokenHash, instante);
      if (!sesion) throw new DispatchError(401, 'La sesión no es válida. Inicia sesión nuevamente.');
      user = sesion.user;
    }
    if (!user || typeof user !== 'object' || !user.id || user.role !== 'inventory' || !user.siteId) {
      throw new DispatchError(403, 'Solo personal de inventario autorizado puede despachar unidades.');
    }

    const comando = validarComandoDespacho(datos);
    if (comando.sedeId !== undefined && comando.sedeId !== user.siteId) {
      throw new DispatchError(409, 'La sede indicada no coincide con la de tu cuenta.');
    }

    const idPedido = pedidoId || datos?.pedidoId;
    if (!idPedido || typeof idPedido !== 'string') {
      throw new DispatchError(400, 'Identificador de pedido inválido.');
    }

    const pedido = db.records.find((r) => r.module === 'requests' && r.id === idPedido);
    if (!pedido) {
      throw new DispatchError(404, 'El pedido no existe.');
    }

    const previa = confirmacionPreviaDespacho(db, user, comando, pedido.id);
    if (previa) {
      resultadoFinal = { item: previa, comprobante: previa, existente: true };
      return;
    }

    validarFechaPrevista(comando.fechaPrevista, fechaHoy);
    const seleccionadas = validarUnidadesDespacho(db, user, pedido, comando.reservaIds);
    const vencidas = seleccionadas.filter(({ fechaLimite }) => fechaHoy >= fechaLimite);

    if (vencidas.length > 0) {
      invalidacionVencidas = invalidarReservasVencidas(db, user, pedido, vencidas, fechaHoy, fechaAhora);
      return;
    }

    resultadoFinal = registrarSalidaDespacho(db, user, pedido, comando, seleccionadas, fechaHoy, fechaAhora);
  });

  if (invalidacionVencidas) {
    throw new DispatchError(
      409,
      `Una o más reservas seleccionadas perdieron vigencia (${invalidacionVencidas.join(', ')}) y fueron invalidadas.`,
    );
  }

  return resultadoFinal;
}
