import { extname } from 'node:path';
import { JsonStore } from './json-store.mjs';
import { SqliteStore } from './sqlite-store.mjs';

export function openStore(path, options) {
  if (extname(path).toLowerCase() === '.json') {
    if (options?.importJsonPath) throw new Error('La importación requiere un destino SQLite.');
    return new JsonStore(path, options);
  }
  return new SqliteStore(path, options);
}
