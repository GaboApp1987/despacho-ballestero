import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'factura.dart';
import 'formato.dart';
import 'producto.dart';

/// Nota de Débito de VENTAS (la que el negocio le emite a un cliente sobre
/// una factura aceptada: intereses, cargos adicionales, diferencias de
/// precio). Backend: /notas-debito/ (gestion.models.NotaDebito). Las líneas
/// salen del catálogo porque Hacienda exige CABYS; el IVA de cada línea lo
/// calcula el backend con el impuesto del producto. Devuelve true si se creó.
Future<bool> mostrarDialogoNotaDebitoVenta(BuildContext context, int negocioId, Factura factura) async {
  final resProductos = await ApiService.get('/productos/?negocio=$negocioId');
  if (!context.mounted) return false;
  if (resProductos.statusCode != 200) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudieron cargar los productos.")));
    return false;
  }
  final productos = (json.decode(utf8.decode(resProductos.bodyBytes)) as List).map((j) => Producto.fromJson(j)).toList();
  if (productos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Primero creá en Inventario el producto o servicio que vas a cobrar (ej. \"Intereses\"), con su CABYS."),
    ));
    return false;
  }

  final motivoCtrl = TextEditingController();
  final lineas = <_LineaNd>[_LineaNd()];
  bool guardando = false;

  final creada = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) {
        double total = 0;
        for (final l in lineas) {
          final p = l.producto;
          if (p == null) continue;
          final sub = l.cantidad * (double.tryParse(l.precioCtrl.text.replaceAll(',', '.')) ?? 0);
          total += sub * (1 + (p.impuesto?.porcentaje ?? 0) / 100);
        }
        return AlertDialog(
          title: Text("Nota de débito sobre F-${factura.consecutivo}"),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Cliente: ${factura.receptorNombre}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: motivoCtrl,
                    maxLength: 180,
                    decoration: const InputDecoration(
                      labelText: "Motivo *",
                      hintText: "Ej. Intereses por pago atrasado",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Text("Qué se le cobra:", style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  for (final (i, l) in lineas.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: DropdownButtonFormField<Producto>(
                              initialValue: l.producto,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: "Producto / servicio", border: OutlineInputBorder(), isDense: true),
                              items: productos.map((p) => DropdownMenuItem(value: p, child: Text(p.nombre, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (p) => setStateDialog(() {
                                l.producto = p;
                                if (p != null && l.precioCtrl.text.isEmpty) l.precioCtrl.text = p.precioUnitario.toStringAsFixed(2);
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 56,
                            child: TextFormField(
                              initialValue: '${l.cantidad}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: "Cant.", border: OutlineInputBorder(), isDense: true),
                              onChanged: (v) => setStateDialog(() => l.cantidad = int.tryParse(v) ?? 0),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: l.precioCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: "Precio (₡, sin IVA)", border: OutlineInputBorder(), isDense: true),
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                          ),
                          if (lineas.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setStateDialog(() => lineas.removeAt(i)),
                            ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("Agregar línea"),
                      onPressed: () => setStateDialog(() => lineas.add(_LineaNd())),
                    ),
                  ),
                  const Divider(),
                  Text("Total con IVA (aprox.): ${formatearColones(total)}",
                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    "Se envía a Hacienda al guardarla. Cuando la acepte, al cliente le llega por correo y se suma a lo que te debe.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: guardando
                  ? null
                  : () async {
                      final validas = lineas.where((l) => l.producto != null && l.cantidad > 0).toList();
                      if (motivoCtrl.text.trim().isEmpty || validas.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Indicá el motivo y al menos una línea con producto y cantidad.")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        ApiService.verificar(await ApiService.post('/notas-debito/', {
                          'negocio': negocioId,
                          'factura': factura.id,
                          'motivo': motivoCtrl.text.trim(),
                          'lineas': validas
                              .map((l) => {
                                    'producto': l.producto!.id,
                                    'cantidad': l.cantidad,
                                    'precio_unitario': l.precioCtrl.text.trim().replaceAll(',', '.'),
                                  })
                              .toList(),
                        }));
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                        }
                      }
                    },
              child: guardando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Emitir nota de débito", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ),
  );
  return creada == true;
}

class _LineaNd {
  Producto? producto;
  int cantidad = 1;
  final precioCtrl = TextEditingController();
}
