
/**
 * HU09 - T09.2
 * Planificación de atención parcial de solicitudes.
 *
 * Calcula las unidades que se deben reservar y la cantidad
 * faltante que se informará al hospital.
 *
 * Esta función no modifica la base de datos.
 * La confirmación definitiva debe realizarse dentro
 * de una transacción SQLite.
 */

export class AtencionParcialError extends Error {
  constructor(mensaje, code = 'INVALID_REQUEST') {
    super(mensaje);

    this.name = 'AtencionParcialError';
    this.code = code;
  }
}

/**
 * Comprueba que un valor sea un entero no negativo.
 */
function validarCantidad(valor, nombre) {
  if (!Number.isSafeInteger(valor) || valor < 0) {
    throw new AtencionParcialError(
      `${nombre} debe ser un entero no negativo.`,
    );
  }
}

/**
 * Valida los saldos de un pedido.
 *
 * Q: unidades solicitadas.
 * D: unidades despachadas.
 * R: reservas válidas.
 *
 * Restricción:
 * 0 <= D + R <= Q
 */
function validarSaldos(saldos) {
  if (saldos === null || typeof saldos !== 'object') {
    throw new AtencionParcialError(
      'Los saldos del pedido son obligatorios.',
    );
  }

  const { Q, D, R } = saldos;

  validarCantidad(Q, 'Cantidad solicitada');
  validarCantidad(D, 'Cantidad despachada');
  validarCantidad(R, 'Cantidad reservada');

  if (Q === 0) {
    throw new AtencionParcialError(
      'El pedido debe solicitar al menos una unidad.',
    );
  }

  if (D + R > Q) {
    throw new AtencionParcialError(
      'Las unidades despachadas y reservadas superan '
      + 'la cantidad solicitada.',
    );
  }

  return {
    Q,
    D,
    R,
    pendientePorAsignar: Q - D - R,
    pendientePorEntregar: Q - D,
  };
}

/**
 * Valida una lista de identificadores de unidades.
 */
function validarUnidades(unidades, nombre) {
  if (!Array.isArray(unidades)) {
    throw new AtencionParcialError(
      `${nombre} debe ser una lista.`,
    );
  }

  const identificadores = new Set();

  for (const id of unidades) {
    if (typeof id !== 'string' || id.trim() === '') {
      throw new AtencionParcialError(
        `${nombre} contiene un identificador inválido.`,
      );
    }

    if (identificadores.has(id)) {
      throw new AtencionParcialError(
        `${nombre} contiene unidades repetidas.`,
      );
    }

    identificadores.add(id);
  }

  return identificadores;
}

/**
 * Planifica una atención parcial.
 *
 * decision:
 * - aceptar: reservar las unidades seleccionadas.
 * - rechazar: informar el faltante sin crear reservas.
 *
 * unidadesPropuestas:
 * IDs seleccionados para una posible reserva.
 *
 * unidadesElegibles:
 * IDs disponibles al momento de revalidar.
 */
export function planificarAtencionParcial({
  pedidoId,
  saldos,
  decision,
  unidadesPropuestas = [],
  unidadesElegibles = [],
}) {
  // 1. Validar la identificación del pedido.
  if (typeof pedidoId !== 'string' ||
      pedidoId.trim() === '') {
    throw new AtencionParcialError(
      'El identificador del pedido es obligatorio.',
    );
  }

  // 2. Validar los saldos actuales.
  const estado = validarSaldos(saldos);

  // 3. Validar la decisión.
  if (decision !== 'aceptar' && decision !== 'rechazar') {
    throw new AtencionParcialError(
      'La decisión debe ser aceptar o rechazar.',
    );
  }

  // 4. Validar los identificadores.
  validarUnidades(
    unidadesPropuestas,
    'Las unidades propuestas',
  );

  const elegibles = validarUnidades(
    unidadesElegibles,
    'Las unidades elegibles',
  );

  // 5. Determinar las reservas nuevas.
  let reservaIds = [];

  if (decision === 'aceptar') {
    reservaIds = [...unidadesPropuestas];

    // No se puede reservar más que el saldo pendiente.
    if (reservaIds.length > estado.pendientePorAsignar) {
      throw new AtencionParcialError(
        'La propuesta supera el saldo pendiente.',
        'STOCK_CONFLICT',
      );
    }

    // Todas las unidades seleccionadas deben seguir disponibles.
    for (const id of reservaIds) {
      if (!elegibles.has(id)) {
        throw new AtencionParcialError(
          `La unidad ${id} ya no está disponible.`,
          'STOCK_CONFLICT',
        );
      }
    }
  }

  // Si se rechaza, no se crean reservas nuevas.
  // Las reservas anteriores permanecen contabilizadas.

  // 6. Calcular el faltante después de la decisión.
  const pendientePorAsignar =
    estado.pendientePorAsignar - reservaIds.length;

  // Las unidades despachadas no cambian en esta operación.
  const pendientePorEntregar =
    estado.pendientePorEntregar;

  // 7. Construir el aviso de faltantes.
  const aviso = {
    pedidoId,
    cantidadFaltante: pendientePorAsignar,
    decision,
  };

  // 8. Devolver la planificación.
  return {
    pedidoId,
    decision,
    reservaIds,
    aviso,
    pendientePorAsignar,
    pendientePorEntregar,
  };
}
