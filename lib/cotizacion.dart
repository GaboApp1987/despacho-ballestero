import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'dart:convert';
import 'negocio.dart';
import 'formulario_cotizacion.dart';
import 'export_service.dart';
import 'api_service.dart';
import 'cliente.dart';
import 'factura.dart';
import 'detalle_factura_screen.dart';
import 'formato.dart';

class CotizacionScreen extends StatefulWidget {
  final Negocio negocio;
  /// Se llama después de convertir una cotización en factura real, para que
  /// la pantalla dueña (DetalleNegocio) refresque su lista de Facturas.
  final VoidCallback? onFacturaCreada;
  const CotizacionScreen({super.key, required this.negocio, this.onFacturaCreada});

  @override
  State<CotizacionScreen> createState() => _CotizacionScreenState();
}

class _CotizacionScreenState extends State<CotizacionScreen> {
  late Future<List<dynamic>> _cotizacionesFuture;
  List<dynamic> _todasLasCotizaciones = [];
  List<dynamic> _cotizacionesFiltradas = [];
  List<Cliente> _listaClientes = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarCotizaciones();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    try {
      final response = await ApiService.get('/clientes/?negocio=${widget.negocio.id}');
      if (response.statusCode == 200 && mounted) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        setState(() => _listaClientes = data.map((j) => Cliente.fromJson(j)).toList());
      }
    } catch (_) {
      // Silencioso: si falla, simplemente no se podrá cambiar el cliente hasta refrescar.
    }
  }

  void _cargarCotizaciones() {
    setState(() {
      _cotizacionesFuture = obtenerCotizaciones();
    });
  }

  Future<List<dynamic>> obtenerCotizaciones() async {
    final response = await ApiService.get('/cotizaciones/?negocio=${widget.negocio.id}');

    if (response.statusCode == 200) {
      final List data = json.decode(utf8.decode(response.bodyBytes));
      _todasLasCotizaciones = data;
      _cotizacionesFiltradas = data;
      return data;
    } else {
      return [];
    }
  }

  Future<void> _cambiarClienteCotizacion(Map<String, dynamic> c) async {
    if (_listaClientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay clientes cargados todavía, intente de nuevo en un momento.")),
      );
      return;
    }

    Cliente? seleccionado;
    try {
      seleccionado = _listaClientes.firstWhere((cli) => cli.id == c['cliente']);
    } catch (_) {
      seleccionado = null;
    }

    final nuevoCliente = await showDialog<Cliente>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Cambiar Cliente"),
          content: DropdownButtonFormField<Cliente>(
            value: seleccionado,
            decoration: const InputDecoration(labelText: "Cliente", border: OutlineInputBorder()),
            items: _listaClientes.map((cli) => DropdownMenuItem(value: cli, child: Text(cli.nombre))).toList(),
            onChanged: (val) => setStateDialog(() => seleccionado = val),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: seleccionado == null ? null : () => Navigator.pop(ctx, seleccionado),
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );

    if (nuevoCliente == null || nuevoCliente.id == c['cliente']) return;

    try {
      final response = await ApiService.patch(
        '/cotizaciones/${c['id']}/?negocio=${widget.negocio.id}',
        {'cliente': nuevoCliente.id},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Cliente actualizado a ${nuevoCliente!.nombre}"), backgroundColor: Colors.green),
          );
          _cargarCotizaciones();
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al cambiar cliente: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _mostrarDetalleCotizacion(Map<String, dynamic> c) {
    final detalles = (c['detalles'] as List?) ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("COT-${c['consecutivo_cotizacion'].toString().padLeft(5, '0')}"),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Cliente: ${c['cliente_nombre'] ?? 'Cliente General'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text("Productos:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 6),
                if (detalles.isEmpty)
                  const Text("Sin líneas de detalle registradas.", style: TextStyle(color: Colors.grey))
                else
                  ...detalles.map((d) {
                    final precioUnitario = double.tryParse(d['precio_unitario'].toString()) ?? 0.0;
                    final montoIva = double.tryParse((d['monto_iva'] ?? 0).toString()) ?? 0.0;
                    final subtotal = double.tryParse((d['subtotal'] ?? 0).toString()) ?? 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['nombre_producto'] ?? 'Producto', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  "${d['cantidad']} x ${formatearColones(precioUnitario)}"
                                  "${montoIva > 0 ? '  ·  IVA ${formatearColones(montoIva)}' : ''}",
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          Text(formatearColones(subtotal + montoIva), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "TOTAL: ${formatearColones(double.parse(c['total'].toString()))}",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _cambiarClienteCotizacion(c);
            },
            icon: Icon(Icons.person_search, color: AppColors.primary),
            label: const Text("Cambiar Cliente"),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_estaConvertida(c))
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _convertirAFactura(c);
                  },
                  icon: const Icon(Icons.receipt_long, color: Colors.green),
                  label: const Text("Convertir a Factura", style: TextStyle(color: Colors.green)),
                ),
              IconButton(
                tooltip: "Compartir",
                icon: const Icon(Icons.share_outlined, color: Colors.blue),
                onPressed: () => ExportService.exportCotizacionToPdf(c, widget.negocio.nombreComercial, share: true),
              ),
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
            ],
          ),
        ],
      ),
    );
  }

  bool _estaConvertida(Map<String, dynamic> c) => c['estado'] == 'A';

  Future<void> _convertirAFactura(Map<String, dynamic> c) async {
    if (_estaConvertida(c)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Esta cotización ya fue convertida a factura.")),
      );
      return;
    }

    String condicionVenta = "01";
    final plazoCtrl = TextEditingController(text: "0");

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Convertir a Factura"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Se generará una factura real a partir de COT-${c['consecutivo_cotizacion'].toString().padLeft(5, '0')} "
                  "para ${c['cliente_nombre'] ?? 'Cliente General'} por ${formatearColones(double.parse(c['total'].toString()))}.",
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: condicionVenta,
                  decoration: const InputDecoration(labelText: "Condición de Venta", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: "01", child: Text("Contado")),
                    DropdownMenuItem(value: "02", child: Text("Crédito")),
                  ],
                  onChanged: (v) => setStateDialog(() => condicionVenta = v!),
                ),
                if (condicionVenta == "02") ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: plazoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Plazo de crédito (días)", border: OutlineInputBorder()),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Generar Factura")),
          ],
        ),
      ),
    );
    if (confirmar != true) return;

    final int plazoCredito = int.tryParse(plazoCtrl.text) ?? 0;
    // Hacienda exige el plazo de crédito (Art. 27 Ley IVA) en toda factura a
    // crédito -- sin esto la factura se crea bien pero Alanube la rechaza
    // al enviarla (queda en "Error Técnico"), un error que solo se ve
    // despues, no al generarla.
    if (condicionVenta == "02" && plazoCredito <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ingrese los días de crédito: son obligatorios para Hacienda en una venta a crédito.")),
        );
      }
      return;
    }

    Cliente? cliente;
    try {
      cliente = _listaClientes.firstWhere((cli) => cli.id == c['cliente']);
    } catch (_) {
      cliente = null;
    }

    final detalles = (c['detalles'] as List?) ?? [];
    final body = {
      'negocio': widget.negocio.id,
      'cliente': c['cliente'],
      'consecutivo': '',
      'receptor_nombre': cliente?.nombre ?? c['cliente_nombre'] ?? 'Cliente General',
      'receptor_cedula': cliente?.cedula ?? '',
      'total_iva': double.parse(c['monto_iva'].toString()),
      'total_factura': double.parse(c['total'].toString()),
      'condicion_venta': condicionVenta,
      'plazo_credito': plazoCredito,
      'detalles': detalles.map((d) => {
        'producto': d['producto'],
        'cantidad': d['cantidad'],
        'precio_unitario': d['precio_unitario'],
        'monto_iva': d['monto_iva'],
        'subtotal': d['subtotal'],
      }).toList(),
    };

    try {
      final response = await ApiService.post('/facturas/', body);
      if (response.statusCode == 201) {
        final facturaCreada = json.decode(utf8.decode(response.bodyBytes));
        await ApiService.patch('/cotizaciones/${c['id']}/?negocio=${widget.negocio.id}', {'estado': 'A'});
        widget.onFacturaCreada?.call();
        _cargarCotizaciones();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Factura generada correctamente."), backgroundColor: Colors.green),
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DetalleFacturaScreen(factura: Factura.fromJson(facturaCreada))),
          );
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo generar la factura: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filtrarCotizaciones(String query) {
    setState(() {
      _cotizacionesFiltradas = _todasLasCotizaciones.where((c) {
        final nombre = (c['cliente_nombre'] ?? '').toLowerCase();
        final numero = "COT-${c['consecutivo_cotizacion'].toString().padLeft(5, '0')}".toLowerCase();
        return nombre.contains(query.toLowerCase()) || numero.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 🧱 ENCABEZADO Y BÚSQUEDA
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.request_quote_outlined, color: AppColors.primary),
                        SizedBox(width: 10),
                        Text(
                          "Presupuestos y Cotizaciones",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _cargarCotizaciones,
                      tooltip: "Actualizar lista",
                    )
                  ],
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _searchController,
                  onChanged: _filtrarCotizaciones,
                  decoration: InputDecoration(
                    hintText: "Buscar por cliente o número de cotización...",
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _cotizacionesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                
                if (_cotizacionesFiltradas.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text("No se encontraron cotizaciones.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cotizacionesFiltradas.length,
                  itemBuilder: (context, index) {
                    final c = _cotizacionesFiltradas[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12), 
                        side: BorderSide(color: Colors.grey.withOpacity(0.1))
                      ),
                      elevation: 0,
                      child: ListTile(
                        onTap: () => _mostrarDetalleCotizacion(c),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.description, color: AppColors.primary, size: 24),
                        ),
                        title: Row(
                          children: [
                            Text(
                              "COT-${c['consecutivo_cotizacion'].toString().padLeft(5, '0')}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (_estaConvertida(c)) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                                child: const Text("FACTURADA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(c['cliente_nombre'] ?? 'Cliente General', style: TextStyle(color: AppColors.textMuted)),
                            Text(c['fecha_emision'].toString().split('T')[0], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 96,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatearColones(double.parse(c['total'].toString())),
                                textAlign: TextAlign.right,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!_estaConvertida(c))
                                    InkWell(
                                      onTap: () => _convertirAFactura(c),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Tooltip(
                                          message: "Convertir a Factura",
                                          child: Icon(Icons.receipt_long, color: Colors.green, size: 20),
                                        ),
                                      ),
                                    ),
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                                    onSelected: (opcion) {
                                      if (opcion == 'ver') {
                                        ExportService.exportCotizacionToPdf(c, widget.negocio.nombreComercial);
                                      }
                                      if (opcion == 'compartir') {
                                        ExportService.exportCotizacionToPdf(c, widget.negocio.nombreComercial, share: true);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'ver',
                                        child: ListTile(
                                          leading: Icon(Icons.print_outlined, color: AppColors.textMuted),
                                          title: Text("Ver / Imprimir PDF"),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'compartir',
                                        child: ListTile(
                                          leading: Icon(Icons.share_outlined, color: Colors.blue),
                                          title: Text("Compartir"),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "fab_nueva_cotizacion",
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text("NUEVA COTIZACIÓN", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        onPressed: () async {
          bool? creado = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => FormularioCotizacion(negocio: widget.negocio)),
          );
          if (creado == true) {
            _cargarCotizaciones();
          }
        },
      ),
    );
  }
}
