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

  // Evita doble-tap mientras el dialogo/la navegacion todavia estan en
  // camino -- sin esto, tocar "Cambiar" dos veces rapido (ej. mientras el
  // primer tap parecia no responder) podia abrir el dialogo de confirmacion
  // dos veces apiladas.
  bool _procesando = false;

  Future<void> _elegirPlan(Plan plan) async {
    if (_procesando) return;
    if (widget.negocio.suscripcionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Este negocio todavía no tiene una suscripción para cobrar.")),
      );
      return;
    }
    setState(() => _procesando = true);
    try {
      final precio = plan.precioMensual != null ? "₡${plan.precioMensual!.toStringAsFixed(0)}/mes" : "";
      final esMismoplan = plan.id == widget.negocio.planId;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(esMismoplan ? "Confirmar compra adicional" : "Confirmar cambio de plan"),
          // SingleChildScrollView: en un telefono en horizontal (poco alto)
          // el texto podia no entrar y desbordar el dialogo.
          content: SingleChildScrollView(
            child: Text(
              esMismoplan
                  ? "Vas a comprar otro bloque del plan ${plan.nombre} (+${plan.limiteFacturasMensual} facturas/mes) "
                      "$precio, que se suma a las facturas que ya tenés disponibles. Se te va a cobrar de inmediato "
                      "con la tarjeta que ingreses."
                  : "Vas a pasar al plan ${plan.nombre} (${plan.limiteFacturasMensual} facturas/mes) $precio. "
                      "Se te va a cobrar de inmediato con la tarjeta que ingreses, y las facturas nuevas quedan "
                      "disponibles apenas se confirme el pago.",
            ),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo iniciar el cambio de plan: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
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
              : Center(
                  child: ConstrainedBox(
                    // Sin este limite, en una pantalla ancha (web/escritorio)
                    // cada plan se estiraba a lo largo de todo el ancho de la
                    // ventana -- cartas larguísimas y poco legibles.
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          // No se usa "X de Y": si el negocio compro mas
                          // facturas antes de quedarse sin ellas, disponibles
                          // puede superar el limite normal del plan -- eso es
                          // valido, no un error, "X de Y" lo hacia parecer uno.
                          "Plan actual: ${widget.negocio.planNombre ?? 'Sin plan'} "
                          "(${widget.negocio.limiteFacturasMensual ?? 0} facturas/mes) — "
                          "${widget.negocio.facturasDisponibles ?? 0} disponibles ahora",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        ..._planes.map((plan) => _tarjetaPlan(plan)),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _tarjetaPlan(Plan plan) {
    final esActual = plan.id == widget.negocio.planId;
    final esBaja = !esActual && _esBaja(plan);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  esActual ? Icons.check_circle : Icons.upgrade,
                  color: esActual ? Colors.green : (esBaja ? AppColors.textMuted : null),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(plan.nombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "${plan.limiteFacturasMensual} facturas/mes"
              "${plan.precioMensual != null ? ' — ₡${plan.precioMensual!.toStringAsFixed(0)}/mes' : ''}",
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (esActual)
              const Align(alignment: Alignment.centerRight, child: Text("Plan actual", style: TextStyle(color: Colors.green))),
            if (esActual) const SizedBox(height: 8),
            if (esBaja)
              Tooltip(
                message: "Para bajar de plan, pedile a tu contador o despacho.",
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text("No disponible", style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              // Se puede comprar el plan actual de nuevo (o cualquier otro
              // que no sea una baja) aunque todavia tenga facturas
              // disponibles -- cada compra suma el cupo completo del plan
              // a lo que ya tenga, no lo reemplaza (ver
              // confirmar_cobro_automatico en el backend).
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _procesando ? null : () => _elegirPlan(plan),
                  child: Text(
                    _procesando
                        ? "Procesando..."
                        : (esActual ? "Comprar de nuevo (+${plan.limiteFacturasMensual})" : "Cambiar a este plan"),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
