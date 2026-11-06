import { fileURLToPath } from 'node:url';
import { createApplication } from './app.mjs';

const port = Number(process.env.PORT ?? 8080);
const { server } = createApplication({
  databasePath: process.env.HEMOLINK_DATABASE ?? fileURLToPath(new URL('../data/hemolink.json', import.meta.url)),
  seedDemo: process.argv.includes('--seed-demo'),
  demoPassword: process.env.HEMOLINK_DEMO_PASSWORD,
  allowedOrigins: process.env.HEMOLINK_ALLOWED_ORIGINS?.split(',').map(origin => origin.trim()),
});
server.listen(port, '127.0.0.1', () => console.log(`HemoLink API local: http://127.0.0.1:${port}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
