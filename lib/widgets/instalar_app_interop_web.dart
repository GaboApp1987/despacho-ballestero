import 'dart:js_interop';

/// Puente hacia el JS de web/index.html que escucha el evento
/// `beforeinstallprompt` del navegador (Chrome/Edge en Windows y Android).

@JS('equilibraPuedeInstalar')
external bool get _puedeInstalar;

@JS('equilibraPlataformaSugerida')
external JSString? get _plataformaSugeridaJs;

@JS('equilibraInstalarApp')
external void _instalarAppJs();

bool puedeInstalarApp() => _puedeInstalar;

String? plataformaSugeridaInstalacion() => _plataformaSugeridaJs?.toDart;

void instalarApp() => _instalarAppJs();
