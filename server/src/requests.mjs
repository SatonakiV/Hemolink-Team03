import { randomUUID } from 'node:crypto';
import { GRUPOS_ABO, FACTORES_RH } from './blood-groups.mjs';
import { calcularSaldosPedido, calcularSaldosPedidoActuales } from './order-balances.mjs';

export class SolicitudError extends Error {
  constructor(status, message, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

export function validarSolicitud(datos) {
  const errors = {};
  if (!datos || typeof datos !== 'object' || Array.isArray(datos)) {
    throw new SolicitudError(400, 'Revisa los datos de la solicitud.', {
      solicitud: 'Ingresa un cuerpo válido.',
    });
  }

  const grupoAbo = typeof datos.grupoAbo === 'string' ? datos.grupoAbo.trim().toUpperCase() : '';
  if (!GRUPOS_ABO.includes(grupoAbo)) {
    errors.grupoAbo = 'Ingresa un grupo ABO válido (A, B, AB u O).';
  }

  const factorRh = typeof datos.factorRh === 'string' ? datos.factorRh.trim().toLowerCase() : '';
  if (!FACTORES_RH.includes(factorRh)) {
    errors.factorRh = 'Ingresa un factor Rh válido (positivo o negativo).';
  }

  const rawCantidad = datos.cantidadSolicitada ?? datos.cantidad;
  if (!Number.isSafeInteger(rawCantidad) || rawCantidad <= 0) {
    errors.cantidad = 'La cantidad solicitada debe ser un entero positivo.';
  }

  const prioridad = typeof datos.prioridad === 'string' ? datos.prioridad.trim().toLowerCase() : '';
  if (prioridad !== 'urgente' && prioridad !== 'normal') {
    errors.prioridad = 'La prioridad debe ser urgente o normal.';
  }

  if (Object.keys(errors).length > 0) {
    throw new SolicitudError(400, 'Revisa los datos de la solicitud.', errors);
  }

  return {
    grupoAbo,
    factorRh,
    cantidadSolicitada: rawCantidad,
    prioridad,
  };
}

export function compararSolicitudes(a, b) {
  const pesoPrioridad = p => (p?.toLowerCase() === 'urgente' ? 0 : 1);
  const prioridadDiff = pesoPrioridad(a.prioridad) - pesoPrioridad(b.prioridad);
  if (prioridadDiff !== 0) return prioridadDiff;

  const fechaA = a.fechaRegistro || '';
  const fechaB = b.fechaRegistro || '';
  const fechaDiff = fechaA.localeCompare(fechaB);
  if (fechaDiff !== 0) return fechaDiff;

  return (a.id || '').localeCompare(b.id || '', 'en');
}

export function ordenarBandeja(solicitudes) {
  return [...solicitudes].sort(compararSolicitudes);
}

export function crearSolicitud(db, user, datosValidados, { id, ahora, fecha } = {}) {
  const solicitudes = db.records.filter(r => r.module === 'requests' && typeof r.numero === 'number');
  const maxNumero = solicitudes.reduce((max, r) => (r.numero > max ? r.numero : max), 0);
  const numero = maxNumero + 1;

  const saldos = calcularSaldosPedido({
    cantidadSolicitada: datosValidados.cantidadSolicitada,
    cantidadDespachada: 0,
    cantidadReservada: 0,
  });

  const solicitudId = id || randomUUID();
  const item = {
    id: solicitudId,
    numero,
    module: 'requests',
    scopeId: user.hospitalId,
    hospitalId: user.hospitalId,
    responsableId: user.id,
    grupoAbo: datosValidados.grupoAbo,
    factorRh: datosValidados.factorRh,
    prioridad: datosValidados.prioridad,
    fecha: fecha || ahora?.slice(0, 10),
    fechaRegistro: ahora || new Date().toISOString(),
    ...saldos,
    label: `Solicitud #${numero} · ${datosValidados.grupoAbo}${datosValidados.factorRh === 'positivo' ? '+' : '-'} (${datosValidados.prioridad})`,
  };

  db.records.push(item);
  return item;
}

export function obtenerFichaSolicitud(db, user, id, { hoy } = {}) {
  const pedido = db.records.find(r => r.module === 'requests' && r.id === id);
  if (!pedido) {
    throw new SolicitudError(404, 'Solicitud no encontrada.');
  }

  if (user.role === 'hospital' && pedido.scopeId !== user.hospitalId && pedido.hospitalId !== user.hospitalId) {
    throw new SolicitudError(404, 'Solicitud no encontrada.');
  }

  if (user.role !== 'hospital' && user.role !== 'inventory') {
    throw new SolicitudError(403, 'Tu perfil no puede consultar solicitudes.');
  }

  const reservas = db.records.filter(r =>
    (r.module === 'reservations' || (r.module === 'inventory' && r.estado === 'reservada')) &&
    r.pedidoId === id,
  );

  const avisos = db.records.filter(r =>
    (r.module === 'notices' || r.module === 'avisos') &&
    r.pedidoId === id,
  );

  const despachos = db.records.filter(r =>
    r.module === 'dispatches' &&
    r.pedidoId === id,
  );

  let saldos = {
    cantidadSolicitada: pedido.cantidadSolicitada,
    cantidadDespachada: pedido.cantidadDespachada ?? 0,
    cantidadReservada: pedido.cantidadReservada ?? 0,
    pendienteAsignar: pedido.pendienteAsignar ?? pedido.cantidadSolicitada,
    pendienteEntregar: pedido.pendienteEntregar ?? pedido.cantidadSolicitada,
    estado: pedido.estado ?? 'pendiente',
  };

  if (hoy && typeof pedido.cantidadSolicitada === 'number') {
    try {
      saldos = calcularSaldosPedidoActuales(db, pedido, hoy);
    } catch {
      // Usar saldos actuales si no se pueden recalcular
    }
  }

  return {
    ...pedido,
    ...saldos,
    reservas,
    avisos,
    despachos,
  };
}
