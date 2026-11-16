import { normalizarRut } from './donors.mjs';

// Diagnóstico de datos históricos: informa inconsistencias sin corregir,
// eliminar ni completar datos clínicos por su cuenta.
export function auditDatabase(data) {
  const issues = [];
  const byModule = new Map();
  const users = new Set(data.users.map(user => user.id));
  for (const item of data.records) {
    if (!byModule.has(item.module)) byModule.set(item.module, new Map());
    byModule.get(item.module).set(item.id, item);
  }
  const report = (item, code, field, targetId) => {
    issues.push({ module: item.module, id: item.id, code, field, ...(targetId === undefined ? {} : { targetId }) });
  };
  const reference = (item, field, module, required = false) => {
    const id = item[field];
    if (id === undefined || id === null) {
      if (required) report(item, 'missing_reference', field);
      return;
    }
    const target = byModule.get(module)?.get(id);
    if (!target) report(item, 'missing_target', field, id);
    else if (target.scopeId !== item.scopeId) report(item, 'scope_mismatch', field, id);
    else return target;
  };
  for (const item of data.records) {
    if (typeof item.scopeId !== 'string' || !item.scopeId) report(item, 'missing_scope', 'scopeId');
    for (const field of ['responsableId', 'usuarioRegistroId', 'usuarioModificacionId']) {
      if (item[field] !== undefined && !users.has(item[field])) report(item, 'missing_user', field, item[field]);
    }
    if (['evaluations', 'donations', 'samples'].includes(item.module)) {
      const clinical = item.resultado !== undefined || item.fechaExtraccion !== undefined || item.codigo !== undefined;
      reference(item, 'donanteId', 'donors', clinical);
    }
    if (item.module === 'donations') {
      const evaluation = reference(item, 'evaluacionId', 'evaluations', item.fechaExtraccion !== undefined);
      if (evaluation && evaluation.donanteId !== item.donanteId) report(item, 'donor_mismatch', 'evaluacionId', evaluation.id);
    }
    if (['inventory', 'samples'].includes(item.module)) {
      const donation = reference(item, 'donacionId', 'donations', item.codigo !== undefined);
      if (item.module === 'samples' && donation && donation.donanteId !== item.donanteId) {
        report(item, 'donor_mismatch', 'donacionId', donation.id);
      }
    }
  }
  const unique = (module, field, normalize) => {
    const seen = new Set();
    for (const item of byModule.get(module)?.values() ?? []) {
      if (item[field] === undefined || item[field] === null) continue;
      const key = normalize(item[field], item);
      if (key === null) { report(item, 'invalid_key', field); continue; }
      if (seen.has(key)) report(item, 'duplicate_key', field);
      seen.add(key);
    }
  };
  unique('donors', 'rut', normalizarRut);
  for (const module of ['inventory', 'samples']) {
    unique(module, 'codigo', code => typeof code === 'string' && code.trim() ? code.trim().toUpperCase() : null);
  }
  unique('donations', 'claveConfirmacion', (key, item) => JSON.stringify([item.scopeId, key]));
  return { ok: issues.length === 0, issues };
}
