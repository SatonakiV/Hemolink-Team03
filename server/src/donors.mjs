import { fechaValida } from './dates.mjs';

export class DonanteError extends Error {
  constructor(status, message, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

// Reutilizable en la corrección de antecedentes de HU04.
export function normalizarRut(valor) {
  if (typeof valor !== 'string') return null;
  const partes = /^([0-9]{1,8})-?([0-9K])$/.exec(valor.replace(/[.\s]/g, '').toUpperCase());
  if (!partes || Number(partes[1]) === 0) return null;
  return `${Number(partes[1])}-${partes[2]}`;
}

export function rutValido(valor) {
  const rut = normalizarRut(valor);
  if (!rut) return false;
  const [cuerpo, dv] = rut.split('-');
  let suma = 0;
  let factor = 2;
  for (let i = cuerpo.length - 1; i >= 0; i--) {
    suma += Number(cuerpo[i]) * factor;
    factor = factor === 7 ? 2 : factor + 1;
  }
  const resultado = 11 - suma % 11;
  return dv === (resultado === 11 ? '0' : resultado === 10 ? 'K' : String(resultado));
}

export function validarDonante(datos, hoy) {
  const errors = {};
  const texto = campo => typeof datos[campo] === 'string' ? datos[campo].trim() : '';
  const nombre = texto('nombre');
  const telefono = texto('telefono');
  const grupoAbo = texto('grupoAbo').toUpperCase();
  const factorRh = texto('factorRh').toLowerCase();
  if (!rutValido(datos.rut)) errors.rut = 'Ingresa un RUT con formato y dígito verificador válidos.';
  if (!nombre) errors.nombre = 'El nombre es obligatorio.';
  if (!fechaValida(datos.fechaNacimiento) || datos.fechaNacimiento > hoy) {
    errors.fechaNacimiento = 'Ingresa una fecha de nacimiento válida y no futura.';
  }
  if (typeof datos.pesoKg !== 'number' || !Number.isFinite(datos.pesoKg) || datos.pesoKg <= 0) {
    errors.pesoKg = 'El peso debe ser un número positivo en kilogramos.';
  }
  if (!['A', 'B', 'AB', 'O'].includes(grupoAbo)) errors.grupoAbo = 'Selecciona un grupo sanguíneo A, B, AB u O.';
  if (!['positivo', 'negativo'].includes(factorRh)) errors.factorRh = 'Selecciona un factor Rh positivo o negativo.';
  if (!telefono) errors.telefono = 'El teléfono es obligatorio.';
  if (Object.keys(errors).length) throw new DonanteError(400, 'Revisa los datos del donante.', errors);
  // Lista explícita: nunca persistir cuestionarios ni metadatos enviados por el cliente.
  return {
    rut: normalizarRut(datos.rut), nombre, fechaNacimiento: datos.fechaNacimiento,
    pesoKg: datos.pesoKg, grupoAbo, factorRh, telefono,
  };
}
