import { realpathSync } from 'node:fs';
import { withFileLock } from './file-lock.mjs';
import { loadSnapshot, replayJournal } from './json-journal.mjs';

// Lectura consistente del JSON original y su diario, sin crearlos, truncarlos
// ni compactarlos. El bloqueo solo dura lo necesario para capturar la copia.
export function readJsonDatabase(path) {
  let source = realpathSync(path);
  if (process.platform === 'win32') source = source.toLowerCase();
  return withFileLock(source, 1000, () => {
    const snapshot = loadSnapshot(source);
    return replayJournal(`${source}.wal`, snapshot, 0, { repairTail: false }).data;
  });
}
