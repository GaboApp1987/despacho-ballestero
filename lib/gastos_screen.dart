import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'gasto_operativo.dart';
import 'negocio.dart';
import 'formato.dart';

/// Registro de gastos operativos (planilla, alquiler, servicios, etc.):
/// junto con Compras, es lo que alimenta la Declaración de Renta anual.
class GastosScreen extends StatefulWidget {
  final Negocio negocio;
  const GastosScreen({super.key, required this.negocio});

  @override
  State<GastosScreen> createState() => _GastosScreenState();
}

class _GastosScreenState extends State<GastosScreen> {
  bool _cargando = true;
  List<GastoOperativo> _gastos = [];
  List<Proveedor> _proveedores = [];
  late int _anioFiltro;

  @override
  void initState() {
    super.initState();
    _anioFiltro = DateTime.now().year;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final respuestas = await Future.wait([
        ApiService.get('/gastos-operativos/?negocio=${widget.negocio.id}&fecha_inicio=$_anioFiltro-01-01&fecha_fin=$_anioFiltro-12-31'),
        ApiService.get('/proveedores/?negocio=${widget.negocio.id}'),
      ]);
      if (!mounted) return;
      if (respuestas[0].statusCode == 200 && respuestas[1].statusCode == 200) {
        final List gastosData = json.decode(utf8.decode(respuestas[0].bodyBytes));
        final List proveedoresData = json.decode(utf8.decode(respuestas[1].bodyBytes));
        setState(() {
          _gastos = gastosData.map((j) => GastoOperativo.fromJson(j)).toList();
          _proveedores = proveedoresData.map((j) => Proveedor.fromJson(j)).toList();
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar gastos: $e")));
    }
  }

  double get _totalDeducible => _gastos.where((g) => g.deducible).fold(0.0, (s, g) => s + g.monto);
  double get _totalNoDeducible => _gastos.where((g) => !g.deducible).fold(0.0, (s, g) => s + g.monto);

  Future<void> _abrirComprobante(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir el comprobante: $url")));
      }
    }
  }

  void _mostrarFormulario({GastoOperativo? gastoExistente}) {
    final fechaInicial = gastoExistente != null && gastoExistente.fecha.isNotEmpty
        ? DateTime.tryParse(gastoExistente.fecha) ?? DateTime.now()
        : DateTime.now();
    DateTime fecha = fechaInicial;
    String categoria = gastoExistente?.categoria ?? 'otros';
    final descripcionCtrl = TextEditingController(text: gastoExistente?.descripcion ?? '');
    final montoCtrl = TextEditingController(text: gastoExistente != null ? gastoExistente.monto.toStringAsFixed(2) : '');
    bool deducible = gastoExistente?.deducible ?? true;
    int? proveedorId = gastoExistente?.proveedorId;
    Uint8List? bytesComprobante;
    String? nombreComprobante;
    bool guardando = false;

    Future.microtask(() {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Text(gastoExistente == null ? "Nuevo Gasto" : "Editar Gasto"),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () async {
                        final elegida = await showDatePicker(
                          context: ctx,
                          initialDate: fecha,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                        );
                        if (elegida != null) setStateDialog(() => fecha = elegida);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: "Fecha", border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                        child: Text("${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: categoria,
                      decoration: const InputDecoration(labelText: "Categoría", border: OutlineInputBorder()),
                      items: categoriasGasto.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setStateDialog(() => categoria = v!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descripcionCtrl,
                      decoration: const InputDecoration(labelText: "Descripción (opcional)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: montoCtrl,
                      decoration: const InputDecoration(labelText: "Monto (₡)", border: OutlineInputBorder(), prefixText: "₡ "),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      value: proveedorId,
                      decoration: const InputDecoration(labelText: "Proveedor (opcional)", border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text("Sin especificar")),
                        ..._proveedores.map((p) => DropdownMenuItem<int?>(value: p.id, child: Text(p.nombre))),
                      ],
                      onChanged: (v) => setStateDialog(() => proveedorId = v),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final resultado = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                          withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
                        );
                        if (resultado != null && resultado.files.single.bytes != null) {
                          setStateDialog(() {
                            bytesComprobante = resultado.files.single.bytes;
                            nombreComprobante = resultado.files.single.name;
                          });
                        }
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Text(nombreComprobante ?? "Adjuntar comprobante (opcional)", overflow: TextOverflow.ellipsis),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 45), alignment: Alignment.centerLeft),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Gasto deducible", style: TextStyle(fontSize: 14)),
                      subtitle: const Text("Cuenta para reducir la Renta líquida gravable", style: TextStyle(fontSize: 11, color: Colors.grey)),
                      value: deducible,
                      onChanged: (v) => setStateDialog(() => deducible = v),
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
                        final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.').trim());
                        if (monto == null || monto <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Ingrese un monto válido.")));
                          return;
                        }
                        setStateDialog(() => guardando = true);
                        final fechaStr = "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";
                        final body = {
                          'negocio': widget.negocio.id,
                          'fecha': fechaStr,
                          'categoria': categoria,
                          'descripcion': descripcionCtrl.text.trim(),
                          'monto': redondear2(monto),
                          'deducible': deducible,
                          if (proveedorId != null) 'proveedor': proveedorId,
                        };
                        try {
                          final response = gastoExistente == null
                              ? await ApiService.post('/gastos-operativos/', body)
                              : await ApiService.put('/gastos-operativos/${gastoExistente.id}/', body);
                          if (response.statusCode == 200 || response.statusCode == 201) {
                            if (bytesComprobante != null) {
                              final gastoId = gastoExistente?.id ?? json.decode(utf8.decode(response.bodyBytes))['id'];
                              final resAdjunto = await ApiService.uploadBytes('/gastos-operativos/$gastoId/', 'comprobante', bytesComprobante!, nombreComprobante ?? 'comprobante');
                              if (resAdjunto.statusCode != 200 && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text("El gasto se guardó, pero no se pudo adjuntar el comprobante: ${ApiService.mensajeError(resAdjunto)}"),
                                ));
                              }
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            _cargarDatos();
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
    });
  }

  Future<void> _eliminarGasto(GastoOperativo gasto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar gasto?"),
        content: Text("Se eliminará el gasto de ${gasto.categoriaLabel} por ${formatearColones(gasto.monto)}."),
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
      final response = await ApiService.delete('/gastos-operativos/${gasto.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarDatos();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo borrar: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gastos Operativos"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _anioFiltro,
              dropdownColor: AppColors.surface,
              style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.bold),
              iconEnabledColor: AppColors.textStrong,
              items: List.generate(5, (i) => anioActual - i)
                  .map((a) => DropdownMenuItem(value: a, child: Text("$a")))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _anioFiltro = v);
                _cargarDatos();
              },
            ),
          ),
          const SizedBox(width: 12),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.surfaceSubtle,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Deducibles del año", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(formatearColones(_totalDeducible), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ],
                        ),
                      ),
                      if (_totalNoDeducible > 0)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("No deducibles", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(formatearColones(_totalNoDeducible), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _gastos.isEmpty
                      ? const Center(child: Text("No hay gastos registrados en este año.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _gastos.length,
                          itemBuilder: (context, i) {
                            final g = _gastos[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: g.deducible ? const Color(0xFFEEF2FF) : Colors.orange[50],
                                  child: Icon(Icons.receipt_long, color: g.deducible ? AppColors.primary : Colors.orange, size: 20),
                                ),
                                title: Text(g.categoriaLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  [
                                    g.fecha,
                                    if (g.descripcion.isNotEmpty) g.descripcion,
                                    if (g.nombreProveedor != null && g.nombreProveedor!.isNotEmpty) g.nombreProveedor!,
                                    if (!g.deducible) "No deducible",
                                  ].join(" · "),
                                  style: TextStyle(color: g.deducible ? null : Colors.orange[800]),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(formatearColones(g.monto), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    PopupMenuButton<String>(
                                      onSelected: (opcion) {
                                        if (opcion == 'editar') _mostrarFormulario(gastoExistente: g);
                                        if (opcion == 'comprobante' && g.comprobanteUrl != null) _abrirComprobante(g.comprobanteUrl!);
                                        if (opcion == 'borrar') _eliminarGasto(g);
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'editar', child: Text("Editar")),
                                        if (g.comprobanteUrl != null && g.comprobanteUrl!.isNotEmpty)
                                          const PopupMenuItem(value: 'comprobante', child: Text("Ver comprobante")),
                                        const PopupMenuItem(value: 'borrar', child: Text("Borrar")),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarFormulario(),
        icon: const Icon(Icons.add),
        label: const Text("NUEVO GASTO"),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}
