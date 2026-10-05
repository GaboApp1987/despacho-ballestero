import 'dart:convert';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'negocio.dart';
import 'formulario_compra.dart';

/// Pestaña del negocio para ver TODOS los correos que llegaron al buzón de
/// compras (<cedula>@facturas.equilibracr.com) -- a diferencia del aviso
/// dentro de "Compras" (que solo muestra los pendientes de revisar), acá se
/// ve el historial completo: los ya confirmados como compra, los
/// descartados que ya no están, y los que llegaron con error al leer el XML.
class CorreosCompraScreen extends StatefulWidget {
  final Negocio negocio;
  const CorreosCompraScreen({super.key, required this.negocio});

  @override
  State<CorreosCompraScreen> createState() => _CorreosCompraScreenState();
}

class _CorreosCompraScreenState extends State<CorreosCompraScreen> {
  bool _cargando = true;
  List<dynamic> _correos = [];
  bool _soloPendientes = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final query = _soloPendientes ? '&pendientes=true' : '';
      final res = await ApiService.get('/correos-compra-recibidos/?negocio=${widget.negocio.id}$query');
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes)) as List;
        if (mounted) setState(() => _correos = data);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _revisar(Map correo) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormularioCompra(
          negocio: widget.negocio,
          datosPrecarga: correo['datos_parseados'] as Map<String, dynamic>?,
          correoId: correo['id'] as int?,
        ),
      ),
    );
    if (resultado == true) _cargar();
  }

  Future<void> _descartar(Map correo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Descartar correo?"),
        content: Text("Se descartará el correo de \"${correo['remitente'] ?? 'remitente desconocido'}\". Esto no borra ninguna compra."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Descartar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      ApiService.verificar(await ApiService.delete('/correos-compra-recibidos/${correo['id']}/'));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al descartar: $e")));
    }
  }

  ({IconData icono, Color color, String texto}) _estado(Map correo) {
    final tieneError = (correo['error'] ?? '').toString().isNotEmpty;
    final confirmado = correo['compra'] != null;
    if (confirmado) return (icono: Icons.check_circle_outline, color: Colors.green, texto: "Registrada como compra");
    if (tieneError) return (icono: Icons.error_outline, color: Colors.red, texto: "Error al leer el XML");
    return (icono: Icons.pending_outlined, color: Colors.amber.shade800, texto: "Pendiente de revisar");
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_read_outlined),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Correos de compras recibidos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              FilterChip(
                label: const Text("Solo pendientes"),
                selected: _soloPendientes,
                onSelected: (v) {
                  setState(() => _soloPendientes = v);
                  _cargar();
                },
              ),
              IconButton(icon: const Icon(Icons.refresh), tooltip: "Recargar", onPressed: _cargar),
            ],
          ),
          Text(
            "Facturas electrónicas que tus proveedores mandaron directo al buzón del negocio "
            "(${widget.negocio.cedula}@facturas.equilibracr.com). Revisalas para confirmarlas como compra.",
            style: const TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _correos.isEmpty
                    ? const Center(child: Text("Todavía no ha llegado ningún correo a ese buzón.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _correos.length,
                        itemBuilder: (context, index) {
                          final correo = _correos[index] as Map;
                          final estado = _estado(correo);
                          final confirmado = correo['compra'] != null;
                          final tieneError = (correo['error'] ?? '').toString().isNotEmpty;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(estado.icono, color: estado.color),
                              title: Text(correo['remitente']?.toString().isNotEmpty == true ? correo['remitente'].toString() : "Remitente desconocido"),
                              subtitle: Text(
                                [
                                  estado.texto,
                                  if (tieneError) correo['error'].toString() else (correo['asunto']?.toString() ?? ''),
                                  (correo['fecha_recibido'] ?? '').toString().split('T').first,
                                ].where((s) => s.isNotEmpty).join(" · "),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: confirmado
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!tieneError)
                                          TextButton(onPressed: () => _revisar(correo), child: const Text("Revisar")),
                                        IconButton(
                                          icon: const Icon(Icons.close, size: 18),
                                          tooltip: "Descartar",
                                          onPressed: () => _descartar(correo),
                                        ),
                                      ],
                                    ),
                              onTap: (!confirmado && !tieneError) ? () => _revisar(correo) : null,
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
