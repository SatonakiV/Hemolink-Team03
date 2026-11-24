import { calcularSaldosPedidoActuales } from './order-balances.mjs';

/**
 * HU07 / T07.1: búsqueda por código y descarte de unidades.
 *
 * Las funciones trabajan sobre el `db` que entrega store.update(): si alguna
 * lanza, la transacción completa se revierte (unidad, reserva y pedido).
 *
 * Reservas: el contrato del sprint define un registro propio
 * (module 'reservations', con unidadId, pedidoId, sede y estado). Mientras se
 * integra HU08, también se reconoce la unidad marcada como 'reservada' con
 * pedidoId. Ambas formas se invalidan igual.
 */

export class DescarteError extends Error {
  constructor(status, message, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

const CODIGO = /^[A-Za-z0-9_-]{1,32}$/;
const MOTIVO_MAX = 300;
const DESCARTABLES = new Set(['disponible', 'reservada']);

const normalizarCodigo = codigo => codigo.trim().toUpperCase();

export function validarCodigo(codigo) {
  const limpio = typeof codigo === 'string' ? codigo.trim() : '';
  if (!CODIGO.test(limpio)) {
    throw new DescarteError(400, 'Ingresa un código de unidad válido.', {
      codigo: 'Usa letras, números, guion o guion bajo (máximo 32).',
    });
  }
  return limpio;
}

export function validarMotivo(datos) {
  const motivo = typeof datos?.motivo === 'string' ? datos.motivo.trim() : '';
  if (!motivo) {
    throw new DescarteError(400, 'Indica el motivo del descarte.', {
      motivo: 'El motivo es obligatorio.',
    });
  }
  if (motivo.length > MOTIVO_MAX) {
    throw new DescarteError(400, 'El motivo es demasiado largo.', {
      motivo: `Usa como máximo ${MOTIVO_MAX} caracteres.`,
    });
  }
  return motivo;
}

const esRegistroReservaActiva = (registro, unidadId) =>
  registro.module === 'reservations' &&
  registro.unidadId === unidadId &&
  registro.estado === 'reservada';

const esUnidadMarcada = unidad =>
  unidad.estado === 'reservada' && typeof unidad.pedidoId === 'string';

/** Reservas activas de la unidad, en cualquiera de las dos representaciones. */
function reservasActivas(db, unidad) {
  const activas = db.records
    .filter(registro => esRegistroReservaActiva(registro, unidad.id))
    .map(registro => ({ reservaId: registro.id, pedidoId: registro.pedidoId }));
  if (esUnidadMarcada(unidad) && !activas.some(r => r.pedidoId === unidad.pedidoId)) {
    activas.push({ reservaId: null, pedidoId: unidad.pedidoId });
  }
  return activas;
}

/** Unidad sin datos del donante (D3). */
export function proyectarUnidad(db, unidad) {
  const reservas = reservasActivas(db, unidad);
  return {
    id: unidad.id,
    codigo: unidad.codigo,
    sedeId: unidad.scopeId,
    donacionId: unidad.donacionId,
    grupoAbo: unidad.grupoAbo,
    factorRh: unidad.factorRh,
    estado: unidad.estado,
    fechaVencimiento: unidad.fechaVencimiento,
    reserva: reservas[0] ?? null,
    descarte: unidad.descarte ?? null,
    historial: Array.isArray(unidad.historial) ? unidad.historial : [],
  };
}

export function buscarUnidadPorCodigo(db, user, codigo) {
  const buscado = normalizarCodigo(validarCodigo(codigo));
  const unidad = db.records.find(registro =>
    registro.module === 'inventory' &&
    registro.scopeId === user.siteId &&
    typeof registro.codigo === 'string' &&
    normalizarCodigo(registro.codigo) === buscado);
  // Otra sede responde igual que inexistente: no se revela qué hay en ella.
  if (!unidad) throw new DescarteError(404, 'No hay una unidad con ese código en tu sede.');
  return proyectarUnidad(db, unidad);
}

/**
 * Descarta una unidad de la sede del usuario. Repetir el descarte devuelve el
 * primer registro sin modificar nada (CA2).
 */
export function descartarUnidad(db, user, unidadId, motivo, { hoy, ahora }) {
  const unidad = db.records.find(registro =>
    registro.module === 'inventory' &&
    registro.id === unidadId &&
    registro.scopeId === user.siteId);
  if (!unidad) throw new DescarteError(404, 'No hay una unidad con ese identificador en tu sede.');

  if (unidad.estado === 'descartada') {
    return { item: proyectarUnidad(db, unidad), repetido: true, reservasInvalidadas: [], pedidos: [] };
  }
  if (unidad.estado === 'despachada') {
    throw new DescarteError(409, 'Una unidad despachada no se puede descartar.');
  }
  if (!DESCARTABLES.has(unidad.estado)) {
    throw new DescarteError(409, 'El estado actual de la unidad no permite descartarla.');
  }

  const estadoAnterior = unidad.estado;
  const reservas = reservasActivas(db, unidad);

  // 1. Invalidar las reservas activas; el registro se conserva como historial.
  for (const registro of db.records) {
    if (esRegistroReservaActiva(registro, unidad.id)) {
      Object.assign(registro, {
        estado: 'invalidada',
        motivoInvalidacion: 'Unidad descartada',
        fechaInvalidacion: ahora,
        usuarioModificacionId: user.id,
        fechaModificacion: ahora,
      });
    }
  }

  // 2. Descartar la unidad. Conserva ID, código, donación, sede y pedidoId.
  const descarte = {
    motivo,
    fecha: hoy,
    fechaRegistro: ahora,
    usuarioId: user.id,
    estadoAnterior,
    reservasInvalidadas: reservas,
  };
  const historial = Array.isArray(unidad.historial) ? unidad.historial : [];
  Object.assign(unidad, {
    estado: 'descartada',
    descarte,
    historial: [...historial, {
      evento: 'descarte',
      fecha: ahora,
      usuarioId: user.id,
      estadoAnterior,
      estadoNuevo: 'descartada',
      motivo,
    }],
    usuarioModificacionId: user.id,
    fechaModificacion: ahora,
  });

  // 3. Actualizar el saldo de cada pedido afectado. D no cambia.
  const pedidos = [];
  for (const pedidoId of new Set(reservas.map(r => r.pedidoId))) {
    const pedido = db.records.find(r => r.module === 'requests' && r.id === pedidoId);
    if (!pedido) continue;
    const saldos = calcularSaldosPedidoActuales(db, pedido, hoy);
    Object.assign(pedido, saldos, { usuarioModificacionId: user.id, fechaModificacion: ahora });
    pedidos.push({ id: pedido.id, ...saldos });
  }

  return { item: proyectarUnidad(db, unidad), repetido: false, reservasInvalidadas: reservas, pedidos };
}
