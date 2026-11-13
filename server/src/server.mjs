import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { createApplication } from './app.mjs';

const port = Number(process.env.PORT ?? 8080);
const databasePath = process.env.HEMOLINK_DATABASE ?? fileURLToPath(new URL('../data/hemolink.sqlite', import.meta.url));
const legacyJson = fileURLToPath(new URL('../data/hemolink.json', import.meta.url));
const { server } = createApplication({
  databasePath,
  importJsonPath: process.env.HEMOLINK_IMPORT_JSON ??
    (!process.env.HEMOLINK_DATABASE && existsSync(legacyJson) ? legacyJson : undefined),
  seedDemo: process.argv.includes('--seed-demo'),
  demoPassword: process.env.HEMOLINK_DEMO_PASSWORD,
  checkpointOnClose: true,
  allowedOrigins: process.env.HEMOLINK_ALLOWED_ORIGINS?.split(',').map(origin => origin.trim()),
});
server.listen(port, '127.0.0.1', () => console.log(`HemoLink API local: http://127.0.0.1:${server.address().port}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
