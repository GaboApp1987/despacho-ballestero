import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'ingreso_operativo.dart';
import 'importar_externo_dialog.dart';
import 'negocio.dart';
import 'formato.dart';

/// Ingresos/ventas que no pasan por Factura -- para negocios que llevan su
/// contabilidad con Equilibra pero no facturan electrónicamente acá (ver
/// IngresoOperativo en el backend). Junto con Compras, alimenta la
/// Declaración de IVA/Renta y "Generar asientos automáticos".
class IngresosScreen extends StatefulWidget {
  final Negocio negocio;
  const IngresosScreen({super.key, required this.negocio});

  @override
  State<IngresosScreen> createState() => _IngresosScreenState();
}

class _IngresosScreenState extends State<IngresosScreen> {
  bool _cargando = true;
  List<IngresoOperativo> _ingresos = [];
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
      final res = await ApiService.get(
        '/ingresos-operativos/?negocio=${widget.negocio.id}&fecha_inicio=$_anioFiltro-01-01&fecha_fin=$_anioFiltro-12-31',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final List data = json.decode(utf8.decode(res.bodyBytes));
        setState(() {
          _ingresos = data.map((j) => IngresoOperativo.fromJson(j)).toList();
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar ingresos: $e")));
    }
  }

  double get _totalSubtotal => _ingresos.fold(0.0, (s, i) => s + i.monto);
  double get _totalIva => _ingresos.fold(0.0, (s, i) => s + i.montoIva);

  Future<void> _abrirComprobante(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir el comprobante: $url")));
      }
    }
  }

  void _mostrarFormulario({IngresoOperativo? ingresoExistente}) {
    final fechaInicial = ingresoExistente != null && ingresoExistente.fecha.isNotEmpty
        ? DateTime.tryParse(ingresoExistente.fecha) ?? DateTime.now()
        : DateTime.now();
    DateTime fecha = fechaInicial;
    final clienteCtrl = TextEditingController(text: ingresoExistente?.clienteNombre ?? '');
    final referenciaCtrl = TextEditingController(text: ingresoExistente?.referencia ?? '');
    final montoCtrl = TextEditingController(text: ingresoExistente != null ? ingresoExistente.monto.toStringAsFixed(2) : '');
    final ivaCtrl = TextEditingController(text: ingresoExistente != null ? ingresoExistente.montoIva.toStringAsFixed(2) : '');
    String condicion = ingresoExistente?.condicionVenta ?? '01';
    bool guardando = false;

    Future.microtask(() {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Text(ingresoExistente == null ? "Nuevo Ingreso" : "Editar Ingreso"),
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
                    TextField(
                      controller: clienteCtrl,
                      decoration: const InputDecoration(labelText: "Cliente (opcional)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: referenciaCtrl,
                      decoration: const InputDecoration(labelText: "Referencia / N.° factura (opcional)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: montoCtrl,
                            decoration: const InputDecoration(labelText: "Subtotal (₡)", border: OutlineInputBorder(), prefixText: "₡ "),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: ivaCtrl,
                            decoration: const InputDecoration(labelText: "IVA (₡)", border: OutlineInputBorder(), prefixText: "₡ "),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: condicion,
                      decoration: const InputDecoration(labelText: "Condición", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: '01', child: Text("Contado")),
                        DropdownMenuItem(value: '02', child: Text("Crédito")),
                      ],
                      onChanged: (v) => setStateDialog(() => condicion = v!),
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
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Ingrese un subtotal válido.")));
                          return;
                        }
                        final iva = double.tryParse(ivaCtrl.text.replaceAll(',', '.').trim()) ?? 0;
                        setStateDialog(() => guardando = true);
                        final fechaStr = "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";
                        final body = {
                          'negocio': widget.negocio.id,
                          'fecha': fechaStr,
                          'cliente_nombre': clienteCtrl.text.trim(),
                          'referencia': referenciaCtrl.text.trim(),
                          'monto': redondear2(monto),
                          'monto_iva': redondear2(iva),
                          'condicion_venta': condicion,
                        };
                        try {
                          final response = ingresoExistente == null
                              ? await ApiService.post('/ingresos-operativos/', body)
                              : await ApiService.put('/ingresos-operativos/${ingresoExistente.id}/', body);
                          if (response.statusCode == 200 || response.statusCode == 201) {
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

  Future<void> _eliminarIngreso(IngresoOperativo ingreso) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar ingreso?"),
        content: Text("Se eliminará el ingreso de ${formatearColones(ingreso.total)}."),
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
      final response = await ApiService.delete('/ingresos-operativos/${ingreso.id}/');
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
        title: const Text("Ingresos"),
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
                            const Text("Subtotal del año", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(formatearColones(_totalSubtotal), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("IVA del año", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(formatearColones(_totalIva), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _ingresos.isEmpty
                      ? const Center(child: Text("No hay ingresos registrados en este año.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _ingresos.length,
                          itemBuilder: (context, i) {
                            final ing = _ingresos[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFEEF2FF),
                                  child: Icon(Icons.trending_up, color: AppColors.primary, size: 20),
                                ),
                                title: Text(
                                  ing.clienteNombre.isNotEmpty ? ing.clienteNombre : "Cliente sin especificar",
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  [
                                    ing.fecha,
                                    if (ing.referencia.isNotEmpty) ing.referencia,
                                    ing.condicionVenta == '02' ? 'Crédito' : 'Contado',
                                  ].join(" · "),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(formatearColones(ing.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    PopupMenuButton<String>(
                                      onSelected: (opcion) {
                                        if (opcion == 'editar') _mostrarFormulario(ingresoExistente: ing);
                                        if (opcion == 'comprobante' && ing.comprobanteUrl != null) _abrirComprobante(ing.comprobanteUrl!);
                                        if (opcion == 'borrar') _eliminarIngreso(ing);
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'editar', child: Text("Editar")),
                                        if (ing.comprobanteUrl != null && ing.comprobanteUrl!.isNotEmpty)
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'importar-ingresos',
            onPressed: () => importarArchivoExterno(
              context: context,
              negocio: widget.negocio,
              endpoint: '/ingresos-operativos/importar-externo/',
              tipoLabel: 'ventas',
              onImportado: _cargarDatos,
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text("Importar archivo"),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textStrong,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'nuevo-ingreso',
            onPressed: () => _mostrarFormulario(),
            icon: const Icon(Icons.add),
            label: const Text("Nuevo Ingreso"),
            backgroundColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
