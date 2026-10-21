# Equilibra — app (Flutter)

App de Equilibra: facturación electrónica (Hacienda de Costa Rica) y contabilidad. Se usa sobre todo como **app web** en `equilibracr.com/app`. El backend Django está en otro repo (`Gaboballestero/equilibra-backend`, carpeta local `DespachoBallesteroProject`); su `CLAUDE.md` explica el sistema completo, Hacienda y la IA.

El dueño habla español de Costa Rica y no es programador: explicá en español, sin jerga, y decí siempre qué falta para que algo llegue a producción.

## Deploy (automático)

- Cada push a `master` que toque `lib/`, `web/`, `assets/` o `pubspec` dispara `.github/workflows/build-web.yml`. Ese workflow hace el build web, lo verifica, lo copia a `webapp/app/` del backend y lo sube ahí. Después Railway lo publica cuando el dueño aprueba el deploy.
- **No hagas builds a mano** salvo que el workflow falle. Si hace falta, el comando es:
  `flutter build web --release --dart-define=API_BASE_URL=https://equilibracr.com/api --base-href=/app/`
  - Sin `--dart-define`, la app compila pero no hace login.
  - Sin `--base-href=/app/`, carga en blanco.
  - La URL es siempre `equilibracr.com`, nunca `*.up.railway.app`: esa da "Bad Request (400)".
  - En Git Bash, anteponé `MSYS_NO_PATHCONV=1`.
- Para ver el resultado: pestaña Actions del repo, o `gh run list`.

## Reglas de código

- **Nunca corras `dart format` sobre un archivo existente**: el código está formateado a mano y se generan cientos de líneas de cambios. Editá respetando el estilo que ya tiene y revisá `git diff --stat` antes de commitear.
- Las cantidades pueden tener decimales (2,5 kg): usá `formatearCantidad` / `leerCantidad` de `formato.dart`.
- Una sección nueva necesita su entrada en `moduloPorSeccion` (`lib/modulos.dart`) y la clave correspondiente en el backend.
- El chat de la IA (`lib/widgets/soporte_chat.dart`) solo ejecuta tarjetas cuya ruta esté en `_rutasPost`. Si la IA del backend propone una ruta nueva, agregala aquí también.
- `test/widget_test.dart` (la plantilla "Counter increments") falla desde siempre: ignorala.
