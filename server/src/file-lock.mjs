import { mkdirSync, readdirSync, writeFileSync, unlinkSync, rmdirSync } from 'node:fs';
import { randomBytes } from 'node:crypto';

const active = new Set();
const sleeper = new Int32Array(new SharedArrayBuffer(4));
const transientWindowsError = error => process.platform === 'win32' && ['EPERM', 'EACCES', 'EBUSY'].includes(error.code);

export class StoreBusyError extends Error {
  constructor() {
    super('La base está ocupada. Vuelve a intentar la operación.');
    this.status = 503;
  }
}

function alive(pid) {
  try { process.kill(pid, 0); return true; }
  catch (error) { return error.code !== 'ESRCH'; }
}

function removeEmpty(path) {
  try { rmdirSync(path); }
  catch (error) {
    // Windows puede mantener un directorio recién eliminado pendiente mientras
    // otro proceso tiene un handle abierto. Dejarlo para el siguiente intento
    // es seguro: rmdir nunca elimina un directorio que tenga propietario.
    if (!['ENOENT', 'ENOTEMPTY', 'EEXIST'].includes(error.code) && !transientWindowsError(error)) throw error;
  }
}

// Nunca se borran archivos de un propietario nuevo ni se usa un vencimiento:
// una transacción lenta de un proceso vivo conserva el bloqueo.
function reap(path) {
  let names;
  try { names = readdirSync(path); }
  catch (error) { if (error.code === 'ENOENT' || transientWindowsError(error)) return; throw error; }
  for (const name of names) {
    const pid = /^owner-(\d+)-[a-f0-9]{32}$/.exec(name)?.[1];
    if (pid && !alive(Number(pid))) {
      try { unlinkSync(`${path}/${name}`); }
      catch (error) { if (error.code !== 'ENOENT' && !transientWindowsError(error)) throw error; }
    }
  }
  removeEmpty(path);
}

export function withFileLock(databasePath, timeoutMs, action) {
  const path = `${databasePath}.lock`;
  if (active.has(path)) throw new StoreBusyError();
  const owner = `owner-${process.pid}-${randomBytes(16).toString('hex')}`;
  const deadline = performance.now() + timeoutMs;
  for (;;) {
    let owned = false;
    try {
      mkdirSync(path, { mode: 0o700 });
      writeFileSync(`${path}/${owner}`, '', { flag: 'wx', mode: 0o600 });
      owned = true;
      // Si un recuperador alcanzó el directorio vacío mientras se creaba el
      // propietario, solo quien observa exclusivamente su archivo puede entrar.
      const names = readdirSync(path);
      if (names.length === 1 && names[0] === owner) {
        active.add(path);
        try { return action(); }
        finally { active.delete(path); }
      }
    } catch (error) {
      if (owned || (!['EEXIST', 'ENOENT'].includes(error.code) && !transientWindowsError(error))) throw error;
    } finally {
      if (owned) {
        unlinkSync(`${path}/${owner}`);
        removeEmpty(path);
      }
    }
    reap(path);
    if (performance.now() >= deadline) throw new StoreBusyError();
    Atomics.wait(sleeper, 0, 0, Math.min(10, Math.max(1, deadline - performance.now())));
  }
}
