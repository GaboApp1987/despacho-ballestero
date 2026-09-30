import 'dart:html' as html;
import 'dart:math';

/// ID anónimo compartido con el landing (misma clave "eq_vid" en
/// localStorage, ver el <script> de analítica en webapp/index.html). Si la
/// persona entró directo a /app/ sin pasar por el landing, se crea acá.
String leerVisitante() {
  try {
    var vid = html.window.localStorage['eq_vid'] ?? '';
    if (vid.isEmpty) {
      final r = Random.secure();
      vid = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      html.window.localStorage['eq_vid'] = vid;
    }
    return vid;
  } catch (_) {
    return '';
  }
}

/// De dónde llegó (lo guarda el landing: Google, Facebook, WhatsApp...).
String leerOrigen() {
  try {
    return html.window.localStorage['eq_origen'] ?? 'Directo';
  } catch (_) {
    return '';
  }
}

String dispositivoActual() => (html.window.innerWidth ?? 1024) <= 760 ? 'movil' : 'escritorio';
