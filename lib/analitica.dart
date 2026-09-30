import 'api_service.dart';
import 'analitica_almacen_stub.dart' if (dart.library.html) 'analitica_almacen_web.dart';

/// Analítica propia del embudo de registro (backend: EventoAnalitica /
/// AnaliticaEventoView). En la web usa el MISMO ID anónimo que guarda el
/// landing en localStorage ("eq_vid") -- los dos viven en equilibracr.com
/// -- así el panel sabe si quien visitó el landing terminó registrándose.
/// En la app instalada (Android/Windows) no hay ese ID y los eventos salen
/// sin visitante. Nunca interrumpe nada: si falla, se pierde el dato.
class Analitica {
  static String get visitante => leerVisitante();
  static String get origen => leerOrigen();

  static Future<void> evento(String tipo, {String detalle = ''}) async {
    try {
      await ApiService.post('/analitica/evento/', {
        'tipo': tipo,
        'visitante': visitante,
        'detalle': detalle,
        'origen': origen,
        'dispositivo': dispositivoActual(),
      });
    } catch (_) {
      // Sin conexión o bloqueado: no es un error para el usuario.
    }
  }
}
