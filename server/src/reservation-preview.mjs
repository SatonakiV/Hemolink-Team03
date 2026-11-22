import { FACTORES_RH, GRUPOS_ABO } from './blood-groups.mjs';
import { fechaValida } from './dates.mjs';
import { consultarStock } from './inventory.mjs';

/**
 * Propone una reserva completa usando el saldo por asignar del pedido.
 * El faltante indica cuánto seguiría sin cubrir si se usara todo el stock elegible.
 */
export function calcularPropuestaFefo(store, { grupoAbo, factorRh, pendienteAsignar, hoy }) {
  if (!GRUPOS_ABO.includes(grupoAbo) || !FACTORES_RH.includes(factorRh)) {
    throw new RangeError('El grupo ABO y el factor Rh del pedido deben ser válidos.');
  }
  if (!Number.isSafeInteger(pendienteAsignar) || pendienteAsignar < 0) {
    throw new RangeError('El saldo por asignar debe ser un entero no negativo.');
  }
  if (!fechaValida(hoy)) throw new RangeError('Ingresa una fecha de corte válida (AAAA-MM-DD).');

  const { items, total: stockElegible } = consultarStock(store, { grupoAbo, factorRh, hoy });
  const faltante = Math.max(0, pendienteAsignar - stockElegible);
  let estado = 'completa';
  if (pendienteAsignar === 0) estado = 'sin_saldo';
  else if (faltante > 0) estado = 'stock_insuficiente';

  return {
    estado,
    pendienteAsignar,
    stockElegible,
    faltante,
    unidades: estado === 'completa' ? items.slice(0, pendienteAsignar) : [],
  };
}
