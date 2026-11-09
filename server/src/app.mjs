import { createServer } from 'node:http';
import { JsonStore } from './json-store.mjs';
import {
  matchesPassword, passwordHash, tokenHash, newToken,
  publicUser, isAuthorizedUser, roleModules, seedDemoData,
} from './auth.mjs';

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function readBody(request) {
  if (!request.headers['content-type']?.startsWith('application/json')) {
    throw new ApiError(415, 'Se requiere contenido JSON.');
  }
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body) > 8192) {
      throw new ApiError(413, 'Solicitud demasiado grande.');
    }
  }
  try {
    const data = JSON.parse(body);
    if (!data || Array.isArray(data) || typeof data !== 'object') {
      throw new Error('Cuerpo incorrecto');
    }
    return data;
  } catch {
    throw new ApiError(400, 'Solicitud JSON inválida.');
  }
}

// Para los datos clínicos del prototipo usamos fechas civiles YYYY-MM-DD.
// Date.parse por sí solo acepta fechas imposibles, como 2026-02-30.
function fechaValida(valor) {
  if (typeof valor !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(valor)) {
    return false;
  }
  const [anio, mes, dia] = valor.split('-').map(Number);
  const fecha = new Date(Date.UTC(anio, mes - 1, dia));
  return fecha.getUTCFullYear() === anio &&
    fecha.getUTCMonth() === mes - 1 &&
    fecha.getUTCDate() === dia;
}

function fechaLocal(clock) {
  const fecha = new Date(clock());
  const anio = String(fecha.getFullYear()).padStart(4, '0');
  const mes = String(fecha.getMonth() + 1).padStart(2, '0');
  const dia = String(fecha.getDate()).padStart(2, '0');
  return `${anio}-${mes}-${dia}`;
}

function validarEvaluacion(datos, clock) {
  if (typeof datos.id !== 'string' ||
      !/^[A-Za-z0-9_-]{1,64}$/.test(datos.id)) {
    throw new ApiError(400, 'El identificador de evaluación no es válido.');
  }
  if (typeof datos.donanteId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,64}$/.test(datos.donanteId)) {
    throw new ApiError(400, 'El identificador del donante no es válido.');
  }
  if (!['apto', 'diferido', 'rechazado'].includes(datos.resultado)) {
    throw new ApiError(400, 'Resultado de aptitud no válido.');
  }
  if (!fechaValida(datos.fechaEvaluacion) ||
      datos.fechaEvaluacion > fechaLocal(clock)) {
    throw new ApiError(400, 'La fecha de evaluación no es válida.');
  }

  const fin = datos.fechaFinVigencia ?? null;
  const habilitacion = datos.fechaHabilitacion ?? null;

  if (datos.resultado === 'apto') {
    if (!fechaValida(fin) || fin < datos.fechaEvaluacion || habilitacion !== null) {
      throw new ApiError(400, 'La evaluación apta requiere una vigencia válida.');
    }
  } else if (datos.resultado === 'diferido') {
    if (!fechaValida(habilitacion) || habilitacion < datos.fechaEvaluacion || fin !== null) {
      throw new ApiError(400, 'La evaluación diferida requiere fecha de habilitación válida.');
    }
  } else if (fin !== null || habilitacion !== null) {
    throw new ApiError(400, 'La evaluación rechazada no admite fechas de vigencia o habilitación.');
  }

  return {
    id: datos.id,
    donanteId: datos.donanteId,
    resultado: datos.resultado,
    fechaEvaluacion: datos.fechaEvaluacion,
    fechaFinVigencia: fin,
    fechaHabilitacion: habilitacion,
  };
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
    const token = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(
      request.headers.authorization ?? '',
    )?.[1];

    const db = store.read();
    const session = token && db.sessions.find(
      item => item.tokenHash === tokenHash(token),
    );
    const user = session && db.users.find(item => item.id === session.userId);

    if (!session || session.expiresAt <= clock() || !isAuthorizedUser(user)) {
      throw new ApiError(401, 'La sesión no es válida. Inicia sesión nuevamente.');
    }
    return { user, session };
  }

  const server = createServer(async (request, response) => {
    const send = (status, data) => {
      response.writeHead(status, {
        'Content-Type': 'application/json; charset=utf-8',
      });
      response.end(JSON.stringify(data));
    };

    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Vary', 'Origin');

    try {
      const origin = request.headers.origin;
      if (origin && !allowedOrigins.includes(origin)) {
        throw new ApiError(403, 'Origen no permitido.');
      }
      if (origin) response.setHeader('Access-Control-Allow-Origin', origin);

      if (request.method === 'OPTIONS') {
        response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        response.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
        response.writeHead(204);
        response.end();
        return;
      }

      const url = new URL(request.url, 'http://localhost');
      const path = url.pathname;

      if (path === '/api/login' && request.method === 'POST') {
        const key = request.socket.remoteAddress;
        for (const [ip, entry] of attempts) {
          if (entry.until <= clock()) attempts.delete(ip);
        }

        const attempt = attempts.get(key) ?? {
          count: 0,
          until: clock() + 15 * 60 * 1000,
        };

        if (attempt.count >= maxLoginAttempts) {
          throw new ApiError(429, 'Demasiados intentos. Vuelve a intentar en 15 minutos.');
        }

        const body = await readBody(request);

        if (typeof body.email !== 'string' || typeof body.password !== 'string' ||
            body.email.length > 254 || body.password.length > 256 ||
            !body.email.trim() || !body.password) {
          throw new ApiError(400, 'Ingresa correo y contraseña válidos.');
        }

        const user = store.read().users.find(
          item => item.email === body.email.trim().toLowerCase(),
        );

        const valid = matchesPassword(body.password, user?.passwordHash ?? dummyHash);

        if (!valid || !isAuthorizedUser(user)) {
          attempt.count++;
          attempts.set(key, attempt);
          throw new ApiError(401, 'Credenciales inválidas o cuenta no verificada.');
        }

        const token = newToken();
        const expiresAt = clock() + 8 * 60 * 60 * 1000;

        store.update(db => {
          db.sessions = db.sessions.filter(item => item.expiresAt > clock());
          db.sessions.push({
            tokenHash: tokenHash(token),
            userId: user.id,
            expiresAt,
          });
        });

        attempts.delete(key);
        send(200, { token, expiresAt, user: publicUser(user) });
        return;
      }

      if (path === '/api/me' && request.method === 'GET') {
        send(200, { user: publicUser(authenticate(request).user) });
        return;
      }

      if (path === '/api/logout' && request.method === 'POST') {
        const { session } = authenticate(request);

        store.update(db => {
          db.sessions = db.sessions.filter(
            item => item.tokenHash !== session.tokenHash,
          );
        });

        send(200, { message: 'Sesión cerrada.' });
        return;
      }

      // T02.1: lectura y escritura de evaluaciones, solo para enfermería.
      if (path === '/api/evaluations' || path.startsWith('/api/evaluations/')) {
        const { user } = authenticate(request);

        if (!roleModules[user.role]?.includes('evaluations')) {
          throw new ApiError(403, 'Tu perfil no puede gestionar evaluaciones.');
        }

        const scope = user.siteId;

        if (path === '/api/evaluations' && request.method === 'POST') {
          const datos = validarEvaluacion(await readBody(request), clock);

          const nuevaEvaluacion = {
            ...datos,
            module: 'evaluations',
            scopeId: scope,
            responsableId: user.id,
            fechaRegistro: new Date(clock()).toISOString(),
          };

          store.update(db => {
            const donanteExiste = db.records.some(item =>
              item.module === 'donors' &&
              item.scopeId === scope &&
              item.id === datos.donanteId,
            );

            if (!donanteExiste) {
              throw new ApiError(404, 'El donante no existe en esta sede.');
            }

            if (db.records.some(item =>
              item.module === 'evaluations' && item.id === datos.id,
            )) {
              throw new ApiError(409, 'Ya existe una evaluación con ese identificador.');
            }

            db.records.push(nuevaEvaluacion);
          });

          send(201, { item: nuevaEvaluacion });
          return;
        }

        if (request.method === 'GET') {
          let items = store.read().records.filter(item =>
            item.module === 'evaluations' &&
            item.scopeId === scope,
          );

          if (path !== '/api/evaluations') {
            const id = path.slice('/api/evaluations/'.length);

            if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
              throw new ApiError(404, 'Evaluación no encontrada.');
            }

            const item = items.find(item => item.id === id);

            if (!item) {
              throw new ApiError(404, 'Evaluación no encontrada.');
            }

            send(200, { item });
            return;
          }

          const donanteId = url.searchParams.get('donanteId');

          if (donanteId !== null) {
            if (!/^[A-Za-z0-9_-]{1,64}$/.test(donanteId)) {
              throw new ApiError(400, 'Identificador del donante no válido.');
            }

            items = items.filter(item => item.donanteId === donanteId);

            items.sort((a, b) =>
              String(b.fechaEvaluacion ?? '').localeCompare(
                String(a.fechaEvaluacion ?? ''),
              ) ||
              String(b.fechaRegistro ?? '').localeCompare(
                String(a.fechaRegistro ?? ''),
              ),
            );
          }

          send(200, { items });
          return;
        }

        throw new ApiError(405, 'Operación no implementada.');
      }

      // Se conservan los módulos de consulta existentes.
      const module = path.startsWith('/api/') ? path.slice(5) : '';

      if (Object.values(roleModules).flat().includes(module)) {
        const { user } = authenticate(request);

        if (!roleModules[user.role].includes(module)) {
          throw new ApiError(403, 'Tu perfil no puede acceder a esta sección.');
        }

        if (request.method !== 'GET') {
          throw new ApiError(405, 'Operación no implementada.');
        }

        const scope = user.role === 'hospital'
          ? user.hospitalId
          : user.siteId;

        const items = store.read().records.filter(item =>
          item.module === module &&
          item.scopeId === scope,
        );

        send(200, { items });
        return;
      }

      throw new ApiError(404, 'Recurso no encontrado.');
    } catch (error) {
      // Nunca exponer rutas locales, contraseñas ni detalles internos.
      send(error.status ?? 500, {
        message: error.status
          ? error.message
          : 'No se pudo completar la operación.',
      });
    }
  });

  return { server, store };
}
