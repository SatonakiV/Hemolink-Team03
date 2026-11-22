
import {
  planificarAtencionParcial,
} from './partial-fulfillment.mjs';

/**
 * HU09 - T09.2
 *
 * Ejecuta la planificación, las reservas y el aviso
 * dentro de una única actualización del almacén.
 *
 * Compatible con SqliteStore.update(), cuyo callback
 * debe ejecutarse de forma síncrona.
 */

function validarDependencias({
  store,
  obtenerEstado,
  guardarReservas,
  guardarAviso,
}) {
  if (!store || typeof store.update !== 'function') {
    throw new TypeError(
      'Se requiere un almacén con el método update.',
    );
  }

  for (const [nombre, funcion] of Object.entries({
    obtenerEstado,
    guardarReservas,
    guardarAviso,
  })) {
    if (typeof funcion !== 'function') {
      throw new TypeError(
        `La dependencia ${nombre} debe ser una función.`,
      );
    }
  }
}

/**
 * Impide utilizar operaciones asíncronas dentro
 * de una transacción SQLite síncrona.
 */
function exigirResultadoSincrono(resultado, operacion) {
  if (
    resultado !== null &&
    typeof resultado === 'object' &&
    typeof resultado.then === 'function'
  ) {
    throw new TypeError(
      `${operacion} debe ejecutarse sincrónicamente.`,
    );
  }
}

/**
 * Confirma una atención parcial.
 *
 * Todos los adaptadores deben trabajar sobre el mismo
 * objeto db entregado por store.update().
 *
 * obtenerEstado(db, pedidoId):
 *   devuelve { saldos, unidadesElegibles }.
 *
 * guardarReservas(db, plan):
 *   registra las unidades seleccionadas.
 *
 * guardarAviso(db, aviso):
 *   registra el aviso vinculado al pedido.
 *
 * Si cualquier operación falla, la actualización
 * completa debe revertirse.
 */
export async function confirmarAtencionParcial({
  store,
  pedidoId,
  decision,
  unidadesPropuestas = [],
  obtenerEstado,
  guardarReservas,
  guardarAviso,
}) {
  validarDependencias({
    store,
    obtenerEstado,
    guardarReservas,
    guardarAviso,
  });

  // SqliteStore.update() no devuelve el resultado
  // del callback. Lo capturamos explícitamente.
  let planConfirmado;

  await store.update((db) => {
    // 1. Consultar el estado dentro de la transacción.
    const estado = obtenerEstado(db, pedidoId);

    exigirResultadoSincrono(
      estado,
      'obtenerEstado',
    );

    if (!estado || typeof estado !== 'object') {
      throw new Error(
        'No se pudo consultar el estado del pedido.',
      );
    }

    // 2. Validar los saldos y el stock actual.
    const plan = planificarAtencionParcial({
      pedidoId,
      saldos: estado.saldos,
      decision,
      unidadesPropuestas,
      unidadesElegibles: estado.unidadesElegibles,
    });

    // 3. Reservar unidades únicamente al aceptar.
    if (plan.reservaIds.length > 0) {
      const resultadoReservas = guardarReservas(
        db,
        plan,
      );

      exigirResultadoSincrono(
        resultadoReservas,
        'guardarReservas',
      );
    }

    // 4. Guardar el aviso en la misma transacción.
    const resultadoAviso = guardarAviso(
      db,
      plan.aviso,
    );

    exigirResultadoSincrono(
      resultadoAviso,
      'guardarAviso',
    );

    // 5. Capturar el resultado.
    // Solo se devolverá cuando update termine.
    planConfirmado = plan;
  });

  return planConfirmado;
}
