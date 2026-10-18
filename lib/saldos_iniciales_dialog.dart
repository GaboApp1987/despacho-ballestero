import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';

/// Saldo inicial de los clientes a crédito: lo que cada uno ya debía cuando
/// el negocio empezó a usar Equilibra (facturas de otro sistema). Suma a su
/// saldo en Cuentas por Cobrar, los abonos lo pagan primero y nunca va a
/// Hacienda ni a las ventas del mes (ver Cliente.saldo_inicial en el backend).
/// Se carga a mano, de a un cliente, o desde un Excel/CSV/PDF con varios.
Future<void> mostrarSaldosIniciales(BuildContext context, Negocio negocio, VoidCallback alGuardar) async {
  final opcion = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text("Saldos iniciales", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Lo que tus clientes ya te debían a crédito antes de usar Equilibra. "
                "No se manda a Hacienda ni cuenta como venta del mes."),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_outlined),
            title: const Text("Agregar o cambiar el de un cliente"),
            onTap: () => Navigator.pop(ctx, 'mano'),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text("Importar varios desde Excel"),
            subtitle: const Text("Excel, CSV, PDF o foto con cliente, cédula y saldo"),
            onTap: () => Navigator.pop(ctx, 'archivo'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || opcion == null) return;
  if (opcion == 'mano') {
    await _agregarAMano(context, negocio, alGuardar);
  } else {
    await _importarArchivo(context, negocio, alGuardar);
  }
}

String _fechaIso(DateTime f) => "${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}";

Future<void> _agregarAMano(BuildContext context, Negocio negocio, VoidCallback alGuardar) async {
  List<Map<String, dynamic>> clientes;
  try {
    final r = ApiService.verificar(await ApiService.get('/clientes/?negocio=${negocio.id}'));
    clientes = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>()
      ..sort((a, b) => a['nombre'].toString().toLowerCase().compareTo(b['nombre'].toString().toLowerCase()));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    return;
  }
  if (!context.mounted) return;

  Map<String, dynamic>? cliente;
  final montoCtrl = TextEditingController();
  final notaCtrl = TextEditingController();
  DateTime fecha = DateTime.now();
  final guardar = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: const Text("Saldo inicial de un cliente"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<Map<String, dynamic>>(
                displayStringForOption: (c) => "${c['nombre']}${(c['cedula'] ?? '').toString().isNotEmpty ? ' · ${c['cedula']}' : ''}",
                optionsBuilder: (v) {
                  final b = v.text.trim().toLowerCase();
                  return clientes.where((c) =>
                      b.isEmpty || c['nombre'].toString().toLowerCase().contains(b) || (c['cedula'] ?? '').toString().contains(b));
                },
                onSelected: (c) => setDialog(() {
                  cliente = c;
                  // Si ya tenía uno, se muestra para cambiarlo.
                  final actual = double.tryParse((c['saldo_inicial'] ?? '0').toString()) ?? 0;
                  montoCtrl.text = actual > 0 ? actual.toStringAsFixed(2) : '';
                  notaCtrl.text = (c['nota_saldo_inicial'] ?? '').toString();
                  final f = DateTime.tryParse((c['fecha_saldo_inicial'] ?? '').toString());
                  if (f != null) fecha = f;
                }),
                fieldViewBuilder: (ctx, ctrl, foco, _) => TextField(
                  controller: ctrl,
                  focusNode: foco,
                  decoration: const InputDecoration(
                    labelText: "Cliente",
                    hintText: "Buscar por nombre o cédula",
                    prefixIcon: Icon(Icons.person_search_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Saldo que debía (₡)",
                  prefixText: "₡ ",
                  helperText: "Poné 0 para quitarlo.",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final elegida = await showDatePicker(
                    context: ctx, initialDate: fecha, firstDate: DateTime(2000), lastDate: DateTime.now(),
                  );
                  if (elegida != null) setDialog(() => fecha = elegida);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Al día",
                    helperText: "Fecha del corte o de la factura más vieja (para los días de atraso).",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.event),
                  ),
                  child: Text("${fecha.day}/${fecha.month}/${fecha.year}"),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notaCtrl,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: "Nota (opcional)",
                  hintText: "Ej. facturas 1020 a 1035 del sistema anterior",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: cliente == null ? null : () => Navigator.pop(ctx, true),
            child: const Text("Guardar"),
          ),
        ],
      ),
    ),
  );
  if (guardar != true || cliente == null || !context.mounted) return;
  final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.').replaceAll(' ', '')) ?? 0;
  try {
    ApiService.verificar(await ApiService.patch('/clientes/${cliente!['id']}/', {
      'saldo_inicial': monto.toStringAsFixed(2),
      'fecha_saldo_inicial': monto > 0 ? _fechaIso(fecha) : null,
      'nota_saldo_inicial': monto > 0 ? notaCtrl.text.trim() : '',
    }));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(monto > 0
            ? "Saldo inicial de ${cliente!['nombre']}: ${formatearColones(monto)}"
            : "Se quitó el saldo inicial de ${cliente!['nombre']}"),
        backgroundColor: Colors.green,
      ));
    }
    alGuardar();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
  }
}

Future<void> _importarArchivo(BuildContext context, Negocio negocio, VoidCallback alGuardar) async {
  final elegido = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf', 'jpg', 'jpeg', 'png'],
    withData: true,
  );
  if (elegido == null || elegido.files.single.bytes == null || !context.mounted) return;
  final archivo = elegido.files.single;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(child: Text("Leyendo ${archivo.name}...")),
      ]),
    ),
  );
  List<Map<String, dynamic>> filas;
  try {
    final r = ApiService.verificar(await ApiService.postMultipartBytes(
      '/clientes/saldos-iniciales/', {'negocio': negocio.id.toString()}, 'archivo', archivo.bytes!, archivo.name,
    ));
    filas = ((json.decode(utf8.decode(r.bodyBytes))['vista_previa'] as List?) ?? []).cast<Map<String, dynamic>>();
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.pop(context);
  if (filas.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No encontré saldos de clientes en ese archivo.")));
    return;
  }

  final validas = filas.where((f) => f['accion'] != 'omitir').toList();
  final total = validas.fold<double>(0, (s, f) => s + ((f['saldo'] as num?)?.toDouble() ?? 0));
  final crear = validas.where((f) => f['accion'] == 'crear').length;
  final aplicar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("Revisá los saldos (${validas.length})"),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Total: ${formatearColones(total)}"
              "${crear > 0 ? ' · $crear cliente${crear == 1 ? '' : 's'} nuevo${crear == 1 ? '' : 's'} se van a crear' : ''}. "
              "Si un cliente ya tenía saldo inicial, se reemplaza.",
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: filas.map((f) {
                  final omitir = f['accion'] == 'omitir';
                  final nuevo = f['accion'] == 'crear';
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      omitir ? Icons.block : (nuevo ? Icons.person_add_alt : Icons.person_outline),
                      color: omitir ? Colors.grey : (nuevo ? Colors.blue : Colors.green),
                    ),
                    title: Text((f['nombre'] ?? '').toString().isNotEmpty ? f['nombre'].toString() : (f['cedula'] ?? '-').toString()),
                    subtitle: Text(omitir
                        ? "No se carga: ${f['motivo']}"
                        : [
                            if ((f['cedula'] ?? '').toString().isNotEmpty) f['cedula'].toString(),
                            if (nuevo) "cliente nuevo",
                            if (f['fecha'] != null) "al ${f['fecha']}",
                          ].join(' · ')),
                    trailing: Text(
                      f['saldo'] == null ? '-' : formatearColones((f['saldo'] as num).toDouble()),
                      style: TextStyle(fontWeight: FontWeight.bold, color: omitir ? Colors.grey : null),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
        ElevatedButton(
          onPressed: validas.isEmpty ? null : () => Navigator.pop(ctx, true),
          child: Text("Cargar ${validas.length}"),
        ),
      ],
    ),
  );
  if (aplicar != true || !context.mounted) return;
  try {
    final r = ApiService.verificar(await ApiService.post('/clientes/saldos-iniciales/', {
      'negocio': negocio.id,
      'registros': validas,
    }));
    final resultado = (json.decode(utf8.decode(r.bodyBytes))['resultado'] as List?) ?? [];
    final cargados = resultado.where((f) => f['accion'] != 'omitir').length;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Listo: $cargados saldo${cargados == 1 ? '' : 's'} inicial${cargados == 1 ? '' : 'es'} cargado${cargados == 1 ? '' : 's'}."),
        backgroundColor: Colors.green,
      ));
    }
    alGuardar();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
  }
}
