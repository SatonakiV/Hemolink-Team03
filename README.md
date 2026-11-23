# HemoLink - Team 03

Proyecto banco de sangre 

## Requisitos

- Flutter 3.47.2 (incluye Dart 3.13.2).
- Node.js 22 o superior para la API local (sin paquetes npm ni base externa).
- Edge para web. Para Windows, herramientas de C++ de Visual Studio con la
  biblioteca ATL de C++ para x86 y x64 de la misma versión del compilador.

## Instalar dependencias

Desde la carpeta del repositorio:

```sh
flutter pub get
```

## Ejecutar con SQLite e importación desde JSON

En una terminal, desde la carpeta del repositorio:

```powershell
node server/src/server.mjs --seed-demo
```

Por defecto, la API utiliza SQLite en `server/data/hemolink.sqlite` con transacciones
atómicas y modo WAL. El primer inicio crea la base con cuentas y registros
ficticios si se incluye `--seed-demo`. Los siguientes inicios conservan los datos;
`--seed-demo` solo agrega semillas que falten. La API escucha en `127.0.0.1:8080`.

### Importación de datos desde JSON

- **Automática:** Si existe `server/data/hemolink.json` heredado y no se especifica
  `HEMOLINK_DATABASE`, el servidor lo importa automáticamente a SQLite en el primer
  arranque sin modificar el archivo JSON original.
- **Variable de entorno:** Puedes definir `HEMOLINK_IMPORT_JSON=ruta/al/origen.json`
  para inicializar una nueva base SQLite a partir de un JSON existente.
- **Herramienta CLI:** Para importar manualmente antes de iniciar el servidor:

```powershell
node server/src/database-tool.mjs import-json server/data/hemolink.json server/data/hemolink.sqlite
```

También puedes auditar la integridad referencial y restricciones únicas de la base:

```powershell
node server/src/database-tool.mjs audit server/data/hemolink.sqlite
```

En otra terminal, instala las dependencias y ejecuta Flutter.

Web:

```sh
.\tool\flutter.cmd run -d edge --web-port 5173
```

Windows:

```powershell
.\tool\flutter.cmd run -d windows
```

### Cuentas ficticias

| Correo | Perfil | Asociación |
| --- | --- | --- |
| `enfermeria@hemolink.test` | Enfermería | `sede-central` |
| `inventario@hemolink.test` | Inventario | `sede-central` |
| `hospital@hemolink.test` | Hospital | `hospital-demo` |
| `sin.verificar@hemolink.test` | Sin verificar: acceso rechazado | `sede-central` |

Contraseña de las semillas: `DemoHemoLink2026!`. Puedes definir
`HEMOLINK_DEMO_PASSWORD` antes de crearlas; no cambia contraseñas ya guardadas.

La sesión se recupera al recargar consultando `/api/me`. Al salir se invalida
en el servidor. Cada sesión vence a las 8 horas. El cliente conserva únicamente
el token mediante `flutter_secure_storage`; el perfil lo obtiene del servidor.

### Configuración y alcance

- `HEMOLINK_DATABASE`: ruta alternativa de la base de datos SQLite (o JSON) del servidor.
- `HEMOLINK_IMPORT_JSON`: ruta opcional de archivo JSON para importar a SQLite en el arranque inicial.
- `PORT`: puerto de la API; por defecto `8080`.
- `HEMOLINK_ALLOWED_ORIGINS`: orígenes web separados por coma; por defecto
  `http://localhost:5173,http://127.0.0.1:5173`.
- Para otra dirección de API, ejecuta Flutter con
  `--dart-define=API_BASE_URL=http://127.0.0.1:8080`.

Las escrituras en SQLite se ejecutan bajo transacciones atómicas con modo WAL. No publiques
`server/data/` dentro de los archivos web.

### Comprobaciones

```powershell
node --test server/test/*.test.mjs
.\tool\flutter.cmd test
.\tool\flutter.cmd analyze
.\tool\flutter.cmd build web
```
