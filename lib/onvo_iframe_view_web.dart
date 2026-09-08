import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Embebe tarjeta.html en un <iframe> real del navegador (registrado como
/// platform view de Flutter Web) y escucha los window.postMessage que esa
/// página manda al terminar de capturar la tarjeta con el SDK de ONVO.
/// Solo se procesan mensajes cuyo origen coincide con el de `url` -- un
/// iframe puede recibir postMessage de cualquier ventana, no solo del
/// propio, así que sin este chequeo cualquier otra pestaña podría
/// inyectar un "éxito" falso.
class OnvoIframeView extends StatefulWidget {
  final Uri url;
  final void Function(String mensaje) onMensaje;

  const OnvoIframeView({super.key, required this.url, required this.onMensaje});

  @override
  State<OnvoIframeView> createState() => _OnvoIframeViewState();
}

class _OnvoIframeViewState extends State<OnvoIframeView> {
  late final String _viewType;
  StreamSubscription<html.MessageEvent>? _suscripcion;

  @override
  void initState() {
    super.initState();
    _viewType = 'onvo-iframe-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return html.IFrameElement()
        ..src = widget.url.toString()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });

    final origenEsperado = widget.url.origin;
    _suscripcion = html.window.onMessage.listen((evento) {
      if (evento.origin != origenEsperado) return;
      final datos = evento.data;
      if (datos is String) widget.onMensaje(datos);
    });
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
