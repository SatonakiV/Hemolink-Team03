import { createServer } from 'node:http';
import { JsonStore } from './json-store.mjs';
import { matchesPassword, passwordHash, tokenHash, newToken, publicUser, isAuthorizedUser, roleModules, seedDemoData } from './auth.mjs';

class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function readBody(request) {
  if (!request.headers['content-type']?.startsWith('application/json')) {
    throw new ApiError(415, 'Se requiere contenido JSON.');
  }
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body) > 8192) throw new ApiError(413, 'Solicitud demasiado grande.');
  }
  try {
    const data = JSON.parse(body);
    if (!data || Array.isArray(data) || typeof data !== 'object') throw new Error();
    return data;
  } catch { throw new ApiError(400, 'Solicitud JSON inválida.'); }
}

export function createApplication({
  databasePath, seedDemo = false, demoPassword = 'DemoHemoLink2026!',
  clock = Date.now, maxLoginAttempts = 10,
  allowedOrigins = ['http://localhost:5173', 'http://127.0.0.1:5173'],
}) {
  const store = new JsonStore(databasePath);
  if (seedDemo) seedDemoData(store, demoPassword);
  const dummyHash = passwordHash('unused-random-' + newToken());
  const attempts = new Map();

  function authenticate(request) {
    const token = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(request.headers.authorization ?? '')?.[1];
    const db = store.read();
    const session = token && db.sessions.find(session => session.tokenHash === tokenHash(token));
    const user = session && db.users.find(user => user.id === session.userId);
    if (!session || session.expiresAt <= clock() || !isAuthorizedUser(user)) {
      throw new ApiError(401, 'La sesión no es válida. Inicia sesión nuevamente.');
    }
    return { user, session };
  }

  const server = createServer(async (request, response) => {
    const send = (status, data) => {
      response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
      response.end(JSON.stringify(data));
    };
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Vary', 'Origin');
    try {
      const origin = request.headers.origin;
      if (origin && !allowedOrigins.includes(origin)) throw new ApiError(403, 'Origen no permitido.');
      if (origin) response.setHeader('Access-Control-Allow-Origin', origin);
      if (request.method === 'OPTIONS') {
        response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        response.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
        response.writeHead(204); response.end(); return;
      }
      const path = new URL(request.url, 'http://localhost').pathname;
      if (path === '/api/login' && request.method === 'POST') {
        const key = request.socket.remoteAddress;
        for (const [ip, entry] of attempts) if (entry.until <= clock()) attempts.delete(ip);
        const attempt = attempts.get(key) ?? { count: 0, until: clock() + 15 * 60 * 1000 };
        if (attempt.count >= maxLoginAttempts) throw new ApiError(429, 'Demasiados intentos. Vuelve a intentar en 15 minutos.');
        const body = await readBody(request);
        if (typeof body.email !== 'string' || typeof body.password !== 'string' ||
            body.email.length > 254 || body.password.length > 256 || !body.email.trim() || !body.password) {
          throw new ApiError(400, 'Ingresa correo y contraseña válidos.');
        }
        const user = store.read().users.find(user => user.email === body.email.trim().toLowerCase());
        const valid = matchesPassword(body.password, user?.passwordHash ?? dummyHash);
        if (!valid || !isAuthorizedUser(user)) {
          attempt.count++; attempts.set(key, attempt);
          throw new ApiError(401, 'Credenciales inválidas o cuenta no verificada.');
        }
        const token = newToken();
        const expiresAt = clock() + 8 * 60 * 60 * 1000;
        store.update(db => {
          db.sessions = db.sessions.filter(session => session.expiresAt > clock());
          db.sessions.push({ tokenHash: tokenHash(token), userId: user.id, expiresAt });
        });
        attempts.delete(key);
        send(200, { token, expiresAt, user: publicUser(user) }); return;
      }
      if (path === '/api/me' && request.method === 'GET') {
        send(200, { user: publicUser(authenticate(request).user) }); return;
      }
      if (path === '/api/logout' && request.method === 'POST') {
        const { session } = authenticate(request);
        store.update(db => { db.sessions = db.sessions.filter(item => item.tokenHash !== session.tokenHash); });
        send(200, { message: 'Sesión cerrada.' }); return;
      }
      const module = path.startsWith('/api/') ? path.slice(5) : '';
      if (Object.values(roleModules).flat().includes(module)) {
        const { user } = authenticate(request);
        if (!roleModules[user.role].includes(module)) throw new ApiError(403, 'Tu perfil no puede acceder a esta sección.');
        if (request.method !== 'GET') throw new ApiError(405, 'Operación no implementada.');
        const scope = user.role === 'hospital' ? user.hospitalId : user.siteId;
        const items = store.read().records.filter(record => record.module === module && record.scopeId === scope);
        send(200, { items }); return;
      }
      throw new ApiError(404, 'Recurso no encontrado.');
    } catch (error) {
      // Nunca devolver rutas locales, contraseñas ni detalles del sistema de archivos.
      send(error.status ?? 500, { message: error.status ? error.message : 'No se pudo completar la operación.' });
    }
  });
  return { server, store };
}
