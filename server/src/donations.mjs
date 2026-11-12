import { fechaValida, sumarDias } from './dates.mjs';
export const VIDA_UTIL_DIAS = 42;
const ID = /^[A-Za-z0-9_-]{1,64}$/;
const CODIGO = /^[A-Za-z0-9_-]{1,32}$/;
const MAX_UNIDADES = 20;
export class DonacionError extends Error {
  constructor(status, message, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}
/**
 * Forma y tipos de la solicitud. Lista: el vencimiento y el responsable nunca se aceptan del cliente. La sede solo se acepta para
 * detectar conflictos con la de la sesión.
 */
export function validarDonacion(datos, hoy) {
  const errors = {};
  if (typeof datos.donanteId !== 'string' || !ID.test(datos.donanteId)) {
    errors.donanteId = 'Selecciona un donante válido.';
  }
  if (typeof datos.evaluacionId !== 'string' || !ID.test(datos.evaluacionId)) {
    errors.evaluacionId = 'Indica la evaluación utilizada.';
  }
  if (!fechaValida(datos.fechaExtraccion)) {
    errors.fechaExtraccion = 'Ingresa una fecha de extracción válida.';
  } else if (datos.fechaExtraccion > hoy) {
    errors.fechaExtraccion = 'La fecha de extracción no puede ser futura.';
  }
  if (!Number.isInteger(datos.volumenMl) || datos.volumenMl <= 0) {
    errors.volumenMl = 'El volumen debe ser un entero positivo en mililitros.';
  }
  if (datos.sedeId !== undefined && typeof datos.sedeId !== 'string') {
    errors.sedeId = 'La sede no es válida.';
  }
  if (datos.fechaVencimiento !== undefined) {
    errors.fechaVencimiento = 'El vencimiento se calcula automáticamente.';
  }

  const unidades = [];
  if (!Array.isArray(datos.unidades) || datos.unidades.length === 0) {
    errors.unidades = 'Agrega minimo una unidad.';
  } else if (datos.unidades.length > MAX_UNIDADES) {
    errors.unidades = `No se admiten más de ${MAX_UNIDADES} unidades.`;
  } else {
    const vistos = new Set();
    for (const unidad of datos.unidades) {
      const codigo = typeof unidad?.codigo === 'string' ? unidad.codigo.trim() : '';
      if (!CODIGO.test(codigo)) {
        errors.unidades = 'Cada unidad necesita un código válido.';
      } else if (vistos.has(codigo.toLowerCase())) {
        errors.unidades = `El código ${codigo} está repetido.`;
      } else if (unidad.fechaVencimiento !== undefined) {
        errors.fechaVencimiento = 'El vencimiento se calcula automáticamente.';
      } else {
        vistos.add(codigo.toLowerCase());
        unidades.push({
          codigo,
          grupoAbo: unidad.grupoAbo,
          factorRh: unidad.factorRh,
        });
      }
    }
  }

  if (Object.keys(errors).length) {
    throw new DonacionError(400, 'Revisa los datos de la donación.', errors);
  }
  return {
    donanteId: datos.donanteId,
    evaluacionId: datos.evaluacionId,
    fechaExtraccion: datos.fechaExtraccion,
    volumenMl: datos.volumenMl,
    sedeId: datos.sedeId,
    unidades,
  };
}

// Regla de HU02 en el servidor: apto y extracción dentro del intervalo.
export function aptitudPermiteExtraer(evaluacion, fechaExtraccion) {
  return evaluacion.resultado === 'apto' &&
    typeof evaluacion.fechaFinVigencia === 'string' &&
    evaluacion.fechaEvaluacion <= fechaExtraccion &&
    fechaExtraccion <= evaluacion.fechaFinVigencia;
}

// Persiste donación y unidades como un solo cambio. Debe ejecutarse dentro de store.update: si lanza, nada se escribe.
export function registrarDonacion(db, user, datos, { id, nuevoIdUnidad, ahora }) {
  const sede = user.siteId;
  if (datos.sedeId !== undefined && datos.sedeId !== sede) {
    throw new DonacionError(409, 'La sede indicada no coincide con la de tu cuenta.');
  }

  const donante = db.records.find(r =>
    r.module === 'donors' && r.scopeId === sede && r.id === datos.donanteId);
  if (!donante) throw new DonacionError(404, 'El donante no existe en esta sede.');

  const evaluaciones = db.records.filter(r =>
    r.module === 'evaluations' && r.scopeId === sede && r.donanteId === donante.id);
  const evaluacion = evaluaciones.find(r => r.id === datos.evaluacionId);
  if (!evaluacion) {
    throw new DonacionError(404, 'La evaluación no existe o no pertenece al donante.');
  }
  // Las evaluaciones se agregan al final del historial: la última es la vigente.
  if (evaluaciones.at(-1).id !== evaluacion.id) {
    throw new DonacionError(409, 'La evaluación indicada no es la vigente del donante.');
  }
  if (!aptitudPermiteExtraer(evaluacion, datos.fechaExtraccion)) {
    throw new DonacionError(409, 'El donante no tiene una evaluación apta para esa fecha.');
  }
  if (!donante.grupoAbo || !donante.factorRh) {
    throw new DonacionError(409, 'El donante no tiene su grupo sanguíneo registrado.');
  }

  const codigosExistentes = new Set(db.records
    .filter(r => r.module === 'inventory' && typeof r.codigo === 'string')
    .map(r => r.codigo.toLowerCase()));
  for (const unidad of datos.unidades) {
    if (codigosExistentes.has(unidad.codigo.toLowerCase())) {
      throw new DonacionError(409, `El código de unidad ${unidad.codigo} ya existe.`);
    }
    const contradice =
      (unidad.grupoAbo !== undefined && unidad.grupoAbo !== donante.grupoAbo) ||
      (unidad.factorRh !== undefined && unidad.factorRh !== donante.factorRh);
    if (contradice) {
      throw new DonacionError(409,
        `El grupo de la unidad ${unidad.codigo} contradice el del donante.`);
    }
  }

  const donacion = {
    id, module: 'donations', scopeId: sede, sedeId: sede,
    label: `Donación ${datos.fechaExtraccion} · ${datos.unidades.length} unidad(es)`,
    donanteId: donante.id, evaluacionId: evaluacion.id,
    fechaExtraccion: datos.fechaExtraccion, volumenMl: datos.volumenMl,
    responsableId: user.id, fechaRegistro: ahora,
  };
  // Las unidades viven en el módulo inventory para que el stock las vea.
  const unidades = datos.unidades.map(unidad => ({
    id: nuevoIdUnidad(), module: 'inventory', scopeId: sede, sedeId: sede,
    label: `${unidad.codigo} · ${donante.grupoAbo}${donante.factorRh === 'positivo' ? '+' : '-'}`,
    codigo: unidad.codigo, donacionId: id,
    grupoAbo: donante.grupoAbo, factorRh: donante.factorRh,
    estado: 'disponible',
    fechaVencimiento: sumarDias(datos.fechaExtraccion, VIDA_UTIL_DIAS),
    fechaRegistro: ahora,
  }));

  db.records.push(donacion, ...unidades);
  return donacion;
}

//Donación con su cadena completa: donante, evaluación utilizada y unidades.
export function detalleDonacion(db, user, id) {
  const donacion = db.records.find(r =>
    r.module === 'donations' && r.scopeId === user.siteId && r.id === id);
  if (!donacion) return null;
  const buscar = (module, valor) =>
    db.records.find(r => r.module === module && r.id === valor) ?? null;
  return {
    ...donacion,
    donante: buscar('donors', donacion.donanteId),
    evaluacion: buscar('evaluations', donacion.evaluacionId),
    unidades: db.records.filter(r =>
      r.module === 'inventory' && r.donacionId === donacion.id),
  };
}
