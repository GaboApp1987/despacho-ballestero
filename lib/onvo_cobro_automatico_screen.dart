import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'onvo_iframe_view.dart';
import 'theme/app_theme.dart';

/// Activa el cobro automático mensual por tarjeta vía ONVO para una
/// SuscripcionNegocio o SuscripcionDespacho que ya existe (y ya tiene
/// monto_mensual guardado). La tarjeta se captura en un WebView que carga
/// el SDK propio de ONVO (webapp/pagos/tarjeta.html + sdk.js) -- esta app
/// nunca ve ni maneja el número de tarjeta, solo el resultado final.
class OnvoCobroAutomaticoScreen extends StatefulWidget {
  final String tipo; // 'negocio' o 'despacho'
  final int suscripcionId;
  final String nombreTitular;
  final bool yaTieneCobroAutomatico;
  /// Si viene, esta pantalla cobra el plan indicado en vez del monto actual
  /// de la suscripción -- el negocio pasa a ese plan (y sus facturas
  /// disponibles suben al toque) recién cuando ONVO confirma el cobro.
  final int? planId;
  final String? planNombre;

  const OnvoCobroAutomaticoScreen({
    super.key,
    required this.tipo,
    required this.suscripcionId,
    required this.nombreTitular,
    this.yaTieneCobroAutomatico = false,
    this.planId,
    this.planNombre,
  });

  @override
  State<OnvoCobroAutomaticoScreen> createState() => _OnvoCobroAutomaticoScreenState();
}

class _OnvoCobroAutomaticoScreenState extends State<OnvoCobroAutomaticoScreen> {
  bool _cargando = true;
  bool _confirmando = false;
  String? _error;
  Uri? _urlTarjeta;

  String get _endpointBase => widget.tipo == 'negocio' ? '/suscripciones-negocio' : '/suscripciones-despacho';

  /// El origen del backend (sin el /api final) -- ahí vive tarjeta.html.
  String get _origenBackend {
    const base = ApiService.baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  @override
  void initState() {
    super.initState();
    // El cambio de plan es una accion aparte, distinta de "reemplazar la
    // tarjeta guardada" -- no hace falta advertir sobre reemplazar nada.
    if (widget.yaTieneCobroAutomatico && widget.planId == null) {
      _confirmarReemplazo();
    } else {
      _iniciar();
    }
  }

  Future<void> _confirmarReemplazo() async {
    final continuar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Reemplazar cobro automático?"),
        content: Text(
          "${widget.nombreTitular} ya tiene una tarjeta activa para el cobro automático. "
          "Si continuás, se va a crear un cobro nuevo (por ejemplo, si cambiaron de tarjeta). "
          "El anterior queda reemplazado.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Continuar")),
        ],
      ),
    );
    if (continuar != true) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _iniciar();
  }

  Future<void> _iniciar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final inicio = await ApiService.post(
        '$_endpointBase/${widget.suscripcionId}/iniciar-cobro-automatico/',
        widget.planId != null ? {'plan': widget.planId} : {},
      );
      final datosInicio = json.decode(utf8.decode(inicio.bodyBytes));
      if (inicio.statusCode != 200) {
        throw Exception(datosInicio['detail'] ?? 'Error desconocido');
      }

      final url = Uri.parse('$_origenBackend/pagos/tarjeta.html').replace(queryParameters: {
        'subscription_id': datosInicio['subscription_id'].toString(),
        'customer_id': datosInicio['customer_id'].toString(),
        'publishable_key': datosInicio['publishable_key'].toString(),
      });

      setState(() {
        _urlTarjeta = url;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _cargando = false;
        _error = "Error al iniciar el cobro automático: $e";
      });
    }
  }

  Future<void> _alRecibirMensajeDeLaTarjeta(String mensaje) async {
    if (_confirmando) return;
    Map<String, dynamic> datos;
    try {
      datos = json.decode(mensaje);
    } catch (_) {
      return;
    }
    if (datos['ok'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo procesar la tarjeta. Intentá de nuevo.")),
        );
      }
      return;
    }

    setState(() => _confirmando = true);
    try {
      final confirmacion = await ApiService.post('$_endpointBase/${widget.suscripcionId}/confirmar-cobro-automatico/', {});
      final datosConfirmacion = json.decode(utf8.decode(confirmacion.bodyBytes));
      if (confirmacion.statusCode == 200 && datosConfirmacion['onvo_status'] == 'active') {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (mounted) {
        setState(() => _confirmando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            "La tarjeta se guardó, pero ONVO todavía no confirma el cobro. Esperá unos segundos y volvé a intentar.",
          )),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _confirmando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al confirmar: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.planId != null
              ? "Cambiar a ${widget.planNombre ?? 'plan nuevo'}"
              : "Cobro automático — ${widget.nombreTitular}",
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  ),
                )
              : Stack(
                  children: [
                    if (_urlTarjeta != null)
                      OnvoIframeView(url: _urlTarjeta!, onMensaje: _alRecibirMensajeDeLaTarjeta),
                    if (_confirmando)
                      Container(
                        color: Colors.black45,
                        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                      ),
                  ],
                ),
    );
  }
}
