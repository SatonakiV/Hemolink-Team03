import {
  openSync, writeFileSync, readFileSync, fsyncSync, closeSync, renameSync,
  rmSync, linkSync, statSync, ftruncateSync, readSync, writeSync,
} from 'node:fs';
import { dirname } from 'node:path';
import { createHash, randomBytes } from 'node:crypto';
import { encodeDatabase } from './store-validation.mjs';

export const GENESIS = '0'.repeat(64);
export const STORAGE_KEY = '__hemolink_storage';
const tables = ['users', 'sessions', 'records'];
export const digest = value => createHash('sha256').update(value).digest('hex');

function syncDirectory(path) {
  // Windows no permite abrir directorios con fs.open; el archivo sí se fsync.
  if (process.platform === 'win32') return;
  const fd = openSync(dirname(path), 'r');
  try { fsyncSync(fd); } finally { closeSync(fd); }
}

export function publishFile(temporary, path, { exclusive = false } = {}) {
  if (exclusive) linkSync(temporary, path);
  else renameSync(temporary, path);
  syncDirectory(path);
}

export function signature(path) {
  try {
    const s = statSync(path, { bigint: true });
    return { key: `${s.dev}:${s.ino}:${s.size}:${s.mtimeNs}:${s.ctimeNs}`, size: Number(s.size), identity: `${s.dev}:${s.ino}` };
  } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

export function atomicSnapshot(path, data, sequence, commitHash, { exclusive = false } = {}) {
  const encoded = encodeDatabase(data);
  const snapshot = JSON.stringify({ ...data, [STORAGE_KEY]: {
    version: 1, sequence, commitHash, dataHash: digest(encoded),
  } }) + '\n';
  const temporary = `${path}.${randomBytes(16).toString('hex')}.tmp`;
  let fd;
  try {
    fd = openSync(temporary, 'wx', 0o600);
    writeFileSync(fd, snapshot, 'utf8');
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    publishFile(temporary, path, { exclusive });
  } finally {
    if (fd !== undefined) closeSync(fd);
    rmSync(temporary, { force: true });
  }
}

export function loadSnapshot(path) {
  const parsed = JSON.parse(readFileSync(path, 'utf8'));
  const hasMetadata = parsed && Object.hasOwn(parsed, STORAGE_KEY);
  const metadata = parsed[STORAGE_KEY];
  delete parsed[STORAGE_KEY];
  const encoded = encodeDatabase(parsed);
  if (!hasMetadata) return { data: parsed, sequence: 0, commitHash: GENESIS };
  if (!metadata || metadata.version !== 1 || !Number.isSafeInteger(metadata.sequence) || metadata.sequence < 0 ||
      !/^[a-f0-9]{64}$/.test(metadata.commitHash) || metadata.dataHash !== digest(encoded)) {
    throw new Error('La instantánea JSON no supera la comprobación de integridad. Conserve los archivos.');
  }
  return { data: parsed, sequence: metadata.sequence, commitHash: metadata.commitHash };
}

export function changesBetween(previous, next) {
  const changes = { root: Object.fromEntries(Object.entries(next).filter(([key]) => !tables.includes(key))) };
  for (const table of tables) {
    const set = [];
    next[table].forEach((row, index) => {
      if (JSON.stringify(row) !== JSON.stringify(previous[table][index])) set.push([index, row]);
    });
    changes[table] = { length: next[table].length, set };
  }
  return changes;
}

function applyChanges(previous, changes) {
  if (!changes?.root || typeof changes.root !== 'object' || Array.isArray(changes.root)) {
    throw new Error('Cabecera de transacción JSON inválida.');
  }
  const next = { ...changes.root };
  for (const table of tables) {
    const delta = changes[table];
    if (!delta || !Number.isSafeInteger(delta.length) || delta.length < 0 || !Array.isArray(delta.set)) {
      throw new Error('Transacción JSON inválida.');
    }
    next[table] = previous[table].slice(0, delta.length);
    const seen = new Set();
    for (const entry of delta.set) {
      if (!Array.isArray(entry) || entry.length !== 2 || !Number.isSafeInteger(entry[0]) ||
          entry[0] < 0 || entry[0] >= delta.length || seen.has(entry[0])) throw new Error('Cambio JSON inválido.');
      seen.add(entry[0]);
      next[table][entry[0]] = entry[1];
    }
    if (next[table].length !== delta.length) throw new Error('Transacción JSON incompleta.');
  }
  encodeDatabase(next);
  return next;
}

export function truncateJournal(path, size) {
  const fd = openForUpdate(path);
  try { ftruncateSync(fd, size); fsyncSync(fd); }
  finally { closeSync(fd); }
}

function openForUpdate(path) {
  try { return openSync(path, 'r+'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; return openSync(path, 'wx+', 0o600); }
}

export function replayJournal(path, snapshot, offset = 0, { repairTail = true } = {}) {
  const stat = signature(path);
  if (!stat) return { ...snapshot, offset: 0 };
  const fd = openSync(path, 'r');
  const bytes = Buffer.alloc(stat.size - offset);
  try {
    let read = 0;
    while (read < bytes.length) {
      const count = readSync(fd, bytes, read, bytes.length - read, offset + read);
      if (!count) throw new Error('Lectura incompleta del diario JSON.');
      read += count;
    }
  } finally { closeSync(fd); }
  const end = bytes.lastIndexOf(10) + 1;
  const complete = bytes.subarray(0, end).toString('utf8');
  let { data, sequence, commitHash } = snapshot;
  let lastSeen;
  for (const line of complete.split('\n')) {
    if (!line) continue;
    const { checksum, ...entry } = JSON.parse(line);
    if (entry.version !== 1 || !Number.isSafeInteger(entry.sequence) || entry.sequence < 1 ||
        !/^[a-f0-9]{64}$/.test(entry.previous) || checksum !== digest(JSON.stringify(entry))) {
      throw new Error('El diario JSON no supera la comprobación de integridad. Conserve los archivos.');
    }
    if (lastSeen && (entry.sequence !== lastSeen.sequence + 1 || entry.previous !== lastSeen.checksum)) {
      throw new Error('El diario JSON contiene una discontinuidad.');
    }
    lastSeen = { sequence: entry.sequence, checksum };
    if (entry.sequence <= sequence) {
      if (entry.sequence === sequence && checksum !== commitHash) throw new Error('La instantánea y el diario JSON no coinciden.');
      continue;
    }
    if (entry.sequence !== sequence + 1 || entry.previous !== commitHash) throw new Error('Falta una transacción del diario JSON.');
    data = applyChanges(data, entry.changes);
    sequence = entry.sequence;
    commitHash = checksum;
  }
  // Solo se descarta una cola sin salto de línea. La corrupción de una
  // transacción completa nunca se interpreta como una escritura interrumpida.
  if (repairTail && end !== bytes.length) truncateJournal(path, offset + end);
  return { data, sequence, commitHash, offset: offset + end };
}

export function appendJournal(path, previous, next, sequence, commitHash) {
  if (sequence >= Number.MAX_SAFE_INTEGER) throw new Error('Se agotó el contador de transacciones JSON.');
  const entry = { version: 1, sequence: sequence + 1, previous: commitHash, changes: changesBetween(previous, next) };
  const checksum = digest(JSON.stringify(entry));
  const line = JSON.stringify({ ...entry, checksum }) + '\n';
  const size = signature(path)?.size ?? 0;
  const fd = openForUpdate(path);
  try {
    const bytes = Buffer.from(line, 'utf8');
    let written = 0;
    while (written < bytes.length) {
      const count = writeSync(fd, bytes, written, bytes.length - written, size + written);
      if (!count) throw new Error('Escritura incompleta del diario JSON.');
      written += count;
    }
    fsyncSync(fd);
    if (size === 0) syncDirectory(path);
  } catch (error) {
    try { ftruncateSync(fd, size); fsyncSync(fd); }
    catch { error.recoveryRequired = true; }
    throw error;
  } finally { closeSync(fd); }
  return { sequence: sequence + 1, commitHash: checksum, offset: size + Buffer.byteLength(line),
    changedTables: tables.filter(table => entry.changes[table].set.length > 0 || previous[table].length !== next[table].length) };
}
