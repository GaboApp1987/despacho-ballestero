import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'negocio.dart';
import 'plan.dart';
import 'onvo_cobro_automatico_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/tarjeta_plan_negocio.dart';
import 'recarga_onvo_screen.dart';

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
  // Todos, incluidos los que ya no se ofrecen (para reconocer el plan actual).
  List<Plan> _todos = [];

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
      final todos = data.map((p) => Plan.fromJson(p)).toList();
      final planes = todos.where((p) => p.activo).toList()..sort((a, b) => a.orden.compareTo(b.orden));
      setState(() {
        _todos = todos;
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
    for (final plan in _todos) {
      if (plan.id == widget.negocio.planId) return plan;
    }
    return null;
  }

  bool _esBaja(Plan plan) {
    final actual = _planActual;
    if (actual?.precioMensualEquivalente == null || plan.precioMensualEquivalente == null) return false;
    return plan.precioMensualEquivalente! < actual!.precioMensualEquivalente!;
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
      final precio = plan.precioMensual != null ? "₡${plan.precioMensual!.toStringAsFixed(0)}/${plan.unidadPeriodo}" : "";
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
                  ? "Vas a comprar otro bloque del plan ${plan.nombre} (+${plan.limiteFacturasMensual} documentos) "
                      "$precio, que se suma a las facturas que ya tenés disponibles. Se te va a cobrar de inmediato "
                      "con la tarjeta que ingreses."
                  : "Vas a pasar al plan ${plan.nombre} (${plan.resumenLimites}) $precio. "
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

  Future<void> _comprarRecarga(Map<String, dynamic> paquete) async {
    if (widget.negocio.suscripcionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Este negocio todavía no tiene una suscripción para cobrar.")),
      );
      return;
    }
    final esIa = paquete['tipo'] == 'ia';
    final descripcion = "${paquete['cantidad']} ${esIa ? 'consultas de IA' : 'documentos'} por "
        "₡${(paquete['precio'] as num).toStringAsFixed(0)}";
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Comprar recarga"),
        content: Text(
          "Vas a comprar $descripcion, con un solo cobro a tu tarjeta. Se suman a lo que te queda disponible, "
          "no cambian tu plan y no vencen.",
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
        builder: (_) => RecargaOnvoScreen(
          suscripcionId: widget.negocio.suscripcionId!,
          tipo: paquete['tipo'],
          descripcion: descripcion,
          cantidad: (paquete['cantidad'] as num).toInt(),
          monto: (paquete['precio'] as num).toDouble(),
        ),
      ),
    );
    if (exito == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("¡Listo! Se sumaron ${paquete['cantidad']} ${esIa ? 'consultas de IA' : 'documentos'}.")));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uso = widget.negocio.usoPlan;
    final actual = _planActual;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Planes"),
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
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          "Plan actual: ${widget.negocio.planNombre ?? 'Sin plan'}",
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (actual != null && !actual.activo)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "Este plan ya no se ofrece a clientes nuevos, pero lo podés seguir usando igual.",
                              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (uso != null) ...[
                          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: UsoPlanNegocio(uso: uso, onComprarRecarga: _comprarRecarga)),
                          const SizedBox(height: 20),
                        ],
                        LayoutBuilder(builder: (context, c) {
                          final columnas = c.maxWidth >= 960 ? 3 : (c.maxWidth >= 620 ? 2 : 1);
                          final ancho = (c.maxWidth - (columnas - 1) * 14) / columnas;
                          return Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [for (final plan in _planes) SizedBox(width: ancho, child: _tarjetaPlan(plan))],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _tarjetaPlan(Plan plan) {
    final esActual = plan.id == widget.negocio.planId;
    final esBaja = !esActual && _esBaja(plan);
    Widget? pie;
    if (esActual) {
      // Las recargas se compran desde "Tu uso", arriba.
      if (plan.recargaDocumentos == null && !plan.documentosIlimitados && plan.precioDocumentoExtra == null) {
        // Comprar el plan actual de nuevo suma su cupo completo a lo que
        // ya tenga (ver confirmar_cobro_automatico en el backend).
        pie = OutlinedButton(
          onPressed: _procesando ? null : () => _elegirPlan(plan),
          child: Text(_procesando ? "Procesando..." : "Comprar de nuevo (+${plan.limiteFacturasMensual})"),
        );
      }
    } else if (esBaja) {
      pie = Text("Para bajar de plan, pedile a tu contador o despacho.", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5));
    } else {
      pie = SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _procesando ? null : () => _elegirPlan(plan),
          child: Text(_procesando ? "Procesando..." : "Cambiar a este plan"),
        ),
      );
    }
    return TarjetaPlanNegocio(plan: plan, actual: esActual, pie: pie);
  }
}
