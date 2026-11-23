
import { randomUUID } from 'node:crypto';

import { fechaValida } from './dates.mjs';
import { unidadElegible } from './inventory.mjs';
import { calcularSaldosPedidoConReservas } from './order-balances.mjs';
import { SolicitudError } from './requests.mjs';
import { AtencionParcialError } from './partial-fulfillment.mjs';
import { confirmarAtencionParcial } from './partial-fulfillment-transaction.mjs';

const ID_VALIDO = /^[A-Za-z0-9_-]{1,64}$/;

/**
 * HU09 - T09.2
 *
 * Adaptadores para el modelo real de HemoLink.
 *
 * Los datos de las unidades se modifican dentro
 * de la misma transaccion que registra el aviso.
 *
 * No se realizan lecturas independientes a store.read()
 * dentro de store.update().
 */

function obtenerPedido(db, pedidoId) {
  const pedido = db.records.find(
    item =>
      item.module === 'requests' &&
      item.id === pedidoId,
  );

  if (!pedido) {
    throw new SolicitudError(
      404,
      'Solicitud no encontrada.',
    );
  }

  return pedido;
}

/**
 * Calcula saldos usando las unidades reservadas
 * que pertenecen al pedido.
 *
 * Las unidades vencidas no cuentan como reservas
 * validas, conforme a la regla de HU09.
 */
function obtenerSaldosActuales(db, pedido, hoy) {
  const reservas = db.records.filter(
    item =>
      item.module === 'inventory' &&
      item.pedidoId === pedido.id &&
      item.estado === 'reservada',
  );

  return calcularSaldosPedidoConReservas({
    cantidadSolicitada: pedido.cantidadSolicitada,
    cantidadDespachada: pedido.cantidadDespachada ?? 0,
    reservas,
    hoy,
  });
}

/**
 * Devuelve unidades elegibles del mismo ABO/Rh,
 * ordenadas por vencimiento y luego por ID (FEFO).
 *
 * Se conserva la sede de cada unidad.
 */
function obtenerUnidadesElegibles(db, pedido, hoy) {
  return db.records
    .filter(
      unidad =>
        unidadElegible(unidad, hoy) &&
        unidad.grupoAbo === pedido.grupoAbo &&
        unidad.factorRh === pedido.factorRh,
    )
    .sort(
      (a, b) =>
        a.fechaVencimiento.localeCompare(
          b.fechaVencimiento,
        ) ||
        a.id.localeCompare(b.id, 'en'),
    );
}

/**
 * Rechaza una propuesta diferente de la propuesta
 * FEFO vigente. Esto detecta cambios de stock
 * entre la consulta y la confirmacion.
 */
function validarPropuestaVigente(
  seleccion,
  elegibles,
  pendienteAsignar,
) {
  const cantidad =
    Math.min(pendienteAsignar, elegibles.length);

  const propuestaActual = elegibles
    .slice(0, cantidad)
    .map(unidad => unidad.id);

  const coincide =
    seleccion.length === propuestaActual.length &&
    seleccion.every(
      (id, index) => id === propuestaActual[index],
    );

  if (!coincide) {
    throw new AtencionParcialError(
      'El stock o la propuesta cambiaron. '
      + 'Actualiza la propuesta antes de confirmar.',
      'STOCK_CONFLICT',
    );
  }
}

/**
 * Confirma una atencion parcial con el modelo
 * actual de solicitudes e inventario.
 *
 * Solo inventario puede ejecutar esta operacion.
 *
 * La API obtiene el usuario desde la sesion;
 * no debe aceptar responsables desde el JSON.
 */
export async function atenderPedidoParcial({
  store,
  user,
  pedidoId,
  decision,
  unidadesPropuestas = [],
  hoy,
  ahora,
}) {
  if (user?.role !== 'inventory') {
    throw new SolicitudError(
      403,
      'Solo inventario puede confirmar atenciones.',
    );
  }

  if (
    !ID_VALIDO.test(pedidoId ?? '') ||
    !fechaValida(hoy) ||
    typeof ahora !== 'string' ||
    !Number.isFinite(Date.parse(ahora))
  ) {
    throw new AtencionParcialError(
      'Los datos de confirmacion no son validos.',
    );
  }

  if (
    !Array.isArray(unidadesPropuestas) ||
    unidadesPropuestas.some(
      id => typeof id !== 'string' ||
        !ID_VALIDO.test(id),
    ) ||
    new Set(unidadesPropuestas).size !==
      unidadesPropuestas.length
  ) {
    throw new AtencionParcialError(
      'La seleccion contiene identificadores invalidos.',
    );
  }

  let avisoGuardado;
  let saldosConfirmados;

  const plan = await confirmarAtencionParcial({
    store,
    pedidoId,
    decision,
    unidadesPropuestas,

    obtenerEstado(db, id) {
      const pedido = obtenerPedido(db, id);

      const saldos = obtenerSaldosActuales(
        db,
        pedido,
        hoy,
      );

      if (saldos.pendienteAsignar === 0) {
        throw new AtencionParcialError(
          'El pedido no tiene unidades pendientes '
          + 'por asignar.',
          'STOCK_CONFLICT',
        );
      }

      const elegibles = obtenerUnidadesElegibles(
        db,
        pedido,
        hoy,
      );

      if (decision === 'aceptar') {
        validarPropuestaVigente(
          unidadesPropuestas,
          elegibles,
          saldos.pendienteAsignar,
        );
      }

      return {
        saldos: {
          Q: saldos.cantidadSolicitada,
          D: saldos.cantidadDespachada,
          R: saldos.cantidadReservada,
        },
        unidadesElegibles: elegibles.map(
          unidad => unidad.id,
        ),
      };
    },

    guardarReservas(db, planActual) {
      const pedido = obtenerPedido(
        db,
        planActual.pedidoId,
      );

      for (const unidadId of planActual.reservaIds) {
        const unidad = db.records.find(
          item =>
            item.module === 'inventory' &&
            item.id === unidadId,
        );

        if (
          !unidad ||
          !unidadElegible(unidad, hoy) ||
          unidad.grupoAbo !== pedido.grupoAbo ||
          unidad.factorRh !== pedido.factorRh
        ) {
          throw new AtencionParcialError(
            'Una unidad dejo de estar disponible.',
            'STOCK_CONFLICT',
          );
        }

        // Se conserva el ID, codigo, donacion y sede.
        unidad.estado = 'reservada';
        unidad.pedidoId = pedido.id;
        unidad.hospitalId = pedido.hospitalId;
        unidad.fechaReserva = hoy;
        unidad.usuarioReservaId = user.id;
        unidad.usuarioModificacionId = user.id;
        unidad.fechaModificacion = ahora;
      }
    },

    guardarAviso(db, aviso) {
      const pedido = obtenerPedido(
        db,
        aviso.pedidoId,
      );

      // Recalcular despues de registrar las reservas.
      const saldos = obtenerSaldosActuales(
        db,
        pedido,
        hoy,
      );

      if (
        saldos.pendienteAsignar !==
        aviso.cantidadFaltante
      ) {
        throw new Error(
          'El aviso no coincide con el saldo calculado.',
        );
      }

      const nuevoAviso = {
        id: randomUUID(),
        module: 'notices',
        scopeId: pedido.hospitalId,
        hospitalId: pedido.hospitalId,
        pedidoId: pedido.id,
        decision: aviso.decision,
        cantidadFaltante: aviso.cantidadFaltante,
        faltante: aviso.cantidadFaltante,
        fecha: hoy,
        fechaRegistro: ahora,
        usuarioRegistroId: user.id,
      };

      db.records.push(nuevoAviso);

      // El pedido conserva sus datos originales.
      Object.assign(pedido, saldos, {
        usuarioModificacionId: user.id,
        fechaModificacion: ahora,
      });

      avisoGuardado = nuevoAviso;
      saldosConfirmados = saldos;
    },
  });

  // Solo se llega aqui cuando store.update() termina
  // correctamente y confirma todos los cambios.
  return {
    pedidoId,
    decision,
    reservaIds: plan.reservaIds,
    aviso: avisoGuardado,
    saldos: saldosConfirmados,
  };
}
