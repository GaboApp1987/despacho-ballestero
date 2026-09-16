import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'negocio.dart';

/// Botón + flujo completo para importar en bloque las ventas o compras de
/// un negocio que no factura con Equilibra: subís un archivo en CUALQUIER
/// formato (Excel, CSV, PDF, foto) y Claude arma cada movimiento (ver
/// importar-externo en CompraViewSet/IngresoOperativoViewSet) -- nunca
/// toca Hacienda, son registros puramente internos para que la
/// Declaración de IVA/Renta y "Generar asientos automáticos" cuenten con
/// esos datos igual que si se hubieran cargado uno por uno.
Future<void> importarArchivoExterno({
  required BuildContext context,
  required Negocio negocio,
  required String endpoint,
  required String tipoLabel,
  required VoidCallback onImportado,
}) async {
  final resultado = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf', 'jpg', 'jpeg', 'png'],
    withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
  );
  if (resultado == null || resultado.files.single.bytes == null) return;
  final bytes = resultado.files.single.bytes!;
  final nombre = resultado.files.single.name;

  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text("Leyendo $nombre con IA...")),
        ],
      ),
    ),
  );

  try {
    final response = await ApiService.postMultipartBytes(
      endpoint,
      {'negocio': negocio.id.toString()},
      'archivo',
      bytes,
      nombre,
    );
    if (context.mounted) Navigator.pop(context); // cierra "Leyendo..."

    if (response.statusCode != 200) {
      String detalle = 'No se pudo importar el archivo.';
      try {
        final data = json.decode(utf8.decode(response.bodyBytes));
        detalle = data['detail']?.toString() ?? detalle;
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detalle)));
      }
      return;
    }

    final data = json.decode(utf8.decode(response.bodyBytes));
    final creados = data['creados'] ?? 0;
    final omitidos = (data['omitidos'] as List?) ?? [];
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(creados > 0 ? "¡Listo!" : "Nada para importar"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                creados > 0
                    ? "Se cargaron $creados movimiento(s) de $tipoLabel."
                    : "No se encontró ningún movimiento para cargar en ese archivo.",
              ),
              if (omitidos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text("Se omitieron ${omitidos.length}:", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: omitidos
                          .map((o) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  "${o['referencia'] ?? 'Sin referencia'}: ${o['motivo']}",
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
      ),
    );
    if (creados > 0) onImportado();
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}
