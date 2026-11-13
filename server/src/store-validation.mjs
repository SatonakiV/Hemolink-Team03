// El contrato de persistencia admite únicamente valores JSON sin conversiones
// silenciosas (NaN, fechas, undefined, ciclos o prototipos personalizados).
export function encodeDatabase(data) {
  const ancestors = new Set();
  function visit(value) {
    if (value === null || typeof value === 'string' || typeof value === 'boolean') return;
    if (typeof value === 'number' && Number.isFinite(value)) return;
    if (typeof value !== 'object' || ancestors.has(value) ||
        (!Array.isArray(value) && Object.getPrototypeOf(value) !== Object.prototype)) {
      throw new TypeError('La base solo admite valores JSON válidos.');
    }
    ancestors.add(value);
    for (const key of Reflect.ownKeys(value)) {
      if (Array.isArray(value) && key === 'length') continue;
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (typeof key !== 'string' || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value') ||
          (Array.isArray(value) && !/^(0|[1-9][0-9]*)$/.test(key))) {
        throw new TypeError('La base solo admite propiedades JSON enumerables.');
      }
      visit(descriptor.value);
    }
    if (Array.isArray(value) && Object.keys(value).length !== value.length) {
      throw new TypeError('La base no admite arreglos dispersos.');
    }
    ancestors.delete(value);
  }
  if (!data || data.version !== 1 ||
      !['users', 'sessions', 'records'].every(key => Array.isArray(data[key]) &&
        data[key].every(item => item && typeof item === 'object' && !Array.isArray(item)))) {
    throw new Error('Formato de base no compatible. Conserve el archivo para revisarlo.');
  }
  visit(data);
  for (const user of data.users) {
    if (typeof user.id !== 'string' || !user.id || typeof user.email !== 'string' || !user.email.trim()) {
      throw new TypeError('Cada usuario necesita identificador y correo.');
    }
  }
  for (const row of data.records) {
    if (typeof row.id !== 'string' || !row.id || typeof row.module !== 'string' || !row.module) {
      throw new TypeError('Cada registro necesita identificador y módulo.');
    }
    for (const field of ['scopeId', 'donanteId', 'evaluacionId', 'donacionId', 'rut', 'codigo']) {
      if (row[field] !== undefined && row[field] !== null && typeof row[field] !== 'string') {
        throw new TypeError('Las claves y referencias de un registro deben ser texto.');
      }
    }
  }
  const users = new Set(data.users.map(user => user.id));
  for (const session of data.sessions) {
    if (typeof session.tokenHash !== 'string' || !/^[a-f0-9]{64}$/.test(session.tokenHash) ||
        !Number.isSafeInteger(session.expiresAt) || session.expiresAt <= 0 || !users.has(session.userId)) {
      throw new TypeError('La sesión necesita hash, vencimiento y usuario existente.');
    }
  }
  validateKeys(data);
  return JSON.stringify(data);
}

export class StoreConstraintError extends Error {
  constructor() {
    super('El cambio incumple una restricción de integridad de la base.');
    this.status = 409;
  }
}

function validateKeys(data) {
  const unique = (rows, key) => {
    const seen = new Set();
    for (const row of rows) {
      const value = key(row);
      if (value === undefined || value === null) continue;
      if (seen.has(value)) throw new StoreConstraintError();
      seen.add(value);
    }
  };
  unique(data.users, row => row.id);
  unique(data.users, row => typeof row.email === 'string' ? row.email.trim().toLowerCase() : undefined);
  unique(data.sessions, row => row.tokenHash);
  unique(data.records, row => JSON.stringify([row.module, row.id]));
  // Las reglas clínicas y las claves de negocio se comprueban en la misma
  // transacción por cada módulo. No se reinterpretan los registros históricos.
}

export function applyChange(change, data) {
  if (typeof change !== 'function' || change.constructor.name === 'AsyncFunction') {
    throw new TypeError('La transacción requiere una función síncrona.');
  }
  const result = change(data);
  if (result && typeof result.then === 'function') {
    // Evita rechazos sin manejar de funciones que devuelven una promesa.
    Promise.resolve(result).catch(() => {});
    throw new TypeError('La transacción no puede devolver una promesa.');
  }
  return encodeDatabase(data);
}
