import 'modulos.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'plan.dart';

/// Gestión de planes de suscripción (nivel plataforma). Solo el administrador
/// del programa (superusuario) puede crear, editar o borrar planes; los
/// contadores/despachos solo los ven para asignarlos a sus negocios.
class PlanesScreen extends StatefulWidget {
  const PlanesScreen({super.key});

  @override
  State<PlanesScreen> createState() => _PlanesScreenState();
}

class _PlanesScreenState extends State<PlanesScreen> {
  bool _isLoading = true;
  List<Plan> _planes = [];
  List<(String, String)> _catalogoModulos = [];

  @override
  void initState() {
    super.initState();
    _cargarPlanes();
    cargarCatalogoModulos().then((c) {
      if (mounted) setState(() => _catalogoModulos = c);
    });
  }

  Future<void> _cargarPlanes() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/planes/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _planes = data.map((j) => Plan.fromJson(j)).toList();
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Error del servidor: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al cargar los planes: ${ApiService.textoError(e)}")),
        );
      }
    }
  }

  void _mostrarFormulario({Plan? planExistente}) {
    final nombreCtrl = TextEditingController(text: planExistente?.nombre ?? '');
    final limiteCtrl = TextEditingController(
      text: planExistente?.limiteFacturasMensual?.toString() ?? '',
    );
    final usuariosCtrl = TextEditingController(text: planExistente?.limiteUsuarios?.toString() ?? '');
    final iaCtrl = TextEditingController(text: planExistente?.limiteConsultasIa?.toString() ?? '');
    final precioCtrl = TextEditingController(
      text: planExistente?.precioMensual != null ? planExistente!.precioMensual.toString() : '',
    );
    final descripcionCtrl = TextEditingController(text: planExistente?.descripcion ?? '');
    String textoPrecio(double? v) => v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toString());
    final recargaIaCtrl = TextEditingController(text: planExistente?.recargaConsultasIa?.toString() ?? '');
    final recargaIaPrecioCtrl = TextEditingController(text: textoPrecio(planExistente?.recargaConsultasIaPrecio));
    final recargaDocsCtrl = TextEditingController(text: planExistente?.recargaDocumentos?.toString() ?? '');
    final recargaDocsPrecioCtrl = TextEditingController(text: textoPrecio(planExistente?.recargaPrecio));
    // Un plan que cobra el documento extra (ej. Empresa) no vende recarga de
    // documentos (ver Plan.paquetes_recarga en el backend).
    final cobraExtra = planExistente?.precioDocumentoExtra != null;
    // Módulos del plan (modulos.dart); null = todos.
    Set<String>? modulos = planExistente?.modulos?.toSet();
    bool activo = planExistente?.activo ?? true;
    bool guardando = false;
    // Vacío ya no quiere decir ilimitado: se guarda el mínimo. Ilimitado es
    // marcar la casilla (así un plan ilimitado no pierde eso al editarlo).
    bool docsIlimitados = planExistente != null && planExistente.limiteFacturasMensual == null;
    bool iaIlimitada = planExistente != null && planExistente.limiteConsultasIa == null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(planExistente == null ? "Nuevo Plan" : "Editar Plan"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: "Nombre del Plan *", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  _campoConIlimitado(
                    controller: limiteCtrl,
                    etiqueta: "Documentos por período",
                    ilimitado: docsIlimitados,
                    onIlimitado: (v) => setStateDialog(() => docsIlimitados = v),
                  ),
                  const SizedBox(height: 10),
                  _campoConIlimitado(
                    controller: iaCtrl,
                    etiqueta: "Consultas de IA al mes",
                    ilimitado: iaIlimitada,
                    onIlimitado: (v) => setStateDialog(() => iaIlimitada = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: usuariosCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Usuarios", hintText: "Ilimitados", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  _seccionRecarga(
                    titulo: "Recarga de documentos",
                    aviso: docsIlimitados
                        ? "Con documentos ilimitados el plan no necesita recarga."
                        : cobraExtra
                            ? "Este plan cobra cada documento extra, así que no vende recarga."
                            : "Paquete que el negocio compra cuando se le acaba el cupo (no vence). Vacío = el plan no vende recarga de documentos.",
                    cantidadCtrl: recargaDocsCtrl,
                    precioCtrl: recargaDocsPrecioCtrl,
                    etiquetaCantidad: "Documentos",
                    habilitada: !docsIlimitados && !cobraExtra,
                  ),
                  const SizedBox(height: 14),
                  _seccionRecarga(
                    titulo: "Recarga de consultas de IA",
                    aviso: iaIlimitada
                        ? "Con IA ilimitada el plan no necesita recarga."
                        : "Paquete que el negocio compra cuando se le acaban las del mes (no vence). Vacío = el plan no vende recarga de IA.",
                    cantidadCtrl: recargaIaCtrl,
                    precioCtrl: recargaIaPrecioCtrl,
                    etiquetaCantidad: "Consultas",
                    habilitada: !iaIlimitada,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Periodicidad, documento extra, \"incluye\" y \"Más popular\" se ajustan en el panel de administración.",
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: precioCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Precio mensual (₡)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descripcionCtrl,
                    decoration: const InputDecoration(labelText: "Descripción", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Módulos que trae", style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                  ),
                  const SizedBox(height: 2),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Dashboard, Clientes, Facturas y Ajustes los tienen todos los planes.",
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectorModulos(
                    catalogo: _catalogoModulos,
                    elegidos: modulos,
                    onCambio: (v) => setStateDialog(() => modulos = v),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Plan activo"),
                    value: activo,
                    onChanged: (v) => setStateDialog(() => activo = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      final limite = docsIlimitados ? null : _limiteOMinimo(limiteCtrl.text);
                      final limiteIa = iaIlimitada ? null : _limiteOMinimo(iaCtrl.text);
                      if (nombreCtrl.text.trim().isEmpty || (!docsIlimitados && limite == -1) || (!iaIlimitada && limiteIa == -1)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Complete el nombre y escriba números válidos en documentos y consultas de IA.")),
                        );
                        return;
                      }
                      // Cada recarga: cantidad y precio, o ninguno (sin los dos
                      // el backend no la ofrece, ver Plan.paquetes_recarga).
                      final recargaDocs = _leerRecarga(recargaDocsCtrl, recargaDocsPrecioCtrl, habilitada: !docsIlimitados && !cobraExtra);
                      final recargaIa = _leerRecarga(recargaIaCtrl, recargaIaPrecioCtrl, habilitada: !iaIlimitada);
                      if (recargaDocs == null || recargaIa == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(
                            "En la recarga de ${recargaDocs == null ? 'documentos' : 'IA'} escriba la cantidad y el precio, o deje los dos vacíos.")));
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      final body = {
                        'nombre': nombreCtrl.text.trim(),
                        'limite_facturas_mensual': limite,
                        'limite_usuarios': int.tryParse(usuariosCtrl.text.trim()),
                        'limite_consultas_ia': limiteIa,
                        'recarga_documentos': recargaDocs.$1,
                        'recarga_precio': recargaDocs.$2,
                        'recarga_consultas_ia': recargaIa.$1,
                        'recarga_consultas_ia_precio': recargaIa.$2,
                        'modulos': modulos?.toList(),
                        'precio_mensual': precioCtrl.text.trim(),
                        'descripcion': descripcionCtrl.text.trim(),
                        'activo': activo.toString(),
                      };
                      try {
                        final response = planExistente == null
                            ? await ApiService.post('/planes/', body)
                            : await ApiService.patch('/planes/${planExistente.id}/', body);
                        if (response.statusCode == 200 || response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarPlanes();
                        } else {
                          throw Exception(ApiService.mensajeError(response));
                        }
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
                        }
                      }
                    },
              child: guardando
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }

  /// Mínimo de documentos y de consultas de IA de un plan cuando el campo
  /// queda vacío.
  static const int _minimoPlan = 10;

  /// El número escrito, [_minimoPlan] si está vacío o -1 si no es válido.
  static int _limiteOMinimo(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return _minimoPlan;
    return int.tryParse(t) ?? -1;
  }

  /// (cantidad, precio) de una recarga; (null, null) si no vende o está
  /// apagada, y null si está a medias o no es válida.
  static (int?, String?)? _leerRecarga(TextEditingController cantidadCtrl, TextEditingController precioCtrl, {required bool habilitada}) {
    final textoCantidad = cantidadCtrl.text.trim();
    final textoPrecio = precioCtrl.text.trim().replaceAll(',', '.');
    if (!habilitada || (textoCantidad.isEmpty && textoPrecio.isEmpty)) return (null, null);
    final cantidad = int.tryParse(textoCantidad);
    final precio = double.tryParse(textoPrecio);
    if (cantidad == null || cantidad <= 0 || precio == null || precio <= 0) return null;
    return (cantidad, textoPrecio);
  }

  Widget _seccionRecarga({
    required String titulo,
    required String aviso,
    required TextEditingController cantidadCtrl,
    required TextEditingController precioCtrl,
    required String etiquetaCantidad,
    required bool habilitada,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
      const SizedBox(height: 2),
      Text(aviso, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: cantidadCtrl,
            enabled: habilitada,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: etiquetaCantidad, hintText: "Ej: 25", border: const OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: precioCtrl,
            enabled: habilitada,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Precio (₡)", hintText: "Ej: 2500", border: OutlineInputBorder()),
          ),
        ),
      ]),
    ]);
  }

  Widget _campoConIlimitado({
    required TextEditingController controller,
    required String etiqueta,
    required bool ilimitado,
    required ValueChanged<bool> onIlimitado,
  }) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: controller,
          enabled: !ilimitado,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: etiqueta,
            hintText: ilimitado ? "Ilimitado" : "Vacío = $_minimoPlan",
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(value: ilimitado, onChanged: (v) => onIlimitado(v ?? false)),
        const Text("Ilimitado", style: TextStyle(fontSize: 11)),
      ]),
    ]);
  }

  Future<void> _eliminarPlan(Plan plan) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar plan?"),
        content: Text("Se eliminará el plan \"${plan.nombre}\". Los negocios que lo tengan asignado quedarán sin plan."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Borrar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final response = await ApiService.delete('/planes/${plan.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarPlanes();
      } else {
        throw Exception(ApiService.mensajeError(response));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al borrar: ${ApiService.textoError(e)}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Planes de Suscripción"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarPlanes),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _planes.isEmpty
              ? const Center(child: Text("Todavía no hay planes creados.", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _planes.length,
                  itemBuilder: (context, index) {
                    final p = _planes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: p.activo ? const Color(0xFFEEF2FF) : AppColors.border,
                          child: Icon(Icons.workspace_premium, color: p.activo ? AppColors.primary : Colors.grey),
                        ),
                        title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "${p.resumenLimites}"
                          "${p.precioMensual != null ? " · ₡${p.precioMensual!.toStringAsFixed(0)}/${p.unidadPeriodo}" : ""}"
                          "${!p.activo ? " · Inactivo" : ""}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: "Editar",
                              onPressed: () => _mostrarFormulario(planExistente: p),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: "Borrar",
                              onPressed: () => _eliminarPlan(p),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarFormulario(),
        icon: const Icon(Icons.add),
        label: const Text("NUEVO PLAN"),
      ),
    );
  }
}
