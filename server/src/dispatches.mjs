import { randomUUID } from 'node:crypto';
import { fechaValida } from './dates.mjs';

export class DispatchError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function validarComandoDespacho(datos) {
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

  return {
    tipo,
    fechaPrevista,
    motivo,
    reservaIds: Array.from(conjuntoUnico),
  };
}

export function crearComprobanteDespacho(comandoValido, opciones = {}) {
  const clock = opciones.clock || (() => Date.now());
  const item = {
    id: opciones.id || randomUUID(),
    module: 'dispatches',
    tipo: comandoValido.tipo,
    fechaPrevista: comandoValido.fechaPrevista || undefined,
    motivo: comandoValido.motivo || undefined,
    reservaIds: comandoValido.reservaIds,
    pedidoId: opciones.pedidoId || 'PED-DEMO-001',
    hospitalId: opciones.hospitalId || 'HOSP-DEMO',
    sedeId: opciones.sedeId || 'sede-central',
    responsableId: opciones.responsableId || 'nursing-demo',
    fechaRegistro: new Date(clock()).toISOString(),
  };
  return item;
}
