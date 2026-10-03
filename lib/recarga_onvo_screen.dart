import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'onvo_iframe_view.dart';
import 'theme/app_theme.dart';

/// Compra de una recarga (documentos o consultas de IA) con un pago único
/// de ONVO. El formulario de tarjeta es el mismo de ONVO
/// (webapp/pagos/tarjeta.html, en modo "one_time"); al terminar, el backend
/// verifica el pago directo con ONVO y suma la recarga al saldo -- si esta
/// pantalla se cierra antes, el webhook de ONVO la aplica igual.
class RecargaOnvoScreen extends StatefulWidget {
  final int suscripcionId;
  final String tipo; // 'documentos' | 'ia'
  final String descripcion; // "25 documentos por ₡4.900"
  final int cantidad;
  final double monto;

  const RecargaOnvoScreen({
    super.key,
    required this.suscripcionId,
    required this.tipo,
    required this.descripcion,
    required this.cantidad,
    required this.monto,
  });

  @override
  State<RecargaOnvoScreen> createState() => _RecargaOnvoScreenState();
}

class _RecargaOnvoScreenState extends State<RecargaOnvoScreen> {
  bool _cargando = true;
  bool _confirmando = false;
  String? _error;
  Uri? _url;
  int? _recargaId;

  String get _origenBackend {
    const base = ApiService.baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final r = await ApiService.post('/suscripciones-negocio/${widget.suscripcionId}/iniciar-recarga/', {'tipo': widget.tipo});
      final datos = json.decode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200) throw Exception(datos['detail'] ?? 'Error desconocido');
      setState(() {
        _recargaId = datos['recarga'];
        _url = Uri.parse('$_origenBackend/pagos/tarjeta.html').replace(queryParameters: {
          'payment_intent_id': datos['payment_intent_id'].toString(),
          'customer_id': datos['customer_id'].toString(),
          'publishable_key': datos['publishable_key'].toString(),
          'concepto': "Recarga de ${widget.cantidad} ${widget.tipo == 'ia' ? 'consultas de IA' : 'documentos'}",
          'detalle': "Se suma a lo que te queda y no vence",
          'monto': widget.monto.toStringAsFixed(0),
        });
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _cargando = false;
        _error = "No se pudo iniciar el pago: $e";
      });
    }
  }

  Future<void> _alRecibirMensaje(String mensaje) async {
    if (_confirmando) return;
    Map<String, dynamic> datos;
    try {
      datos = json.decode(mensaje);
    } catch (_) {
      return;
    }
    if (datos['ok'] != true) return; // el formulario de ONVO ya muestra el motivo
    setState(() => _confirmando = true);
    // ONVO puede tardar unos segundos en marcar el pago como "succeeded".
    for (int intento = 0; intento < 6; intento++) {
      try {
        final r = await ApiService.post('/suscripciones-negocio/${widget.suscripcionId}/confirmar-recarga/', {'recarga': _recargaId});
        final d = json.decode(utf8.decode(r.bodyBytes));
        if (r.statusCode == 200 && d['estado'] == 'pagada') {
          if (mounted) Navigator.pop(context, true);
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) {
      setState(() => _confirmando = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("ONVO todavía no confirma el pago. Si se te cobró, la recarga se suma sola en unos minutos."),
      ));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Recarga: ${widget.descripcion}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
                )
              : Stack(children: [
                  if (_url != null) OnvoIframeView(url: _url!, onMensaje: _alRecibirMensaje),
                  if (_confirmando)
                    Container(
                      color: Colors.black45,
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                ]),
    );
  }
}
