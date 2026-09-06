import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'impuesto.dart';
import 'formato.dart';

class ImpuestosScreen extends StatefulWidget {
  const ImpuestosScreen({super.key});

  @override
  State<ImpuestosScreen> createState() => _ImpuestosScreenState();
}

class _ImpuestosScreenState extends State<ImpuestosScreen> {
  bool _isLoading = true;
  List<Impuesto> _impuestos = [];

  @override
  void initState() {
    super.initState();
    _cargarImpuestos();
  }

  Future<void> _cargarImpuestos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/impuestos/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _impuestos = data.map((j) => Impuesto.fromJson(j)).toList();
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
          SnackBar(content: Text("Error al cargar impuestos: $e")),
        );
      }
    }
  }

  Future<void> _guardarImpuesto({
    int? id,
    required String nombre,
    required String codigo,
    required double porcentaje,
  }) async {
    final body = {
      'nombre': nombre,
      'codigo_hacienda': codigo,
      'porcentaje': porcentaje,
      'activo': true,
    };
    try {
      final response = id == null
          ? await ApiService.post('/impuestos/', body)
          : await ApiService.put('/impuestos/$id/', body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _cargarImpuestos();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar impuesto: $e")),
        );
      }
    }
  }

  Future<void> _eliminarImpuesto(Impuesto imp) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar impuesto"),
        content: Text("¿Desea eliminar \"${imp.nombre}\"?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final response = await ApiService.delete('/impuestos/${imp.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarImpuestos();
      } else {
        throw Exception("No se puede eliminar: está en uso por uno o más productos.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _mostrarFormulario({Impuesto? existente}) {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final porcentajeCtrl = TextEditingController(
      text: existente != null ? existente.porcentaje.toString() : '',
    );
    String codigoSeleccionado = existente?.codigoHacienda ?? '08';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(existente == null ? "Nuevo Impuesto" : "Editar Impuesto"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: "Nombre", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: codigoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: "Código Hacienda (Tarifa)",
                    border: OutlineInputBorder(),
                  ),
                  items: codigosTarifaHacienda.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text("${e.key} - ${e.value}")))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setStateDialog(() {
                      codigoSeleccionado = val;
                      final match = RegExp(r'([\d.]+)%').firstMatch(codigosTarifaHacienda[val] ?? '');
                      if (match != null) porcentajeCtrl.text = match.group(1)!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: porcentajeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Porcentaje (%)", border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () {
                final nombre = nombreCtrl.text.trim();
                final porcentaje = double.tryParse(porcentajeCtrl.text.replaceAll(',', '.'));
                if (nombre.isEmpty || porcentaje == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Complete nombre y porcentaje válidos")),
                  );
                  return;
                }
                Navigator.pop(ctx);
                _guardarImpuesto(
                  id: existente?.id,
                  nombre: nombre,
                  codigo: codigoSeleccionado,
                  porcentaje: porcentaje,
                );
              },
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.percent, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text("Impuestos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              Flexible(
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarFormulario(),
                  icon: const Icon(Icons.add),
                  label: const Text("Nuevo Impuesto"),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _impuestos.isEmpty
                  ? const Center(child: Text("No hay impuestos registrados."))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _impuestos.length,
                      itemBuilder: (context, index) {
                        final imp = _impuestos[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.surfaceSubtle,
                              child: Text(
                                "${formatearNumero(imp.porcentaje, decimales: 0)}%",
                                style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(imp.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              "Código Hacienda: ${imp.codigoHacienda} — ${codigosTarifaHacienda[imp.codigoHacienda] ?? ''}",
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, color: AppColors.primary),
                                  tooltip: "Editar",
                                  onPressed: () => _mostrarFormulario(existente: imp),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  tooltip: "Eliminar",
                                  onPressed: () => _eliminarImpuesto(imp),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
