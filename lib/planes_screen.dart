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

  @override
  void initState() {
    super.initState();
    _cargarPlanes();
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
          SnackBar(content: Text("Error al cargar los planes: $e")),
        );
      }
    }
  }

  void _mostrarFormulario({Plan? planExistente}) {
    final nombreCtrl = TextEditingController(text: planExistente?.nombre ?? '');
    final limiteCtrl = TextEditingController(
      text: planExistente != null ? planExistente.limiteFacturasMensual.toString() : '',
    );
    final precioCtrl = TextEditingController(
      text: planExistente?.precioMensual != null ? planExistente!.precioMensual.toString() : '',
    );
    final descripcionCtrl = TextEditingController(text: planExistente?.descripcion ?? '');
    bool activo = planExistente?.activo ?? true;
    bool guardando = false;

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
                  TextField(
                    controller: limiteCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Facturas electrónicas por mes *",
                      border: OutlineInputBorder(),
                    ),
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
                      final limite = int.tryParse(limiteCtrl.text.trim());
                      if (nombreCtrl.text.trim().isEmpty || limite == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Complete el nombre y un límite de facturas válido.")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      final body = {
                        'nombre': nombreCtrl.text.trim(),
                        'limite_facturas_mensual': limite.toString(),
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
                          throw Exception(utf8.decode(response.bodyBytes));
                        }
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error: $e")));
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
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al borrar: $e")));
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
                          "${p.limiteFacturasMensual} facturas/mes"
                          "${p.precioMensual != null ? " · ₡${p.precioMensual!.toStringAsFixed(0)}/mes" : ""}"
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
