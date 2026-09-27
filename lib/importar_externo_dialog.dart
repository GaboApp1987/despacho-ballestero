import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
  await _subirYProcesar(
    context: context,
    negocio: negocio,
    endpoint: endpoint,
    tipoLabel: tipoLabel,
    onImportado: onImportado,
    bytes: bytes,
    nombre: nombre,
    forzar: false,
  );
}

Future<void> _subirYProcesar({
  required BuildContext context,
  required Negocio negocio,
  required String endpoint,
  required String tipoLabel,
  required VoidCallback onImportado,
  required Uint8List bytes,
  required String nombre,
  required bool forzar,
}) async {
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
      {'negocio': negocio.id.toString(), if (forzar) 'forzar': 'true'},
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

    // El backend detectó que el propio documento se identifica como el
    // tipo CONTRARIO al que se está importando (ver advertencia_tipo en
    // extraer_transacciones_externas_con_claude) -- no creó nada todavía,
    // hay que confirmar antes de seguir. Pasó real: un archivo de compras
    // (proveedores reales) se cargó por el botón de Ingresos y quedó como
    // si esos proveedores fueran clientes, sin ningún aviso.
    final advertencia = data['advertencia_tipo'] as String?;
    if (advertencia != null) {
      if (!context.mounted) return;
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("¿Este archivo es correcto?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(child: Text(advertencia)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Estás importando esto como $tipoLabel. Si es correcto, continuá; si no, cerrá y subí el archivo correcto.",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Continuar de todas formas"),
            ),
          ],
        ),
      );
      if (continuar == true && context.mounted) {
        await _subirYProcesar(
          context: context,
          negocio: negocio,
          endpoint: endpoint,
          tipoLabel: tipoLabel,
          onImportado: onImportado,
          bytes: bytes,
          nombre: nombre,
          forzar: true,
        );
      }
      return;
    }

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
                    ? "Se cargaron $creados $tipoLabel."
                    : "No se encontró información de $tipoLabel en ese archivo.",
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

/// Igual que [importarArchivoExterno] pero para productos (Inventario) --
/// a diferencia de compras/ingresos, acá el backend corre la carga en un
/// hilo de fondo y devuelve un job_id de inmediato (ver
/// ProductoViewSet.importar_externo), porque buscar el código CABYS de
/// varios productos puede tardar bastante. Este diálogo consulta el
/// progreso con polling y muestra el conteo avanzando en vivo en vez de
/// solo un spinner indefinido.
Future<void> importarProductosMasivo({
  required BuildContext context,
  required Negocio negocio,
  required VoidCallback onImportado,
}) async {
  final resultado = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf', 'jpg', 'jpeg', 'png'],
    withData: true,
  );
  if (resultado == null || resultado.files.single.bytes == null) return;
  final bytes = resultado.files.single.bytes!;
  final nombre = resultado.files.single.name;

  String jobId;
  try {
    final response = await ApiService.postMultipartBytes(
      '/productos/importar-externo/',
      {'negocio': negocio.id.toString()},
      'archivo',
      bytes,
      nombre,
    );
    if (response.statusCode != 202) {
      String detalle = 'No se pudo iniciar la carga.';
      try {
        detalle = (json.decode(utf8.decode(response.bodyBytes))['detail'] ?? detalle).toString();
      } catch (_) {}
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detalle)));
      return;
    }
    jobId = json.decode(utf8.decode(response.bodyBytes))['job_id'];
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    return;
  }

  if (!context.mounted) return;
  final Map<String, dynamic>? estadoFinal = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DialogoProgresoImportacionProductos(jobId: jobId),
  );
  if (estadoFinal == null) return; // se cerro solo/cancelado

  if (estadoFinal['estado'] == 'error') {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al importar: ${estadoFinal['error']}")),
      );
    }
    return;
  }

  final creados = estadoFinal['creados'] ?? 0;
  final omitidos = (estadoFinal['omitidos'] as List?) ?? [];
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
                  ? "Se cargaron $creados productos."
                  : "No se encontró información de productos en ese archivo.",
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
}

class _DialogoProgresoImportacionProductos extends StatefulWidget {
  final String jobId;
  const _DialogoProgresoImportacionProductos({required this.jobId});

  @override
  State<_DialogoProgresoImportacionProductos> createState() => _DialogoProgresoImportacionProductosState();
}

class _DialogoProgresoImportacionProductosState extends State<_DialogoProgresoImportacionProductos> {
  Timer? _timer;
  Map<String, dynamic> _estado = {"estado": "leyendo", "total": 0, "creados": 0, "procesados": 0};

  @override
  void initState() {
    super.initState();
    _consultar();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) => _consultar());
  }

  Future<void> _consultar() async {
    try {
      final r = await ApiService.get('/productos/importar-externo-estado/?job_id=${widget.jobId}');
      if (r.statusCode != 200 || !mounted) return;
      final datos = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      setState(() => _estado = datos);
      if (datos['estado'] == 'listo' || datos['estado'] == 'error') {
        _timer?.cancel();
        Navigator.of(context).pop(datos);
      }
    } catch (_) {
      // Se sigue intentando en el proximo tick -- un fallo puntual de red
      // no debe cortar el polling.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = (_estado['total'] ?? 0) as int;
    final procesados = (_estado['procesados'] ?? 0) as int;
    final creados = (_estado['creados'] ?? 0) as int;
    final estado = _estado['estado'] as String? ?? 'leyendo';
    final double? progreso = total > 0 ? procesados / total : null;

    String mensaje;
    switch (estado) {
      case 'leyendo':
        mensaje = "Leyendo el archivo con IA...";
        break;
      case 'resolviendo_cabys':
        mensaje = "Buscando códigos CABYS...";
        break;
      case 'creando':
        mensaje = "Cargando productos: $procesados de $total ($creados creados)";
        break;
      default:
        mensaje = "Procesando...";
    }

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mensaje),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progreso),
        ],
      ),
    );
  }
}
