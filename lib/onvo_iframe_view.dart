// Widget que embebe una URL en un iframe y recibe mensajes postMessage
// desde adentro (ver tarjeta.html + OnvoCobroAutomaticoScreen). Equilibra
// solo se despliega como Flutter Web hoy, así que la implementación real
// vive en onvo_iframe_view_web.dart; onvo_iframe_view_stub.dart es el
// respaldo para una futura compilación móvil/escritorio (donde esto
// requeriría un WebView nativo en vez de un iframe).
export 'onvo_iframe_view_stub.dart' if (dart.library.html) 'onvo_iframe_view_web.dart';
