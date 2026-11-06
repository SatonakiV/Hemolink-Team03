import { existsSync, mkdirSync, openSync, writeFileSync, fsyncSync, closeSync, renameSync, readFileSync, rmSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomBytes } from 'node:crypto';

// Un único proceso es dueño del archivo. Las escrituras síncronas serializan
// las transacciones; el reemplazo atómico evita dejar un JSON a medio escribir.
export class JsonStore {
  #data;
  constructor(path) {
    this.path = path;
    mkdirSync(dirname(path), { recursive: true });
    if (existsSync(path)) {
      this.#data = JSON.parse(readFileSync(path, 'utf8'));
      if (this.#data.version !== 1 || !['users', 'sessions', 'records'].every(key => Array.isArray(this.#data[key]))) {
        throw new Error('Formato de base JSON no compatible. Conserve el archivo para revisarlo.');
      }
    } else {
      this.#data = { version: 1, users: [], sessions: [], records: [] };
      this.update(() => {});
    }
  }

  read() { return structuredClone(this.#data); }

  update(change) {
    const next = this.read();
    change(next);
    const temporary = `${this.path}.${randomBytes(8).toString('hex')}.tmp`;
    let descriptor;
    try {
      descriptor = openSync(temporary, 'wx', 0o600);
      writeFileSync(descriptor, JSON.stringify(next, null, 2) + '\n', 'utf8');
      fsyncSync(descriptor);
      closeSync(descriptor);
      descriptor = undefined;
      renameSync(temporary, this.path);
      this.#data = next;
    } finally {
      if (descriptor !== undefined) closeSync(descriptor);
      rmSync(temporary, { force: true });
    }
  }
}
