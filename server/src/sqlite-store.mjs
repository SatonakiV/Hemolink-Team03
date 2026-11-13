import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readFileSync, openSync, closeSync, realpathSync, fsyncSync, rmSync } from 'node:fs';
import { dirname, basename, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { applyChange, encodeDatabase, StoreConstraintError } from './store-validation.mjs';
import { StoreBusyError } from './file-lock.mjs';
import { auditDatabase } from './database-audit.mjs';
import { atomicSnapshot, GENESIS, publishFile, STORAGE_KEY } from './json-journal.mjs';
import { readJsonDatabase } from './json-import.mjs';

const APPLICATION_ID = 0x48454d4f; // HEMO
const SCHEMA_VERSION = 1;
const tables = ['users', 'sessions', 'records'];
const fields = {
  users: { id: 'id', email: 'email' },
  sessions: { tokenHash: 'token_hash', userId: 'user_id' },
  records: { id: 'id', module: 'module', scopeId: 'scope_id', donanteId: 'donor_id',
    evaluacionId: 'evaluation_id', donacionId: 'donation_id', rut: 'rut', codigo: 'code' },
};
const key = (table, row) => table === 'records' ? JSON.stringify([row.module, row.id])
  : table === 'sessions' ? row.tokenHash : row.id;
const decode = row => JSON.parse(row.payload);
const empty = () => ({ version: 1, users: [], sessions: [], records: [] });
const root = data => JSON.stringify(Object.fromEntries(Object.entries(data).filter(([name]) => !tables.includes(name))));

function translate(error) {
  const code = error.errcode & 0xff;
  if (code === 5 || code === 6) return new StoreBusyError();
  if (code === 19) return new StoreConstraintError();
  return error;
}

export class SqliteStore {
  #db;
  #statements = new Map();
  #transaction = false;
  #closed = false;
  #path;

  constructor(path, { importJsonPath, requireNew = false, busyTimeoutMs = 5000 } = {}) {
    if (!Number.isSafeInteger(busyTimeoutMs) || busyTimeoutMs < 0 || busyTimeoutMs > 5000) {
      throw new TypeError('Tiempo de espera SQLite no válido.');
    }
    this.path = path;
    this.#path = path === ':memory:' ? path : resolve(path);
    if (path !== ':memory:') {
      mkdirSync(dirname(this.#path), { recursive: true });
      // El modo inicial también se hereda en los archivos auxiliares de SQLite.
      try { closeSync(openSync(this.#path, 'wx', 0o600)); }
      catch (error) { if (error.code !== 'EEXIST' || requireNew) throw error; }
    }
    try {
      this.#db = new DatabaseSync(this.#path);
      this.#db.exec(`PRAGMA busy_timeout = ${busyTimeoutMs}; PRAGMA foreign_keys = ON; PRAGMA synchronous = FULL;`);
      this.#run('IMMEDIATE', () => {
        const version = this.#statement('PRAGMA user_version').get().user_version;
        const applicationId = this.#statement('PRAGMA application_id').get().application_id;
        const count = this.#statement("SELECT count(*) AS n FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").get().n;
        if (version === 0 && applicationId === 0 && count === 0) {
          this.#db.exec(readFileSync(new URL('./sqlite-schema.sql', import.meta.url), 'utf8'));
          this.#db.exec(`PRAGMA application_id = ${APPLICATION_ID}; PRAGMA user_version = ${SCHEMA_VERSION};`);
          // Esquema e importación comparten el mismo COMMIT. Si falla una
          // restricción no queda una base vacía marcada como importada.
          if (importJsonPath) {
            const data = readJsonDatabase(importJsonPath);
            encodeDatabase(data);
            if (!auditDatabase(data).ok) {
              const error = new StoreConstraintError();
              error.message = 'El JSON contiene inconsistencias. Ejecute database-tool.mjs audit sobre el origen; no se modificaron sus datos.';
              throw error;
            }
            this.#write(empty(), data);
          }
        } else if (version !== SCHEMA_VERSION || applicationId !== APPLICATION_ID) {
          throw new Error('Base SQLite ajena o versión no compatible. Conserve el archivo.');
        }
      });
      this.#db.exec('PRAGMA journal_mode = WAL;');
    } catch (error) {
      this.#db?.close();
      throw translate(error);
    }
  }

  #ensureOpen() {
    if (this.#closed) throw new Error('La base está cerrada.');
  }

  #statement(sql) {
    this.#ensureOpen();
    if (!this.#statements.has(sql)) this.#statements.set(sql, this.#db.prepare(sql));
    return this.#statements.get(sql);
  }

  #run(mode, action) {
    this.#ensureOpen();
    if (this.#transaction) throw new Error('No se permiten transacciones anidadas.');
    try { this.#db.exec(`BEGIN ${mode}`); }
    catch (error) { throw translate(error); }
    this.#transaction = true;
    try {
      const result = action();
      this.#db.exec('COMMIT');
      return result;
    } catch (error) {
      try { this.#db.exec('ROLLBACK'); } catch { /* SQLite puede haber revertido automáticamente por E/S. */ }
      throw translate(error);
    } finally { this.#transaction = false; }
  }

  #read(query) {
    const data = query === undefined ? JSON.parse(this.#statement('SELECT payload FROM database_meta WHERE singleton = 1').get().payload)
      : { version: 1 };
    for (const table of tables) data[table] = [];
    if (query !== undefined && (!query || Array.isArray(query) || typeof query !== 'object')) {
      throw new TypeError('Consulta no válida.');
    }
    for (const [table, where] of Object.entries(query ?? Object.fromEntries(tables.map(table => [table, {}])))) {
      if (!tables.includes(table) || !where || Array.isArray(where) || typeof where !== 'object') {
        throw new TypeError('Colección de consulta no válida.');
      }
      const clauses = [], values = [];
      for (const [field, value] of Object.entries(where)) {
        const column = fields[table][field];
        if (!Object.hasOwn(fields[table], field)) throw new TypeError('Campo de consulta no indexado.');
        if (value === undefined) clauses.push(`json_type(payload, '$.${field}') IS NULL`);
        else if (value === null) clauses.push(`json_type(payload, '$.${field}') = 'null'`);
        else { clauses.push(`${column} = ?`); values.push(value); }
      }
      data[table] = this.#statement(`SELECT payload FROM ${table}${clauses.length ? ' WHERE ' + clauses.join(' AND ') : ''} ORDER BY position`)
        .all(...values).map(decode);
    }
    return data;
  }

  read(query) {
    this.#ensureOpen();
    return this.#transaction ? this.#read(query) : this.#run('DEFERRED', () => this.#read(query));
  }

  #write(previous, next) {
    let changed = root(previous) !== root(next);
    for (const table of tables) {
      const before = new Map(previous[table].map((row, index) => [key(table, row), { row, index }]));
      const after = new Map(next[table].map((row, index) => [key(table, row), { row, index }]));
      const different = (old, current) => !old || !current || old.index !== current.index ||
        JSON.stringify(old.row) !== JSON.stringify(current.row);
      const where = table === 'records' ? 'module = ? AND id = ?' : table === 'users' ? 'id = ?' : 'token_hash = ?';
      // Primero eliminar todas las filas cambiadas permite intercambiar claves
      // únicas y posiciones sin conflictos transitorios. Las FK son diferidas.
      for (const [id, old] of before) {
        if (!different(old, after.get(id))) continue;
        changed = true;
        const values = table === 'records' ? [old.row.module, old.row.id] : [key(table, old.row)];
        this.#statement(`DELETE FROM ${table} WHERE ${where}`).run(...values);
      }
      for (const [id, current] of after) {
        if (!different(before.get(id), current)) continue;
        changed = true;
        const values = table === 'records' ? [current.row.module, current.row.id] : [key(table, current.row)];
        this.#statement(table === 'records'
          ? 'INSERT INTO records(module, id, position, payload) VALUES (?, ?, ?, ?)'
          : `INSERT INTO ${table}(${table === 'users' ? 'id' : 'token_hash'}, position, payload) VALUES (?, ?, ?)`)
          .run(...values, current.index, JSON.stringify(current.row));
      }
    }
    if (changed) {
      const sequence = this.#statement('SELECT sequence FROM database_meta WHERE singleton = 1').get().sequence;
      if (sequence >= Number.MAX_SAFE_INTEGER) throw new Error('Se agotó el contador de transacciones.');
      this.#statement('UPDATE database_meta SET payload = ?, sequence = sequence + 1 WHERE singleton = 1').run(root(next));
    }
  }

  update(change) {
    this.#ensureOpen();
    if (resolve(this.path) !== resolve(this.#path) && this.#path !== ':memory:') {
      throw new Error('No se puede cambiar la ruta de una base abierta.');
    }
    return this.#run('IMMEDIATE', () => {
      const previous = this.#read();
      const next = structuredClone(previous);
      applyChange(change, next);
      if (Object.hasOwn(next, STORAGE_KEY)) throw new Error('Metadatos de persistencia reservados.');
      this.#write(previous, next);
    });
  }

  verify({ references = false } = {}) {
    return this.#run('DEFERRED', () => {
      const integrity = this.#statement('PRAGMA integrity_check').all().map(row => row.integrity_check);
      const foreignKeys = this.#statement('PRAGMA foreign_key_check').all();
      const data = this.#read();
      encodeDatabase(data);
      const audit = references ? auditDatabase(data) : { ok: true };
      return { ...audit, ok: audit.ok && integrity.length === 1 && integrity[0] === 'ok' && foreignKeys.length === 0,
        engine: 'sqlite', integrity, foreignKeys,
        sequence: this.#statement('SELECT sequence FROM database_meta WHERE singleton = 1').get().sequence,
        counts: Object.fromEntries(tables.map(table => [table, data[table].length])) };
    });
  }

  checkpoint() {
    this.#ensureOpen();
    if (this.#transaction) throw new Error('No se puede compactar dentro de una transacción.');
    try {
      const result = this.#statement('PRAGMA wal_checkpoint(TRUNCATE)').get();
      if (result.busy) throw new StoreBusyError();
    } catch (error) { throw translate(error); }
  }

  #backupTarget(path) {
    const target = resolve(path);
    if (this.#path !== ':memory:') {
      const normalize = value => process.platform === 'win32' ? value.toLowerCase() : value;
      const candidate = normalize(resolve(realpathSync(dirname(target)), basename(target)));
      const active = normalize(realpathSync(this.#path));
      if ([active, `${active}-wal`, `${active}-shm`, `${active}-journal`].includes(candidate)) {
        throw new Error('El respaldo requiere un archivo independiente.');
      }
    }
    return target;
  }

  exportJsonTo(path) {
    this.#ensureOpen();
    if (this.#transaction) throw new Error('No se puede exportar dentro de una transacción.');
    const target = this.#backupTarget(path);
    const data = this.read();
    // Un JSON autónomo inicia su propio diario desde cero; mantiene todos los
    // usuarios, hashes, sesiones, registros, orden y campos adicionales.
    atomicSnapshot(target, data, 0, GENESIS, { exclusive: true });
  }

  backupTo(path) {
    this.#ensureOpen();
    if (this.#transaction) throw new Error('No se puede respaldar dentro de una transacción.');
    const target = this.#backupTarget(path);
    const temporary = `${target}.${randomBytes(16).toString('hex')}.tmp`;
    closeSync(openSync(temporary, 'wx', 0o600));
    try {
      this.#statement('VACUUM INTO ?').run(temporary);
      const descriptor = openSync(temporary, 'r+');
      try { fsyncSync(descriptor); } finally { closeSync(descriptor); }
      publishFile(temporary, target, { exclusive: true });
    } catch (error) { throw translate(error); }
    finally { rmSync(temporary, { force: true }); }
  }

  close({ checkpoint = false } = {}) {
    if (this.#closed) return;
    if (this.#transaction) throw new Error('No se puede cerrar dentro de una transacción.');
    try { if (checkpoint) this.checkpoint(); }
    finally { this.#db.close(); this.#closed = true; this.#statements.clear(); }
  }
}
