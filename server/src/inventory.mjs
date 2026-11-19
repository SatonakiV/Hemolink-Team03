import { GRUPOS_ABO, FACTORES_RH } from './blood-groups.mjs';
import { fechaValida } from './dates.mjs';

const tieneTexto = valor => typeof valor === 'string' && valor.trim().length > 0;

export function unidadElegible(unidad, hoy) {
  return unidad.module === 'inventory' && unidad.estado === 'disponible' &&
    tieneTexto(unidad.id) && tieneTexto(unidad.scopeId) &&
    tieneTexto(unidad.codigo) && tieneTexto(unidad.donacionId) &&
    GRUPOS_ABO.includes(unidad.grupoAbo) && FACTORES_RH.includes(unidad.factorRh) &&
    fechaValida(unidad.fechaVencimiento) && hoy < unidad.fechaVencimiento;
}

export function consultarStock(store, { sedeId, grupoAbo, factorRh, hoy }) {
  const { records } = store.read({ records: {
    module: 'inventory',
    ...(sedeId === undefined ? {} : { scopeId: sedeId }),
  } });
  const items = records
    .filter(unidad => unidadElegible(unidad, hoy) &&
      (grupoAbo === undefined || unidad.grupoAbo === grupoAbo) &&
      (factorRh === undefined || unidad.factorRh === factorRh))
    .sort((a, b) => a.fechaVencimiento.localeCompare(b.fechaVencimiento) || a.id.localeCompare(b.id, 'en'))
    .map(({ id, scopeId, codigo, donacionId, grupoAbo, factorRh, estado, fechaVencimiento }) => ({
      id, sedeId: scopeId, codigo, donacionId, grupoAbo, factorRh, estado, fechaVencimiento,
      label: `${codigo} · ${grupoAbo}${factorRh === 'positivo' ? '+' : '-'}`,
    }));
  return { items, total: items.length };
}
