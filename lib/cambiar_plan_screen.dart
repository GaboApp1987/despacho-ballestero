import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'negocio.dart';
import 'plan.dart';
import 'onvo_cobro_automatico_screen.dart';
import 'theme/app_theme.dart';

/// Pantalla de autoservicio para que el propio negocio suba de plan (mas
/// facturas mensuales) pagando de una vez con tarjeta -- el limite nuevo
/// queda disponible apenas ONVO confirma el cobro (ver
/// SuscripcionNegocioViewSet.confirmar_cobro_automatico en el backend).
class CambiarPlanScreen extends StatefulWidget {
  final Negocio negocio;

  const CambiarPlanScreen({super.key, required this.negocio});

  @override
  State<CambiarPlanScreen> createState() => _CambiarPlanScreenState();
}

class _CambiarPlanScreenState extends State<CambiarPlanScreen> {
  bool _cargando = true;
  String? _error;
  List<Plan> _planes = [];

  @override
  void initState() {
    super.initState();
    _cargarPlanes();
  }

  Future<void> _cargarPlanes() async {
    try {
      final response = await ApiService.get('/planes/');
      if (response.statusCode != 200) {
        setState(() {
          _error = "No se pudieron cargar los planes disponibles.";
          _cargando = false;
        });
        return;
      }
      final data = json.decode(utf8.decode(response.bodyBytes)) as List;
      final planes = data.map((p) => Plan.fromJson(p)).where((p) => p.activo).toList()
        ..sort((a, b) => a.limiteFacturasMensual.compareTo(b.limiteFacturasMensual));
      setState(() {
        _planes = planes;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = "No se pudieron cargar los planes disponibles: $e";
        _cargando = false;
      });
    }
  }

  Plan? get _planActual {
    for (final plan in _planes) {
      if (plan.id == widget.negocio.planId) return plan;
    }
    return null;
  }

  bool _esBaja(Plan plan) {
    final actual = _planActual;
    if (actual?.precioMensual == null || plan.precioMensual == null) return false;
    return plan.precioMensual! < actual!.precioMensual!;
  }

  Future<void> _elegirPlan(Plan plan) async {
    if (widget.negocio.suscripcionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Este negocio todavía no tiene una suscripción para cobrar.")),
      );
      return;
    }
    final precio = plan.precioMensual != null ? "₡${plan.precioMensual!.toStringAsFixed(0)}/mes" : "";
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmar cambio de plan"),
        content: Text(
          "Vas a pasar al plan ${plan.nombre} (${plan.limiteFacturasMensual} facturas/mes) $precio. "
          "Se te va a cobrar de inmediato con la tarjeta que ingreses, y las facturas nuevas quedan "
          "disponibles apenas se confirme el pago.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Continuar y pagar")),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final exito = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OnvoCobroAutomaticoScreen(
          tipo: 'negocio',
          suscripcionId: widget.negocio.suscripcionId!,
          nombreTitular: widget.negocio.nombreComercial,
          yaTieneCobroAutomatico: widget.negocio.suscripcionCobroAutomatico,
          planId: plan.id,
          planNombre: plan.nombre,
        ),
      ),
    );
    if (exito == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("¡Listo! Ya estás en el plan ${plan.nombre}.")),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cambiar de plan"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(_error!, textAlign: TextAlign.center)),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      "Plan actual: ${widget.negocio.planNombre ?? 'Sin plan'} — "
                      "${widget.negocio.facturasDisponibles ?? 0} de ${widget.negocio.limiteFacturasMensual ?? 0} "
                      "facturas disponibles este mes",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ..._planes.map((plan) {
                      final esActual = plan.id == widget.negocio.planId;
                      final esBaja = !esActual && _esBaja(plan);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Icon(
                            esActual ? Icons.check_circle : Icons.upgrade,
                            color: esActual ? Colors.green : (esBaja ? AppColors.textMuted : null),
                          ),
                          title: Text(plan.nombre),
                          subtitle: Text(
                            "${plan.limiteFacturasMensual} facturas/mes"
                            "${plan.precioMensual != null ? ' — ₡${plan.precioMensual!.toStringAsFixed(0)}/mes' : ''}",
                          ),
                          trailing: esActual
                              ? const Text("Plan actual", style: TextStyle(color: Colors.green))
                              : esBaja
                                  ? Tooltip(
                                      message: "Para bajar de plan, pedile a tu contador o despacho.",
                                      child: Text("No disponible", style: TextStyle(color: AppColors.textMuted)),
                                    )
                                  : ElevatedButton(
                                      onPressed: () => _elegirPlan(plan),
                                      child: const Text("Cambiar"),
                                    ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}
