import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'negocio.dart';
import 'compra_model.dart';
import 'formato.dart';

/// Espejo de CuentasPorCobrarScreen, pero del lado de lo que el negocio le
/// debe a SUS proveedores (compras a credito) en vez de lo que le deben a
/// el (facturas a credito de sus clientes).
class CuentasPorPagarScreen extends StatefulWidget {
  final Negocio negocio;
  const CuentasPorPagarScreen({super.key, required this.negocio});

  @override
  State<CuentasPorPagarScreen> createState() => _CuentasPorPagarScreenState();
}

class _CuentasPorPagarScreenState extends State<CuentasPorPagarScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _saldosProveedores = [];

  double get _totalGeneral => _saldosProveedores.fold(
        0.0,
        (sum, item) => sum + (double.tryParse(item['saldo'].toString()) ?? 0.0),
      );

  @override
  void initState() {
    super.initState();
    _cargarSaldos();
  }

  Future<void> _cargarSaldos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/proveedores/saldos/?negocio=${widget.negocio.id}');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _saldosProveedores = data.cast<Map<String, dynamic>>();
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
          SnackBar(content: Text("Error al cargar saldos: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
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
                    Icon(Icons.local_shipping_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text(
                      "Cuentas por Pagar",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarSaldos),
              ],
            ),
          ),
          if (!_isLoading && _saldosProveedores.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: AppColors.surfaceSubtle,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total General por Pagar", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
                  Text(
                    formatearColones(_totalGeneral),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _saldosProveedores.isEmpty
                    ? const Center(child: Text("No hay cuentas pendientes por pagar."))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _saldosProveedores.length,
                        itemBuilder: (context, index) {
                          final item = _saldosProveedores[index];
                          final double saldo = double.tryParse(item['saldo'].toString()) ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withOpacity(0.1),
                                child: Text((item['nombre'] as String).isNotEmpty ? item['nombre'][0].toUpperCase() : '?', style: TextStyle(color: AppColors.primary)),
                              ),
                              title: Text(item['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("Cédula: ${item['cedula_juridica'] ?? '-'}"),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text("Saldo Pendiente", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  Text(
                                    formatearColones(saldo),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DetalleCuentaProveedorScreen(
                                      proveedorId: item['id'],
                                      proveedorNombre: item['nombre'],
                                      negocioId: widget.negocio.id,
                                    ),
                                  ),
                                );
                                _cargarSaldos();
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class DetalleCuentaProveedorScreen extends StatefulWidget {
  final int proveedorId;
  final String proveedorNombre;
  final int negocioId;

  const DetalleCuentaProveedorScreen({
    super.key,
    required this.proveedorId,
    required this.proveedorNombre,
    required this.negocioId,
  });

  @override
  State<DetalleCuentaProveedorScreen> createState() => _DetalleCuentaProveedorScreenState();
}

class _DetalleCuentaProveedorScreenState extends State<DetalleCuentaProveedorScreen> {
  bool _isLoading = true;
  List<dynamic> _historial = [];

  double get _totalPendiente {
    double total = 0.0;
    for (final entry in _historial) {
      final double monto = double.tryParse(entry['monto'].toString()) ?? 0.0;
      // COMPRA y NOTA_DEBITO aumentan lo que se debe; ABONO lo reduce.
      total += entry['tipo'] == 'ABONO' ? -monto : monto;
    }
    return total;
  }

  String _formatFecha(String raw) {
    final DateTime? fecha = DateTime.tryParse(raw);
    if (fecha == null) return raw;
    final local = fecha.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return "$dd/$mm/${local.year} $hh:$min";
  }

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/proveedores/${widget.proveedorId}/historial-cuenta/?negocio=${widget.negocioId}');
      if (response.statusCode == 200) {
        if (mounted) {
          final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
          data.sort((a, b) {
            final DateTime? fechaA = DateTime.tryParse(a['fecha'].toString());
            final DateTime? fechaB = DateTime.tryParse(b['fecha'].toString());
            if (fechaA == null || fechaB == null) return 0;
            return fechaA.compareTo(fechaB);
          });
          setState(() {
            _historial = data;
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Error al cargar historial: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Compra>> _cargarComprasPendientes() async {
    final response = await ApiService.get(
      '/compras/?negocio=${widget.negocioId}&proveedor=${widget.proveedorId}&condicion_compra=02&pagada=false',
    );
    if (response.statusCode == 200) {
      final List data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((j) => Compra.fromJson(j)).toList();
    }
    return [];
  }

  void _mostrarDialogoAbono() async {
    final montoController = TextEditingController();
    final comprasPendientes = await _cargarComprasPendientes();
    Compra? compraSeleccionada;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Registrar Pago a Proveedor"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Monto del Pago",
                  prefixText: "₡ ",
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              if (comprasPendientes.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<Compra?>(
                  value: compraSeleccionada,
                  decoration: const InputDecoration(
                    labelText: "¿Paga una compra específica?",
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<Compra?>(value: null, child: Text("Pago general")),
                    ...comprasPendientes.map((c) => DropdownMenuItem<Compra?>(
                          value: c,
                          child: Text("${c.numeroFacturaProveedor} · ${formatearColones(c.totalCompra)}", overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setStateDialog(() => compraSeleccionada = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () {
                final String montoStr = montoController.text;
                final compraId = compraSeleccionada?.id;
                Navigator.pop(ctx);
                _registrarAbono(montoStr, compraId);
              },
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _registrarAbono(String montoStr, [int? compraId]) async {
    final double? monto = double.tryParse(montoStr.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingrese un monto válido")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.post(
        '/proveedores/${widget.proveedorId}/registrar-abono/?negocio=${widget.negocioId}',
        {
          'negocio': widget.negocioId,
          'monto': monto,
          if (compraId != null) 'compra': compraId,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Pago registrado con éxito"), backgroundColor: Colors.green),
          );
          _cargarHistorial();
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Historial: ${widget.proveedorNombre}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: Column(
        children: [
          if (!_isLoading && _historial.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.surfaceSubtle,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Saldo Pendiente", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
                  Text(
                    formatearColones(_totalPendiente),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _historial.isEmpty
                    ? const Center(child: Text("Sin movimientos registrados."))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _historial.length,
                        itemBuilder: (context, index) {
                          final entry = _historial[index];
                          final String tipo = entry['tipo'];
                          final bool esCompra = tipo == 'COMPRA';
                          final bool esNotaDebito = tipo == 'NOTA_DEBITO';

                          final IconData icono = esCompra
                              ? Icons.shopping_cart_outlined
                              : esNotaDebito
                                  ? Icons.trending_up
                                  : Icons.payments_outlined;
                          final Color color = esCompra ? Colors.orange : (esNotaDebito ? Colors.deepOrange : Colors.green);
                          final String titulo = esCompra
                              ? "Compra ${entry['numero']}"
                              : esNotaDebito
                                  ? "Nota de Débito ${entry['numero']}"
                                  : "Pago a Proveedor";

                          return Card(
                            child: ListTile(
                              leading: Icon(icono, color: color),
                              title: Text(titulo),
                              subtitle: Text(_formatFecha(entry['fecha'].toString())),
                              trailing: Text(
                                "${tipo == 'ABONO' ? '-' : '+'} ${formatearColones(double.parse(entry['monto'].toString()))}",
                                style: TextStyle(fontWeight: FontWeight.bold, color: tipo == 'ABONO' ? Colors.green : Colors.red),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoAbono,
        label: const Text("REGISTRAR PAGO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.green,
      ),
    );
  }
}
