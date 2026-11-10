import { randomUUID } from 'node:crypto';

export class MuestraError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function donacionDeSede(db, id, sede) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
    throw new MuestraError(400, 'El identificador de donación no es válido.');
  }
  const donacion = db.records.find(item =>
    item.module === 'donations' && item.id === id && item.scopeId === sede);
  if (!donacion || !db.records.some(item => item.module === 'donors' &&
      item.id === donacion.donanteId && item.scopeId === sede)) {
    throw new MuestraError(404, 'La donación no existe en esta sede.');
  }
  return donacion;
}

// Se ejecuta dentro de JsonStore.update: origen y unicidad se verifican juntos.
export function registrarMuestra(db, datos, user, clock) {
  const codigo = typeof datos.codigo === 'string' ? datos.codigo.trim().toUpperCase() : '';
  if (!/^[A-Z0-9_-]{1,64}$/.test(codigo)) {
    throw new MuestraError(400, 'Ingresa un código de muestra válido.');
  }
  const donacionId = typeof datos.donacionId === 'string' ? datos.donacionId.trim() : '';
  const donacion = donacionDeSede(db, donacionId, user.siteId);
  if (db.records.some(item => item.module === 'samples' &&
      item.codigo.trim().toUpperCase() === codigo)) {
    throw new MuestraError(409, 'Ya existe una muestra con ese código.');
  }
  const item = {
    id: randomUUID(), module: 'samples', codigo, donacionId,
    donanteId: donacion.donanteId, scopeId: donacion.scopeId,
    responsableId: user.id, fechaRegistro: new Date(clock()).toISOString(),
  };
  db.records.push(item);
  return item;
}
