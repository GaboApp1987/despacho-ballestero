import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'dart:convert';
import 'api_service.dart';
import 'producto.dart';

class MovimientosProductoScreen extends StatelessWidget {
  final Producto producto;
  const MovimientosProductoScreen({super.key, required this.producto});

  Future<List<dynamic>> _fetchMovimientos() async {
    final response = await ApiService.get('/productos/${producto.id}/movimientos/');
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Kárdex: ${producto.nombre}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _fetchMovimientos(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final movimientos = snapshot.data ?? [];

          if (movimientos.isEmpty) {
            return const Center(child: Text("Sin movimientos registrados."));
          }

          return ListView.builder(
            itemCount: movimientos.length,
            itemBuilder: (context, i) {
              final mov = movimientos[i];
              final esVenta = mov['tipo'] == 'VENTA';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: Icon(
                    esVenta ? Icons.arrow_downward : Icons.arrow_upward,
                    color: esVenta ? Colors.red : Colors.green,
                  ),
                  title: Text("${mov['tipo']} - Ref: ${mov['referencia']}"),
                  subtitle: Text("${mov['actor']} \n${mov['fecha'].toString().substring(0, 10)}"),
                  trailing: Text(
                    "${esVenta ? '-' : '+'}${mov['cantidad']}",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: esVenta ? Colors.red : Colors.green,
                    ),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}