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

## Ejecutar con base JSON local

En una terminal, desde la carpeta del repositorio:

```powershell
node server/src/server.mjs --seed-demo
```

El primer inicio crea `server/data/hemolink.json` con cuentas y registros
ficticios. Los siguientes inicios conservan los datos; `--seed-demo` solo agrega
semillas que falten. El archivo contiene contraseñas con hash y sesiones con
vencimiento, y está excluido de Git. Para iniciar sin agregar semillas, omite
`--seed-demo`. La API escucha solamente en `127.0.0.1:8080`.

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

- `HEMOLINK_DATABASE`: ruta alternativa del archivo JSON del servidor.
- `PORT`: puerto de la API; por defecto `8080`.
- `HEMOLINK_ALLOWED_ORIGINS`: orígenes web separados por coma; por defecto
  `http://localhost:5173,http://127.0.0.1:5173`.
- Para otra dirección de API, ejecuta Flutter con
  `--dart-define=API_BASE_URL=http://127.0.0.1:8080`.

Usa una sola instancia del servidor por archivo JSON. Las escrituras se realizan
mediante un archivo temporal y reemplazo atómico. Para respaldar o editar el JSON,
detén la API primero. No publiques `server/data/` dentro de los archivos web.

### Comprobaciones

```powershell
node --test server/test/*.test.mjs
.\tool\flutter.cmd test
.\tool\flutter.cmd analyze
.\tool\flutter.cmd build web
```
