import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { extname } from 'node:path';
import { openStore } from './store.mjs';
import { SqliteStore } from './sqlite-store.mjs';

const [command, databasePath = process.env.HEMOLINK_DATABASE ??
  fileURLToPath(new URL('../data/hemolink.sqlite', import.meta.url)), destination, extra] = process.argv.slice(2);
const needsDestination = ['backup', 'import-json', 'export-json'].includes(command);

if (!['verify', 'audit', 'checkpoint', 'backup', 'import-json', 'export-json'].includes(command) || extra ||
    (command === 'import-json' && destination && extname(destination).toLowerCase() === '.json') ||
    (command === 'export-json' && destination && extname(destination).toLowerCase() !== '.json') ||
    (needsDestination && !destination) || (!needsDestination && destination)) {
  console.error('Uso: node server/src/database-tool.mjs verify|audit|checkpoint [base.sqlite|base.json]');
  console.error('     node server/src/database-tool.mjs backup origen destino');
  console.error('     node server/src/database-tool.mjs import-json origen.json nuevo.sqlite');
  console.error('     node server/src/database-tool.mjs export-json origen.sqlite nuevo.json');
  process.exitCode = 2;
} else {
  let store;
  try {
    if (!existsSync(databasePath)) throw new Error('El archivo de origen no existe. No se creó una base vacía.');
    store = command === 'import-json'
      ? new SqliteStore(destination, { importJsonPath: databasePath, requireNew: true }) : openStore(databasePath);
    if (command === 'checkpoint') store.checkpoint();
    if (command === 'backup') {
      if (store instanceof SqliteStore && extname(destination).toLowerCase() === '.json') store.exportJsonTo(destination);
      else store.backupTo(destination);
    }
    if (command === 'export-json') {
      if (store instanceof SqliteStore) store.exportJsonTo(destination);
      else store.backupTo(destination);
    }
    const result = store.verify({ references: command === 'audit' });
    console.log(JSON.stringify({ operation: command, ...result }, null, 2));
    if (!result.ok) process.exitCode = 1;
  } catch (error) {
    console.error(`No se pudo completar ${command}: ${error.message}`);
    process.exitCode = 1;
  } finally { store?.close(); }
}
