import { randomBytes, scryptSync, timingSafeEqual, createHash } from 'node:crypto';

export const roleModules = Object.freeze({
  nursing: ['donors', 'evaluations'],
  inventory: ['inventory'],
  hospital: ['requests'],
});

export function passwordHash(password, salt = randomBytes(16).toString('hex')) {
  return `${salt}:${scryptSync(password, salt, 64).toString('hex')}`;
}

export function matchesPassword(password, encoded) {
  const [salt, hash] = encoded.split(':');
  const candidate = scryptSync(password, salt, 64);
  const expected = Buffer.from(hash, 'hex');
  return candidate.length === expected.length && timingSafeEqual(candidate, expected);
}

export const tokenHash = token => createHash('sha256').update(token).digest('hex');
export const newToken = () => randomBytes(32).toString('base64url');

export function publicUser(user) {
  return {
    id: user.id, role: user.role, isVerified: user.isVerified,
    siteId: user.siteId, hospitalId: user.hospitalId,
    modules: roleModules[user.role] ?? [],
  };
}

export function isAuthorizedUser(user) {
  if (!user?.isVerified || !Object.hasOwn(roleModules, user.role)) return false;
  return user.role === 'hospital'
    ? typeof user.hospitalId === 'string' && user.hospitalId.length > 0 && user.siteId === null
    : typeof user.siteId === 'string' && user.siteId.length > 0 && user.hospitalId === null;
}

export function seedDemoData(store, password) {
  const accounts = [
    ['nursing-demo', 'enfermeria@hemolink.test', 'nursing', true],
    ['inventory-demo', 'inventario@hemolink.test', 'inventory', true],
    ['hospital-demo', 'hospital@hemolink.test', 'hospital', true],
    ['unverified-demo', 'sin.verificar@hemolink.test', 'nursing', false],
  ];
  store.update(db => {
    for (const [id, email, role, isVerified] of accounts) {
      if (db.users.some(user => user.id === id || user.email === email)) continue;
      db.users.push({
        id, email, role, isVerified, passwordHash: passwordHash(password),
        siteId: role === 'hospital' ? null : 'sede-central',
        hospitalId: role === 'hospital' ? 'hospital-demo' : null,
      });
    }
    for (const [module, label] of [
      ['donors', 'Donante ficticio de prueba'],
      ['evaluations', 'Evaluación ficticia de prueba'],
      ['inventory', 'Unidad ficticia de prueba'],
      ['requests', 'Solicitud ficticia de prueba'],
    ]) {
      const id = `demo-${module}`;
      if (!db.records.some(record => record.id === id)) {
        db.records.push({ id, module, label, scopeId: module === 'requests' ? 'hospital-demo' : 'sede-central' });
      }
    }
  });
}
