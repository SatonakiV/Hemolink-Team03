
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { openStore } from './store.mjs';
import { fechaValida, fechaLocal } from './dates.mjs';
import { GRUPOS_ABO, FACTORES_RH } from './blood-groups.mjs';
import { consultarStock } from './inventory.mjs';
import { DonanteError, normalizarRut, rutValido, validarDonante } from './donors.mjs';
import { DonacionError, validarDonacion, registrarDonacion, detalleDonacion, confirmacionPrevia} from './donations.mjs';
import { donacionDeSede, registrarMuestra } from './samples.mjs';
import {DescarteError, validarMotivo, buscarUnidadPorCodigo, descartarUnidad} from './discards.mjs';
import { SolicitudError, validarSolicitud, ordenarBandeja, crearSolicitud, obtenerFichaSolicitud } from './requests.mjs';
import { AtencionParcialError } from './partial-fulfillment.mjs';
import { atenderPedidoParcial } from './partial-fulfillment-integration.mjs';
import { confirmarDespacho } from './dispatches.mjs';
import {
  matchesPassword, passwordHash, tokenHash, newToken,
  publicUser, isAuthorizedUser, activeSession, roleModules, seedDemoData,
} from './auth.mjs';

const ID_VALIDO = /^[A-Za-z0-9_-]{1,64}$/;

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
  checkpointOnClose = false, importJsonPath,
  allowedOrigins = ['http://localhost:5173', 'http://127.0.0.1:5173'],
}) {
  const store = openStore(databasePath, { importJsonPath });
  if (seedDemo) seedDemoData(store, demoPassword);
  const dummyHash = passwordHash('unused-random-' + newToken());
  const attempts = new Map();

  function authenticate(request) {
    const token = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(
      request.headers.authorization ?? '',
    )?.[1];

    const hash = token ? tokenHash(token) : '';
    const db = store.read({ users: {}, sessions: { tokenHash: hash } });
    const autenticacion = activeSession(db, hash, clock());
    if (!autenticacion) {
      throw new ApiError(401, 'La sesión no es válida. Inicia sesión nuevamente.');
    }
    return autenticacion;
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
        response.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS');
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

        const user = store.read({ users: { email: body.email.trim().toLowerCase() } }).users.find(
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

      if (path === '/api/donors' || path.startsWith('/api/donors/')) {
        const { user } = authenticate(request);
        if (!roleModules[user.role]?.includes('donors')) {
          throw new ApiError(403, 'Tu perfil no puede gestionar donantes.');
        }

        if (path === '/api/donors' && request.method === 'POST') {
          const datos = validarDonante(await readBody(request), fechaLocal(clock));
          const item = {
            ...datos, id: randomUUID(), module: 'donors', scopeId: user.siteId,
            label: datos.nombre, usuarioRegistroId: user.id,
            fechaRegistro: new Date(clock()).toISOString(),
          };
          store.update(db => {
            if (db.records.some(record => record.module === 'donors' &&
                normalizarRut(record.rut) === datos.rut)) {
              throw new DonanteError(409, 'Ya existe un donante con ese RUT.', {
                rut: 'Ya existe un donante con ese RUT.',
              });
            }
            db.records.push(item);
          });
          send(201, { item });
          return;
        }

        if (request.method === 'GET') {
          let items = store.read({ records: {
            module: 'donors', scopeId: user.siteId,
            ...(path === '/api/donors' ? {} : { id: path.slice('/api/donors/'.length) }),
          } }).records.filter(record =>
            record.module === 'donors' && record.scopeId === user.siteId,
          );
          if (path !== '/api/donors') {
            const id = path.slice('/api/donors/'.length);
            const item = /^[A-Za-z0-9_-]{1,64}$/.test(id)
              ? items.find(record => record.id === id) : undefined;
            if (!item) throw new ApiError(404, 'Donante no encontrado.');
            send(200, { item });
            return;
          }
          const rut = url.searchParams.get('rut');
          const nombre = url.searchParams.get('nombre')?.trim().toLowerCase();
          if (rut !== null) {
            if (!rutValido(rut)) {
              throw new DonanteError(400, 'El RUT de búsqueda no es válido.', {
                rut: 'Ingresa un RUT válido para buscar.',
              });
            }
            items = items.filter(record => normalizarRut(record.rut) === normalizarRut(rut));
          }
          if (nombre) items = items.filter(record => record.nombre?.toLowerCase().includes(nombre));
          send(200, { items });
          return;
        }

        if (request.method === 'PUT' && path.startsWith('/api/donors/')) {
          const id = path.slice('/api/donors/'.length);
          if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
            throw new ApiError(404, 'Donante no encontrado.');
          }
          const datos = validarDonante(await readBody(request), fechaLocal(clock));
          let itemActualizado;
          store.update(db => {
            const index = db.records.findIndex(record =>
              record.module === 'donors' && record.scopeId === user.siteId && record.id === id,
            );
            if (index === -1) {
              throw new ApiError(404, 'Donante no encontrado.');
            }
            if (db.records.some(record =>
              record.module === 'donors' &&
              record.id !== id &&
              normalizarRut(record.rut) === datos.rut,
            )) {
              throw new DonanteError(409, 'Ya existe un donante con ese RUT.', {
                rut: 'Ya existe un donante con ese RUT.',
              });
            }
            const actual = db.records[index];
            itemActualizado = {
              ...actual,
              ...datos,
              id: actual.id,
              module: 'donors',
              scopeId: actual.scopeId,
              label: datos.nombre,
              usuarioRegistroId: actual.usuarioRegistroId,
              fechaRegistro: actual.fechaRegistro,
              usuarioModificacionId: user.id,
              fechaModificacion: new Date(clock()).toISOString(),
            };
            db.records[index] = itemActualizado;
          });
          send(200, { item: itemActualizado });
          return;
        }

        throw new ApiError(405, 'Operación no implementada.');
      }

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
          let items = store.read({ records: {
            module: 'evaluations', scopeId: scope,
            ...(path === '/api/evaluations' ? {} : { id: path.slice('/api/evaluations/'.length) }),
            ...(url.searchParams.has('donanteId') && path === '/api/evaluations'
              ? { donanteId: url.searchParams.get('donanteId') } : {}),
          } }).records.filter(item =>
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
          }

          items.reverse();

          send(200, { items });
          return;
        }

        throw new ApiError(405, 'Operación no implementada.');
      }

      if (path === '/api/samples' || path.startsWith('/api/samples/')) {
        const { user } = authenticate(request);
        if (user.role !== 'nursing') {
          throw new ApiError(403, 'Tu perfil no puede gestionar muestras.');
        }
        if (path === '/api/samples' && request.method === 'POST') {
          const datos = await readBody(request);
          let item;
          store.update(db => { item = registrarMuestra(db, datos, user, clock); });
          send(201, { item });
          return;
        }
        if (request.method === 'GET') {
          const donationFilter = url.searchParams.get('donacionId');
          const db = donationFilter !== null ? store.read() : store.read({ records: {
            module: 'samples', scopeId: user.siteId,
            ...(path === '/api/samples' ? {} : { id: path.slice('/api/samples/'.length) }),
          } });
          let items = db.records.filter(item => item.module === 'samples' && item.scopeId === user.siteId);
          if (path !== '/api/samples') {
            const item = items.find(item => item.id === path.slice('/api/samples/'.length));
            if (!item) throw new ApiError(404, 'Muestra no encontrada.');
            send(200, { item });
            return;
          }
          const donacionId = url.searchParams.get('donacionId');
          if (donacionId !== null) {
            donacionDeSede(db, donacionId, user.siteId);
            items = items.filter(item => item.donacionId === donacionId);
          }
          send(200, { items });
          return;
        }
        throw new ApiError(405, 'Operación no implementada.');
      }

      if (path === '/api/donations' || path.startsWith('/api/donations/')) {
        const { user } = authenticate(request);
        if (!roleModules[user.role]?.includes('donations')) {
          throw new ApiError(403, 'Tu perfil no puede gestionar donaciones.');
        }

        if (path === '/api/donations' && request.method === 'POST') {
          const datos = validarDonacion(await readBody(request), fechaLocal(clock));
          let item;
          let created = false;
          store.update(db => {
            const previa = confirmacionPrevia(db, user, datos);
            const id = previa?.id ?? randomUUID();
            if (!previa) {
              registrarDonacion(db, user, datos, {
                id, nuevoIdUnidad: randomUUID, ahora: new Date(clock()).toISOString(),
              });
              created = true;
            }
            item = detalleDonacion(db, user, id);
          });
          send(created ? 201 : 200, { item });
          return;
        }

        if (request.method === 'GET') {
          const db = path === '/api/donations'
            ? store.read({ records: { module: 'donations', scopeId: user.siteId } }) : store.read();
          if (path === '/api/donations') {
            const items = db.records.filter(r =>
              r.module === 'donations' && r.scopeId === user.siteId).reverse();
            send(200, { items });
            return;
          }
          const id = path.slice('/api/donations/'.length);
          const item = ID_VALIDO.test(id) ? detalleDonacion(db, user, id) : null;
          if (!item) throw new ApiError(404, 'Donación no encontrada.');
          send(200, { item });
          return;
        }
        throw new ApiError(405, 'Operación no implementada.');
      }

      // HU06 / T06.1: solicitudes y HU09 / T09.2: atención parcial.
      if (path === '/api/requests' || path.startsWith('/api/requests/')) {
        const { user, session } = authenticate(request);

        if (user.role !== 'hospital' && user.role !== 'inventory') {
          throw new ApiError(403, 'Tu perfil no puede gestionar solicitudes.');
        }

        const rutaAtencionParcial =
          /^\/api\/requests\/([A-Za-z0-9_-]{1,64})\/partial-fulfillment$/.exec(path);

        if (rutaAtencionParcial) {
          if (request.method !== 'POST') {
            throw new ApiError(405, 'Operación no implementada.');
          }

          if (user.role !== 'inventory') {
            throw new ApiError(
              403,
              'Solo inventario puede confirmar atenciones parciales.',
            );
          }

          const datos = await readBody(request);

          try {
            const resultado = await atenderPedidoParcial({
              store,
              user,
              pedidoId: rutaAtencionParcial[1],
              decision: datos.decision,
              unidadesPropuestas: datos.unidadesPropuestas,
              hoy: fechaLocal(clock),
              ahora: new Date(clock()).toISOString(),
            });

            send(200, resultado);
            return;
          } catch (error) {
            if (error instanceof AtencionParcialError) {
              throw new ApiError(
                error.code === 'STOCK_CONFLICT' ? 409 : 400,
                error.message,
              );
            }
            throw error;
          }
        }

        const rutaDespacho =
          /^\/api\/requests\/([A-Za-z0-9_-]{1,64})\/dispatches$/.exec(path);

        if (rutaDespacho) {
          if (request.method !== 'POST') {
            throw new ApiError(405, 'Operación no implementada.');
          }

          if (user.role !== 'inventory') {
            throw new ApiError(403, 'Solo inventario puede confirmar despachos.');
          }

          const datos = await readBody(request);
          const resultado = await confirmarDespacho({
            store, sessionTokenHash: session.tokenHash, clock,
            pedidoId: rutaDespacho[1], datos,
          });
          send(resultado.existente ? 200 : 201, resultado);
          return;
        }

        if (path === '/api/requests' && request.method === 'POST') {
          if (user.role !== 'hospital') {
            throw new ApiError(403, 'Solo el hospital puede ingresar solicitudes.');
          }
          const datos = validarSolicitud(await readBody(request));
          let item;
          store.update(db => {
            item = crearSolicitud(db, user, datos, {
              id: randomUUID(),
              ahora: new Date(clock()).toISOString(),
              fecha: fechaLocal(clock),
            });
          });
          send(201, { item });
          return;
        }

        if (request.method === 'GET') {
          if (path === '/api/requests') {
            const db = user.role === 'hospital'
              ? store.read({ records: { module: 'requests', scopeId: user.hospitalId } })
              : store.read({ records: { module: 'requests' } });

            let items = db.records.filter(r =>
              r.module === 'requests' &&
              (user.role === 'inventory' || r.scopeId === user.hospitalId)
            );
            items = ordenarBandeja(items);
            send(200, { items });
            return;
          }

          const id = path.slice('/api/requests/'.length);
          if (!ID_VALIDO.test(id)) {
            throw new ApiError(404, 'Solicitud no encontrada.');
          }
          const db = store.read();
          const item = obtenerFichaSolicitud(db, user, id, { hoy: fechaLocal(clock) });
          send(200, { item });
          return;
        }

        throw new ApiError(405, 'Operación no implementada.');
      }

      // HU07/T07.1: búsqueda por código y descarte, solo inventario de la sede.
      if (path.startsWith('/api/inventory/')) {
        const { user } = authenticate(request);
        if (!roleModules[user.role]?.includes('inventory')) {
          throw new ApiError(403, 'Tu perfil no puede gestionar el inventario.');
        }
        if (path === '/api/inventory/lookup' && request.method === 'GET') {
          // Lectura completa: la búsqueda también informa la reserva activa.
          const item = buscarUnidadPorCodigo(
            store.read(),
            user,
            url.searchParams.get('codigo'),
          );
          send(200, { item });
          return;
        }
        const rutaDescarte = /^\/api\/inventory\/([A-Za-z0-9_-]{1,64})\/discard$/.exec(path);
        if (rutaDescarte && request.method === 'POST') {
          const motivo = validarMotivo(await readBody(request));
          let resultado;
          // Unidad, reserva y pedido cambian juntos o no cambia nada.
          store.update(db => {
            resultado = descartarUnidad(db, user, rutaDescarte[1], motivo, {
              hoy: fechaLocal(clock),
              ahora: new Date(clock()).toISOString(),
            });
          });
          send(200, resultado);
          return;
        }
        throw new ApiError(rutaDescarte ? 405 : 404,
          rutaDescarte ? 'Operación no implementada.' : 'Recurso no encontrado.');
      }
      if (path === '/api/dispatches' || path.startsWith('/api/dispatches/')) {
        const { user, session } = authenticate(request);
        if (user.role !== 'inventory') {
          throw new ApiError(403, 'Solo inventario puede gestionar despachos.');
        }

        if (path === '/api/dispatches' && request.method === 'POST') {
          const datos = await readBody(request);
          const resultado = await confirmarDespacho({
            store, sessionTokenHash: session.tokenHash, clock, datos,
          });
          send(resultado.existente ? 200 : 201, resultado);
          return;
        }

        if (request.method === 'GET') {
          const db = store.read({ records: { module: 'dispatches', scopeId: user.siteId } });
          if (path === '/api/dispatches') {
            const items = db.records.filter(r => r.module === 'dispatches' && r.scopeId === user.siteId).reverse();
            send(200, { items });
            return;
          }
          const id = path.slice('/api/dispatches/'.length);
          const item = ID_VALIDO.test(id)
            ? db.records.find(r => r.module === 'dispatches' && r.scopeId === user.siteId && r.id === id)
            : null;
          if (!item) throw new ApiError(404, 'Despacho no encontrado.');
          send(200, { item });
          return;
        }

        throw new ApiError(405, 'Operación no implementada.');
      }

      const module = path.startsWith('/api/') ? path.slice(5) : '';

      if (Object.values(roleModules).flat().includes(module)) {
        const { user } = authenticate(request);

        if (!roleModules[user.role].includes(module)) {
          throw new ApiError(403, 'Tu perfil no puede acceder a esta sección.');
        }

        if (request.method !== 'GET') {
          throw new ApiError(405, 'Operación no implementada.');
        }

        if (module === 'inventory') {
          const sedeId = url.searchParams.get('sedeId') ?? undefined;
          const grupoAbo = url.searchParams.get('grupoAbo')?.trim().toUpperCase();
          const factorRh = url.searchParams.get('factorRh')?.trim().toLowerCase();
          if (sedeId !== undefined && !sedeId.trim()) {
            throw new ApiError(400, 'La sede no es válida.');
          }
          if (grupoAbo !== undefined && !GRUPOS_ABO.includes(grupoAbo)) {
            throw new ApiError(400, 'El grupo ABO no es válido.');
          }
          if (factorRh !== undefined && !FACTORES_RH.includes(factorRh)) {
            throw new ApiError(400, 'El factor Rh no es válido.');
          }
          send(200, consultarStock(store, { sedeId, grupoAbo, factorRh, hoy: fechaLocal(clock) }));
          return;
        }

        const scope = user.role === 'hospital'
          ? user.hospitalId
          : user.siteId;

        const items = store.read({ records: { module, scopeId: scope } }).records.filter(item =>
          item.module === module &&
          item.scopeId === scope,
        );

        send(200, { items });
        return;
      }

      throw new ApiError(404, 'Recurso no encontrado.');
    } catch (error) {
      send(error.status ?? 500, {
        message: error.status
          ? error.message
          : 'No se pudo completar la operación.',
        ...(error instanceof DonanteError || error instanceof DonacionError || error instanceof SolicitudError
          || error instanceof DescarteError ? { errors: error.errors } : {}),
      });
    }
  });

  server.once('close', () => {
    try { store.close({ checkpoint: checkpointOnClose }); }
    catch { console.error('No se pudo compactar la base JSON; conserve la instantánea y su diario.'); }
  });
  return { server, store };
}
