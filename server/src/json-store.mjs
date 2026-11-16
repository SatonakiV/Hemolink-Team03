import { existsSync, mkdirSync, realpathSync } from 'node:fs';
import { dirname, basename, resolve, join } from 'node:path';
import { applyChange, encodeDatabase } from './store-validation.mjs';
import { withFileLock } from './file-lock.mjs';
import { auditDatabase } from './database-audit.mjs';
import {
  GENESIS, STORAGE_KEY, signature, atomicSnapshot, loadSnapshot,
  appendJournal, replayJournal, truncateJournal,
} from './json-journal.mjs';

const tables = ['users', 'sessions', 'records'];
const indexed = {
  users: ['id', 'email'], sessions: ['tokenHash', 'userId'],
  records: ['id', 'module', 'scopeId', 'donanteId', 'evaluacionId', 'donacionId', 'rut', 'codigo'],
};
const empty = () => ({ version: 1, users: [], sessions: [], records: [] });
function canonicalPath(path) {
  const absolute = resolve(path);
  let canonical;
  try { canonical = realpathSync(absolute); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    canonical = join(realpathSync(dirname(absolute)), basename(absolute));
  }
  return process.platform === 'win32' ? canonical.toLowerCase() : canonical;
}

// Instantánea JSON + diario incremental con checksum. Todas las operaciones
// coordinan instancias/procesos mediante un bloqueo breve del mismo archivo.
export class JsonStore {
  #path;
  #data;
  #sequence = 0;
  #commitHash = GENESIS;
  #offset = 0;
  #snapshotStat;
  #journalStat;
  #indexes = {};
  #updating = false;
  #closed = false;
  #recoveryRequired = false;
  #options;

  constructor(path, { checkpointBytes = 1024 * 1024, busyTimeoutMs = 1000 } = {}) {
    if (!Number.isSafeInteger(checkpointBytes) || checkpointBytes < 1 ||
        !Number.isSafeInteger(busyTimeoutMs) || busyTimeoutMs < 0 || busyTimeoutMs > 5000) {
      throw new TypeError('Configuración de persistencia no válida.');
    }
    const absolute = resolve(path);
    mkdirSync(dirname(absolute), { recursive: true });
    this.#path = canonicalPath(absolute);
    this.path = path;
    this.#options = { checkpointBytes, busyTimeoutMs };
    this.#locked(() => {
      if (!existsSync(this.#path)) {
        if (signature(this.#journalPath)) throw new Error('Falta la instantánea JSON. Conserve el diario para recuperarla.');
        atomicSnapshot(this.#path, empty(), 0, GENESIS);
      }
      this.#refresh(true);
    });
  }

  get #journalPath() { return `${this.#path}.wal`; }

  #locked(action) {
    if (this.#closed) throw new Error('La base está cerrada.');
    if (this.#recoveryRequired) throw new Error('Fallo de disco: cierre y reabra la base para verificar su recuperación.');
    return withFileLock(this.#path, this.#options.busyTimeoutMs, action);
  }

  #refresh(force = false) {
    const snapshotStat = signature(this.#path);
    const journalStat = signature(this.#journalPath);
    if (!force && snapshotStat?.key === this.#snapshotStat?.key && journalStat?.key === this.#journalStat?.key) return;
    const incremental = !force && this.#data && snapshotStat?.key === this.#snapshotStat?.key &&
      journalStat && journalStat.identity === this.#journalStat?.identity && journalStat.size > this.#offset;
    const base = incremental ? { data: this.#data, sequence: this.#sequence, commitHash: this.#commitHash }
      : loadSnapshot(this.#path);
    const recovered = replayJournal(this.#journalPath, base, incremental ? this.#offset : 0);
    if (this.#data && recovered.sequence < this.#sequence) throw new Error('La base perdió transacciones confirmadas. Conserve los archivos.');
    this.#publish(recovered.data, recovered);
    this.#snapshotStat = snapshotStat;
    this.#journalStat = signature(this.#journalPath);
  }

  #publish(data, { sequence, commitHash, offset, changedTables = tables }) {
    this.#data = data;
    this.#sequence = sequence;
    this.#commitHash = commitHash;
    this.#offset = offset;
    for (const table of changedTables) delete this.#indexes[table];
  }

  #index(table, field) {
    const fields = this.#indexes[table] ??= new Map();
    if (!fields.has(field)) {
      const index = new Map();
      for (const row of this.#data[table]) {
        const value = row[field];
        if (!index.has(value)) index.set(value, []);
        index.get(value).push(row);
      }
      fields.set(field, index);
    }
    return fields.get(field);
  }

  #select(query) {
    if (query === undefined) return structuredClone(this.#data);
    if (!query || Array.isArray(query) || typeof query !== 'object') throw new TypeError('Consulta JSON no válida.');
    const result = empty();
    for (const [table, where] of Object.entries(query)) {
      if (!tables.includes(table) || !where || Array.isArray(where) || typeof where !== 'object') {
        throw new TypeError('Colección de consulta no válida.');
      }
      let candidates = this.#data[table];
      const filters = Object.entries(where);
      for (const [field, value] of filters) {
        if (!indexed[table].includes(field)) throw new TypeError('Campo de consulta no indexado.');
        const matches = this.#index(table, field).get(value) ?? [];
        if (matches.length < candidates.length) candidates = matches;
      }
      result[table] = structuredClone(candidates.filter(row => filters.every(([key, value]) => row[key] === value)));
    }
    return result;
  }

  // Sin argumento conserva el contrato original. Con consulta solo se clonan
  // las filas seleccionadas. Nunca se devuelven referencias internas.
  read(query) {
    if (this.#updating) return this.#select(query);
    return this.#locked(() => { this.#refresh(); return this.#select(query); });
  }

  update(change) {
    if (this.#updating) throw new Error('No se permiten transacciones anidadas.');
    if (canonicalPath(this.path) !== this.#path) {
      throw new Error('No se puede cambiar la ruta de una base abierta.');
    }
    return this.#locked(() => {
      this.#refresh();
      this.#updating = true;
      try {
        const next = this.read();
        const encoded = applyChange(change, next);
        if (Object.hasOwn(next, STORAGE_KEY)) throw new Error('Metadatos de persistencia reservados.');
        if (encoded === encodeDatabase(this.#data)) return;
        const committed = JSON.parse(encoded);
        // Compactar antes de confirmar el cambio nuevo: un fallo del checkpoint
        // no transforma una transacción ya confirmada en una respuesta de error.
        if (this.#offset >= this.#options.checkpointBytes) this.#checkpoint();
        let commit;
        try { commit = appendJournal(this.#journalPath, this.#data, committed, this.#sequence, this.#commitHash); }
        catch (error) { if (error.recoveryRequired) this.#recoveryRequired = true; throw error; }
        this.#publish(committed, commit);
        this.#journalStat = signature(this.#journalPath);
      } finally {
        this.#updating = false;
      }
    });
  }

  #checkpoint() {
    atomicSnapshot(this.#path, this.#data, this.#sequence, this.#commitHash);
    this.#snapshotStat = signature(this.#path);
    truncateJournal(this.#journalPath, 0);
    this.#offset = 0;
    this.#journalStat = signature(this.#journalPath);
  }

  checkpoint() {
    if (this.#updating) throw new Error('No se puede compactar dentro de una transacción.');
    return this.#locked(() => { this.#refresh(); this.#checkpoint(); });
  }

  backupTo(path) {
    if (this.#updating) throw new Error('No se puede respaldar dentro de una transacción.');
    return this.#locked(() => {
      this.#refresh();
      const target = resolve(path);
      const canonical = join(realpathSync(dirname(target)), basename(target));
      const comparison = process.platform === 'win32' ? canonical.toLowerCase() : canonical;
      if ([this.#path, this.#journalPath, `${this.#path}.lock`].includes(comparison) ||
          comparison.startsWith(`${this.#path}.lock/`) || comparison.startsWith(`${this.#path}.lock\\`)) {
        throw new Error('El respaldo requiere un archivo de destino independiente.');
      }
      atomicSnapshot(target, this.#data, this.#sequence, this.#commitHash, { exclusive: true });
    });
  }

  verify({ references = false } = {}) {
    if (this.#updating) throw new Error('No se puede verificar dentro de una transacción.');
    return this.#locked(() => {
      this.#refresh(true);
      return { ...(references ? auditDatabase(this.#data) : { ok: true }), sequence: this.#sequence,
        counts: Object.fromEntries(tables.map(table => [table, this.#data[table].length])) };
    });
  }

  close({ checkpoint = false } = {}) {
    if (this.#closed) return;
    if (this.#updating) throw new Error('No se puede cerrar dentro de una transacción.');
    if (checkpoint) this.checkpoint();
    this.#closed = true;
  }
}
