import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme/app_theme.dart';

/// Recorridos guiados: la pantalla se oscurece, se ilumina el botón real y
/// un globo explica qué hacer (Atrás / Siguiente / Saltar). Los recorridos
/// están definidos en lib/recorridos.dart; qué vio cada usuario lo guarda
/// el backend (gestion/recorridos.py) para no ofrecérselos otra vez en
/// ningún dispositivo.

class PasoRecorrido {
  /// El elemento que se ilumina (un GlobalKey puesto en el widget). Null =
  /// paso sin destacar nada (bienvenida o cierre), centrado. Si el elemento
  /// no está en pantalla en ese momento (ej. una opción que solo aparece en
  /// contado), el paso se salta solo.
  final GlobalKey? objetivo;
  final String titulo;
  final String texto;
  const PasoRecorrido({this.objetivo, required this.titulo, required this.texto});
}

/// Lo que cada usuario ya vio (se pide una vez por sesión).
class Recorridos {
  static Set<String>? _vistos;
  // Ofrecidos en esta sesión: una pantalla que recarga no lo vuelve a ofrecer.
  static final _ofrecidos = <String>{};
  static Future<Set<String>>? _cargando;

  static Future<Set<String>> vistos() {
    if (_vistos != null) return Future.value(_vistos!);
    return _cargando ??= () async {
      try {
        final r = await ApiService.get('/recorridos/');
        _vistos = r.statusCode == 200
            ? ((json.decode(utf8.decode(r.bodyBytes))['vistos'] as List).cast<String>()).toSet()
            : <String>{};
      } catch (_) {
        // Sin conexión: mejor no ofrecer nada que ofrecerlo de más.
        _vistos = {'*'};
      }
      _cargando = null;
      return _vistos!;
    }();
  }

  static Future<void> marcar(String clave) async {
    (_vistos ??= <String>{}).add(clave);
    try {
      await ApiService.post('/recorridos/', {'clave': clave});
    } catch (_) {}
  }

  // Recorrido pedido desde otro lado ("Mostrame cómo" del asistente, un
  // paso de Primeros pasos): la pantalla lo lanza sola al abrirse, en vez de
  // ofrecerlo. Vence a los 30 s por si la pantalla nunca se llega a abrir.
  static String? _pendiente;
  static DateTime? _pendienteEn;

  /// Pide que la próxima pantalla que cargue el recorrido `clave` lo muestre.
  static void pedir(String clave) {
    _pendiente = clave;
    _pendienteEn = DateTime.now();
  }

  static bool _tomarPendiente(String clave) {
    final vigente = _pendienteEn != null && DateTime.now().difference(_pendienteEn!) < const Duration(seconds: 30);
    if (_pendiente != clave || !vigente) return false;
    _pendiente = null;
    return true;
  }

  /// Al cerrar sesión (otro usuario puede entrar en el mismo dispositivo).
  static void olvidar() {
    _vistos = null;
    _cargando = null;
  }
}

/// La primera vez que alguien entra a una pantalla: un aviso discreto
/// "¿Te muestro cómo funciona?". Se ofrece una sola vez (aunque diga "Ahora
/// no"); después queda el botón "?" de la pantalla.
Future<void> ofrecerRecorrido(BuildContext context, {required String clave, required String titulo, required VoidCallback iniciar}) async {
  if (Recorridos._tomarPendiente(clave)) {
    Recorridos._ofrecidos.add(clave);
    if (await _esperarAlFrente(context, espera: 500)) iniciar();
    return;
  }
  if (!Recorridos._ofrecidos.add(clave)) return;
  final vistos = await Recorridos.vistos();
  if (vistos.contains(clave) || vistos.contains('*') || !context.mounted) return;
  if (!await _esperarAlFrente(context, espera: 1200)) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  var acepto = false;
  messenger
      .showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        content: Row(children: [
          const Icon(Icons.tips_and_updates_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text("¿Te muestro cómo $titulo? Son 30 segundos.")),
        ]),
        action: SnackBarAction(label: "MOSTRAME", onPressed: () => acepto = true),
      ))
      .closed
      .then((_) {
    if (acepto) {
      iniciar();
    } else {
      Recorridos.marcar(clave);
    }
  });
}

/// Espera a que la pantalla termine de dibujarse y esté al frente: si algo
/// la tapa (el asistente de IA que se abre al entrar, un diálogo), espera a
/// que lo cierren -- si no, el recorrido iluminaría cosas tapadas. False si
/// la pantalla se cerró o nunca quedó al frente (5 minutos).
Future<bool> _esperarAlFrente(BuildContext context, {required int espera}) async {
  await Future.delayed(Duration(milliseconds: espera));
  for (var i = 0; i < 300; i++) {
    if (!context.mounted) return false;
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!context.mounted) return false;
      if (ModalRoute.of(context)?.isCurrent ?? true) return true;
    } else {
      await Future.delayed(const Duration(seconds: 1));
    }
  }
  return false;
}

/// Lanza el recorrido de la pantalla donde ya se está (ej. "Mostrame cómo"
/// del asistente estando en esa pantalla) apenas el asistente se cierra.
Future<void> lanzarRecorridoAlFrente(BuildContext context, VoidCallback iniciar) async {
  if (await _esperarAlFrente(context, espera: 300)) iniciar();
}

/// Botón "?" para ver el recorrido de la pantalla cuando se quiera.
class BotonGuia extends StatelessWidget {
  final VoidCallback iniciar;
  final Color? color;
  const BotonGuia({super.key, required this.iniciar, this.color});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: "¿Cómo funciona? Ver el recorrido",
        icon: Icon(Icons.help_outline, color: color),
        onPressed: iniciar,
      );
}

/// Muestra el recorrido. Al terminarlo o saltarlo queda marcado como visto.
Future<void> mostrarRecorrido(BuildContext context, {required String clave, required List<PasoRecorrido> pasos, Color? color}) async {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, __, ___) => _Recorrido(pasos: pasos, color: color ?? Theme.of(context).colorScheme.primary),
    transitionsBuilder: (_, animacion, __, hijo) => FadeTransition(opacity: animacion, child: hijo),
  ));
  await Recorridos.marcar(clave);
}

class _Recorrido extends StatefulWidget {
  final List<PasoRecorrido> pasos;
  final Color color;
  const _Recorrido({required this.pasos, required this.color});

  @override
  State<_Recorrido> createState() => _RecorridoState();
}

class _RecorridoState extends State<_Recorrido> {
  int _i = 0;
  Rect? _hueco;
  Timer? _seguir;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ir(0, 1));
    // Por si la pantalla de abajo se mueve (teclado, scroll, cambio de tamaño).
    _seguir = Timer.periodic(const Duration(milliseconds: 400), (_) => _medir());
  }

  @override
  void dispose() {
    _seguir?.cancel();
    super.dispose();
  }

  bool _visible(PasoRecorrido p) => p.objetivo == null || p.objetivo!.currentContext?.findRenderObject() is RenderBox;

  /// Va al paso `destino`, saltando en `direccion` los que no están en pantalla.
  Future<void> _ir(int destino, int direccion) async {
    var i = destino;
    while (i >= 0 && i < widget.pasos.length && !_visible(widget.pasos[i])) {
      i += direccion;
    }
    if (i < 0) i = _i;
    if (i >= widget.pasos.length) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final objetivo = widget.pasos[i].objetivo?.currentContext;
    if (objetivo != null) {
      await Scrollable.ensureVisible(objetivo, duration: const Duration(milliseconds: 250), alignment: 0.35)
          .catchError((_) {});
    }
    if (!mounted) return;
    setState(() => _i = i);
    _medir();
  }

  void _medir() {
    if (!mounted) return;
    final caja = widget.pasos[_i].objetivo?.currentContext?.findRenderObject();
    Rect? hueco;
    if (caja is RenderBox && caja.hasSize && caja.attached) {
      final esquina = caja.localToGlobal(Offset.zero);
      hueco = (esquina & caja.size).inflate(6);
    }
    if (hueco != _hueco) setState(() => _hueco = hueco);
  }

  bool get _hayAnterior {
    for (var j = _i - 1; j >= 0; j--) {
      if (_visible(widget.pasos[j])) return true;
    }
    return false;
  }

  bool get _esUltimo {
    for (var j = _i + 1; j < widget.pasos.length; j++) {
      if (_visible(widget.pasos[j])) return false;
    }
    return true;
  }

  int get _numero => widget.pasos.take(_i + 1).where(_visible).length;
  int get _total => widget.pasos.where(_visible).length;

  @override
  Widget build(BuildContext context) {
    final paso = widget.pasos[_i];
    final pantalla = MediaQuery.of(context).size;
    final hueco = paso.objetivo == null ? null : _hueco;
    final ancho = (pantalla.width - 32).clamp(0.0, 380.0);

    final globo = Material(
      color: AppColors.surface,
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: ancho,
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.color.withValues(alpha: 0.5))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Text("$_numero de $_total", style: TextStyle(color: widget.color, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Saltar", style: TextStyle(color: AppColors.textMuted)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(paso.titulo, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          const SizedBox(height: 6),
          Text(paso.texto, style: TextStyle(fontSize: 14.5, height: 1.35, color: AppColors.textStrong)),
          const SizedBox(height: 8),
          Row(children: [
            // Puntitos de avance.
            for (var j = 0; j < _total; j++)
              Container(
                width: j == _numero - 1 ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: j == _numero - 1 ? widget.color : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const Spacer(),
            if (_hayAnterior) TextButton(onPressed: () => _ir(_i - 1, -1), child: const Text("Atrás")),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: widget.color),
              onPressed: () => _ir(_i + 1, 1),
              child: Text(_esUltimo ? "Listo" : "Siguiente"),
            ),
          ]),
        ]),
      ),
    );

    // El globo va debajo del elemento si hay espacio; si no, arriba.
    Widget colocado;
    if (hueco == null) {
      colocado = Center(child: globo);
    } else {
      final abajo = pantalla.height - hueco.bottom;
      final izquierda = (hueco.center.dx - ancho / 2).clamp(16.0, (pantalla.width - ancho - 16).clamp(16.0, double.infinity));
      if (abajo > 230) {
        colocado = Positioned(left: izquierda, top: hueco.bottom + 12, child: globo);
      } else if (hueco.top > 230) {
        colocado = Positioned(left: izquierda, bottom: pantalla.height - hueco.top + 12, child: globo);
      } else {
        // El elemento ocupa casi toda la pantalla (ej. el catálogo): el globo va abajo, encima.
        colocado = Positioned(left: izquierda, bottom: 24, child: globo);
      }
    }

    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // la pantalla de abajo no se toca durante el recorrido
          child: CustomPaint(painter: _Velo(hueco: hueco, color: widget.color)),
        ),
      ),
      colocado,
    ]);
  }
}

/// Oscurece todo menos el hueco del elemento, con un borde de color.
class _Velo extends CustomPainter {
  final Rect? hueco;
  final Color color;
  _Velo({required this.hueco, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Path()..addRect(Offset.zero & size);
    final velo = Paint()..color = Colors.black.withValues(alpha: 0.62);
    if (hueco == null) {
      canvas.drawPath(todo, velo);
      return;
    }
    final redondo = RRect.fromRectAndRadius(hueco!, const Radius.circular(12));
    canvas.drawPath(Path.combine(PathOperation.difference, todo, Path()..addRRect(redondo)), velo);
    canvas.drawRRect(redondo, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_Velo viejo) => viejo.hueco != hueco || viejo.color != color;
}
