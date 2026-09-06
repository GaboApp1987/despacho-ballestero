import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'cliente.dart';
import 'formato.dart';
import 'historial_precio_cliente.dart';

/// Muestra, para un cliente puntual, cada producto que se le ha facturado
/// y a que precio -- para negociar rapido el proximo precio sin tener que
/// acordarse o ir a revisar facturas viejas una por una. Ver
/// ClienteViewSet.historial_precios en el backend.
class HistorialPreciosClienteScreen extends StatefulWidget {
  final Cliente cliente;
  const HistorialPreciosClienteScreen({super.key, required this.cliente});

  @override
  State<HistorialPreciosClienteScreen> createState() => _HistorialPreciosClienteScreenState();
}

class _HistorialPreciosClienteScreenState extends State<HistorialPreciosClienteScreen> {
  late Future<List<PrecioHistoricoCliente>> _historialFuture;

  @override
  void initState() {
    super.initState();
    _historialFuture = _cargarHistorial();
  }

  Future<List<PrecioHistoricoCliente>> _cargarHistorial() async {
    final response = await ApiService.get('/clientes/${widget.cliente.id}/historial-precios/');
    if (response.statusCode != 200) {
      throw Exception('Error al obtener el historial de precios');
    }
    final data = json.decode(utf8.decode(response.bodyBytes)) as List;
    return data.map((j) => PrecioHistoricoCliente.fromJson(j)).toList();
  }

  String _formatearFecha(DateTime f) =>
      "${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Precios de ${widget.cliente.nombre}")),
      body: FutureBuilder<List<PrecioHistoricoCliente>>(
        future: _historialFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("No se pudo cargar el historial: ${snapshot.error}"));
          }
          final historial = snapshot.data ?? [];
          if (historial.isEmpty) {
            return const Center(
              child: Text("Todavía no se le ha facturado nada a este cliente.", style: TextStyle(color: Colors.grey)),
            );
          }

          // Agrupamos por producto para que el precio mas reciente de cada
          // uno quede primero y bien visible -- el orden entre productos
          // sigue el de su venta mas reciente.
          final porProducto = <int, List<PrecioHistoricoCliente>>{};
          for (final registro in historial) {
            porProducto.putIfAbsent(registro.productoId, () => []).add(registro);
          }
          final productosOrdenados = porProducto.values.toList()
            ..sort((a, b) => b.first.fechaEmision.compareTo(a.first.fechaEmision));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: productosOrdenados.length,
            itemBuilder: (context, i) {
              final registros = productosOrdenados[i];
              final masReciente = registros.first;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text(masReciente.productoNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    "Último precio: ${formatearColones(masReciente.precioUnitario)} · ${_formatearFecha(masReciente.fechaEmision)}",
                  ),
                  children: registros.map((r) {
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        r.facturaAnulada ? Icons.block : Icons.receipt_long_outlined,
                        color: r.facturaAnulada ? Colors.blueGrey : AppColors.primary,
                        size: 20,
                      ),
                      title: Text("${formatearColones(r.precioUnitario)} × ${r.cantidad}"),
                      subtitle: Text("F-${r.facturaConsecutivo} · ${_formatearFecha(r.fechaEmision)}"),
                      trailing: r.facturaAnulada
                          ? const Text("ANULADA", style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold))
                          : null,
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
