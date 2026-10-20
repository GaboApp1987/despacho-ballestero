import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'formulario_compra.dart';
import 'ordenes_compra.dart';
import 'impuesto.dart';
import 'importar_externo_dialog.dart';
import 'negocio.dart';
import 'formato.dart';
import 'widgets/campo_cedula_hacienda.dart';
import 'widgets/selector_ubicacion_cr.dart';
import 'recorridos.dart';
import 'widgets/recorrido_guiado.dart';
import 'widgets/calculadora.dart';

/// Registra una Nota de Débito que el proveedor emitió sobre `compra` (le
/// cobró de más) -- compartido entre la lista de Compras y la pantalla de
/// Notas de Crédito/Débito, ya que ambas necesitan poder crear una. Llama a
/// `onCreada` (recargar la lista del que invoca) recién cuando se guarda con
/// éxito.
Future<void> mostrarDialogoNotaDebito(BuildContext context, Compra compra, {VoidCallback? onCreada}) async {
  final numeroCtrl = TextEditingController();
  final motivoCtrl = TextEditingController();
  final montoCtrl = TextEditingController();
  Uint8List? bytesXml;
  String? nombreXml;
  bool guardando = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) => AlertDialog(
        title: Text("Nota de Débito — ${compra.nombreProveedor ?? 'Proveedor'}"),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final resultado = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['xml'],
                      withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
                    );
                    if (resultado != null && resultado.files.single.bytes != null) {
                      setStateDialog(() {
                        bytesXml = resultado.files.single.bytes;
                        nombreXml = resultado.files.single.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(nombreXml ?? "Adjuntar XML de Hacienda (opcional)", overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 45), alignment: Alignment.centerLeft),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Si adjuntas el XML, el número de documento y el monto se toman de ahí automáticamente.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numeroCtrl,
                  decoration: const InputDecoration(labelText: "Número de documento", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(labelText: "Motivo", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: montoCtrl,
                  enabled: bytesXml == null,
                  decoration: InputDecoration(
                    labelText: "Monto (₡)",
                    border: const OutlineInputBorder(),
                    helperText: bytesXml != null ? "Se toma del XML adjunto" : null,
                  ),
                  keyboardType: TextInputType.number,
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
                    if (bytesXml == null && montoCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text("Adjunte el XML o ingrese el monto manualmente.")),
                      );
                      return;
                    }
                    setStateDialog(() => guardando = true);
                    try {
                      final http.Response response;
                      if (bytesXml != null) {
                        response = await ApiService.postMultipartBytes(
                          '/compras/${compra.id}/agregar-nota-debito/',
                          {'numero_documento': numeroCtrl.text.trim(), 'motivo': motivoCtrl.text.trim()},
                          'archivo',
                          bytesXml!,
                          nombreXml ?? 'nota_debito.xml',
                        );
                      } else {
                        response = await ApiService.post('/compras/${compra.id}/agregar-nota-debito/', {
                          'numero_documento': numeroCtrl.text.trim(),
                          'motivo': motivoCtrl.text.trim(),
                          'monto': redondear2(double.tryParse(montoCtrl.text.trim()) ?? 0),
                        });
                      }
                      if (response.statusCode == 201) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        onCreada?.call();
                      } else {
                        throw Exception(ApiService.mensajeError(response));
                      }
                    } catch (e) {
                      setStateDialog(() => guardando = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
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
}

bool correoAceptable(Map correo) => (correo['error'] ?? '').toString().isEmpty;

/// Registra y acepta ante Hacienda las facturas seleccionadas de una vez
/// (ver aceptar_lote en el backend). Las líneas que coinciden por CABYS
/// suman a su producto; de las demás se pregunta cuáles agregar al
/// inventario (se crean como producto) y el resto entra sin inventario
/// (gasto). Se mandan de a 5 para no pasarse del tiempo límite del servidor.
/// Compartido entre el aviso de Compras y la pestaña de correos de compras;
/// `correos` son los seleccionados, `onProgreso(null)` avisa que terminó de
/// mandar (antes de recargar) y devuelve cuántas se aceptaron.
Future<int> aceptarCorreosEnLote(
  BuildContext context, {
  required int negocioId,
  required List<dynamic> correos,
  required void Function(String? progreso) onProgreso,
  required Future<void> Function() recargar,
}) async {
  final ids = correos
      .where((c) => correoAceptable(c))
      .map<int>((c) => c['id'] as int)
      .toList();
  if (ids.isEmpty) return 0;
  // Líneas que no están en el inventario: el backend ya las vinculó por
  // nombre o CABYS (producto_id / insumo_id) al mandar los correos.
  final nuevas = <({int correoId, int indice, String proveedor, String detalle, num cantidad, bool entera})>[];
  for (final c in correos.where((c) => ids.contains(c['id']))) {
    final datos = c['datos_parseados'] as Map? ?? {};
    final lineas = (datos['lineas'] as List?) ?? [];
    for (var i = 0; i < lineas.length; i++) {
      final l = lineas[i] as Map;
      final cabys = (l['codigo_cabys'] ?? '').toString().trim();
      if (l['producto_id'] != null || l['insumo_id'] != null) continue;
      final cantidad = (l['cantidad'] as num?) ?? 0;
      nuevas.add((
        correoId: c['id'] as int,
        indice: i,
        proveedor: (datos['proveedor_nombre'] ?? c['remitente'] ?? '').toString(),
        detalle: (l['detalle'] ?? cabys).toString(),
        cantidad: cantidad,
        entera: cantidad % 1 == 0,
      ));
    }
  }
  if (!context.mounted) return 0;
  // Apagado por defecto: casi nunca hace falta un producto nuevo por línea.
  final marcadas = <int>{};
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) => AlertDialog(
        title: Text("¿Aceptar ${ids.length} factura${ids.length == 1 ? '' : 's'}?"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Cada factura se registra como compra y se acepta ante Hacienda. Las líneas que coinciden por CABYS "
                  "con un producto tuyo suman a su inventario. Si el proveedor es nuevo, se crea solo.",
                ),
                if (nuevas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    "${nuevas.length} línea${nuevas.length == 1 ? '' : 's'} no ${nuevas.length == 1 ? 'está' : 'están'} en tu inventario. "
                    "Marcá las que querés agregar como producto nuevo; las demás entran como gasto.",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...nuevas.asMap().entries.map((e) {
                    final n = e.value;
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: marcadas.contains(e.key),
                      onChanged: (v) => setStateDialog(() => v == true ? marcadas.add(e.key) : marcadas.remove(e.key)),
                      title: Text(n.detalle),
                      subtitle: Text(
                          "${n.proveedor} · ${formatearNumero(n.cantidad, decimales: n.entera ? 0 : 3)} unid."),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                const Text(
                  "Las que no se puedan aceptar (dólares sin tipo de cambio, montos que no cuadran, otra cédula) quedan por revisar con el motivo.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Aceptar")),
        ],
      ),
    ),
  );
  if (confirmar != true || !context.mounted) return 0;
  final agregar = <String, List<int>>{};
  for (final k in marcadas) {
    agregar.putIfAbsent(nuevas[k].correoId.toString(), () => []).add(nuevas[k].indice);
  }
  final resultados = <Map>[];
  try {
    for (var i = 0; i < ids.length; i += 5) {
      final fin = (i + 5).clamp(0, ids.length);
      onProgreso("Aceptando ${i + 1}-$fin de ${ids.length}...");
      final r = ApiService.verificar(await ApiService.post(
        '/correos-compra-recibidos/aceptar-lote/',
        {'ids': ids.sublist(i, fin), 'agregar': agregar},
      ));
      resultados.addAll((json.decode(utf8.decode(r.bodyBytes))['resultados'] as List).cast<Map>());
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al aceptar: ${ApiService.textoError(e)}")));
    }
  }
  // El nombre del proveedor se toma antes de recargar (las aceptadas salen de la lista).
  final nombres = {
    for (final c in correos)
      c['id']: ((c['datos_parseados'] as Map?)?['proveedor_nombre'] ?? c['remitente'] ?? 'Factura').toString(),
  };
  onProgreso(null);
  final aceptadas = resultados.where((r) => r['ok'] == true).length;
  final fallidas = resultados.where((r) => r['ok'] != true).toList();
  await recargar();
  if (!context.mounted || resultados.isEmpty) return aceptadas;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("$aceptadas de ${resultados.length} aceptada${resultados.length == 1 ? '' : 's'}"),
      content: fallidas.isEmpty
          ? const Text("Todas quedaron registradas y aceptadas ante Hacienda.")
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Con problema:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...fallidas.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text("• ${nombres[r['id']] ?? 'Factura'}: ${r['detalle']}"),
                        )),
                  ],
                ),
              ),
            ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendido"))],
    ),
  );
  return aceptadas;
}

/// Pantalla principal del módulo de Compras: historial de compras
/// (ingresos de mercadería) y gestión de proveedores.
class ComprasScreen extends StatefulWidget {
  final Negocio negocio;
  const ComprasScreen({super.key, required this.negocio});

  @override
  State<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends State<ComprasScreen> {
  bool _cargando = true;
  List<Compra> _compras = [];
  // Filtro del Historial por la respuesta a Hacienda (Mensaje Receptor):
  // 'todas', 'aceptadas', 'pendientes' o 'rechazadas'.
  String _filtroHacienda = 'todas';
  List<Proveedor> _proveedores = [];
  List<dynamic> _correosPendientes = [];
  // "Aceptar seleccionadas" en las facturas por revisar (ver _aceptarCorreosEnLote).
  final Set<int> _correosSeleccionados = {};
  String? _progresoLote;
  bool _guiaOfrecida = false;
  bool _modoSeleccion = false;
  final Set<int> _comprasSeleccionadas = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<double> _obtenerTipoCambioDelDia() async {
    try {
      final r = await ApiService.get('/tipo-cambio/');
      if (r.statusCode == 200) {
        final d = json.decode(utf8.decode(r.bodyBytes));
        if (d['disponible'] == true) return (d['venta'] as num).toDouble();
      }
    } catch (_) {}
    return 1.0;
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final respuestas = await Future.wait([
        ApiService.get('/compras/?negocio=${widget.negocio.id}'),
        ApiService.get('/proveedores/?negocio=${widget.negocio.id}'),
        ApiService.get('/correos-compra-recibidos/?negocio=${widget.negocio.id}&pendientes=true'),
      ]);
      if (!mounted) return;
      if (respuestas[0].statusCode == 200 && respuestas[1].statusCode == 200) {
        final List comprasData = json.decode(utf8.decode(respuestas[0].bodyBytes));
        final List proveedoresData = json.decode(utf8.decode(respuestas[1].bodyBytes));
        final List correosData = respuestas[2].statusCode == 200
            ? json.decode(utf8.decode(respuestas[2].bodyBytes))
            : [];
        setState(() {
          _compras = comprasData.map((j) => Compra.fromJson(j)).toList();
          _proveedores = proveedoresData.map((j) => Proveedor.fromJson(j)).toList();
          _correosPendientes = correosData;
          _correosSeleccionados.removeWhere((id) => !correosData.any((c) => c['id'] == id));
          _cargando = false;
        });
        _consultarMensajesEnviados();
        if (!_guiaOfrecida) {
          _guiaOfrecida = true;
          ofrecerRecorrido(context, clave: GuiaCompras.clave, titulo: "se registran las compras", iniciar: _mostrarGuia);
        }
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar compras: ${ApiService.textoError(e)}")));
    }
  }

  Future<void> _abrirNuevaCompra() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => FormularioCompra(negocio: widget.negocio)),
    );
    if (resultado == true) {
      await _cargarDatos();
      // Si se aceptó ante Hacienda al confirmar, Hacienda lo procesa en
      // unos segundos: se vuelve a consultar para que pase a "Aceptadas".
      await Future.delayed(const Duration(seconds: 6));
      if (mounted) await _consultarMensajesEnviados();
    }
  }

  /// Abre "Nueva Compra" precargada con lo que ya se leyó del XML que llegó
  /// por correo a <cedula>@facturas.equilibracr.com. El correo solo se borra
  /// de "pendientes" cuando el usuario efectivamente guarda la compra (ver
  /// FormularioCompra._guardarCompra), nunca solo por abrirlo.
  Future<void> _revisarCorreoPendiente(Map correo) async {
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
    if (resultado == true) {
      await _cargarDatos();
      // Si se aceptó ante Hacienda al confirmar, Hacienda lo procesa en
      // unos segundos: se vuelve a consultar para que pase a "Aceptadas".
      await Future.delayed(const Duration(seconds: 6));
      if (mounted) await _consultarMensajesEnviados();
    }
  }

  Future<void> _aceptarCorreosEnLote() async {
    final aceptadas = await aceptarCorreosEnLote(
      context,
      negocioId: widget.negocio.id,
      correos: _correosPendientes.where((c) => _correosSeleccionados.contains(c['id'])).toList(),
      onProgreso: (p) => setState(() {
        _progresoLote = p;
        if (p == null) _correosSeleccionados.clear();
      }),
      recargar: _cargarDatos,
    );
    // Hacienda procesa los Mensajes Receptor en unos segundos.
    if (aceptadas > 0) {
      await Future.delayed(const Duration(seconds: 6));
      if (mounted) await _consultarMensajesEnviados();
    }
  }

  Future<void> _descartarCorreoPendiente(Map correo) async {
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
      _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al descartar: ${ApiService.textoError(e)}")));
      }
    }
  }

  /// Importación masiva: se eligen varios XML de facturas de proveedores de
  /// una vez y se crea automáticamente una compra por cada uno (proveedor y
  /// productos se resuelven o crean solos, igual que con un solo archivo).
  Future<void> _importarVariosXml() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      allowMultiple: true,
      withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
    );
    if (resultado == null || resultado.files.isEmpty) return;

    // Para poder asignarle un impuesto al producto que se crea solo (sin
    // preguntar) cuando una línea no coincide con ninguno existente por
    // CABYS -- si no, esas líneas quedaban sin impuesto y el Reporte de
    // Compras/Declaración de IVA no podía calcular su crédito fiscal.
    List<Impuesto> impuestos = [];
    try {
      final resImpuestos = await ApiService.get('/impuestos/');
      if (resImpuestos.statusCode == 200) {
        final data = json.decode(utf8.decode(resImpuestos.bodyBytes)) as List;
        impuestos = data.map((j) => Impuesto.fromJson(j)).toList();
      }
    } catch (_) {
      // Sin la lista de impuestos simplemente los productos nuevos quedan
      // sin impuesto asignado, igual que antes de este fix.
    }

    final archivos = resultado.files.where((f) => f.bytes != null).toList();
    final List<String> exitosos = [];
    final List<String> fallidos = [];
    final List<String> conAdvertencia = [];
    // Estos viven FUERA del builder del diálogo a propósito: si estuvieran
    // declarados dentro de StatefulBuilder.builder, cada setState los
    // reiniciaría a su valor inicial (por eso el contador se quedaba en 0).
    int procesados = 0;
    bool terminado = false;
    void Function(void Function())? refrescarDialogo;

    Future<void> procesarTodos() async {
      for (final archivo in archivos) {
        try {
          final cuadre = await _importarUnXml(archivo.bytes!, archivo.name, impuestos);
          exitosos.add(archivo.name);
          if (cuadre != null) {
            final totalLineas = (cuadre['total_calculado'] as num).toDouble();
            final diferencia = (cuadre['diferencia'] as num).toDouble();
            conAdvertencia.add(
              "${archivo.name}: el comprobante dice ${formatearColones(totalLineas + diferencia)} pero las "
              "líneas suman ${formatearColones(totalLineas)}",
            );
          }
        } catch (e) {
          fallidos.add("${archivo.name}: ${ApiService.textoError(e)}");
        }
        procesados++;
        refrescarDialogo?.call(() {});
      }
      terminado = true;
      refrescarDialogo?.call(() {});
    }

    procesarTodos(); // se dispara una sola vez; el ciclo real corre en segundo plano

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          refrescarDialogo = setStateDialog;
          return AlertDialog(
            title: const Text("Importando facturas"),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: archivos.isEmpty ? 0 : procesados / archivos.length),
                  const SizedBox(height: 16),
                  Text("$procesados de ${archivos.length} archivos procesados"),
                ],
              ),
            ),
            actions: [
              if (terminado)
                ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
            ],
          );
        },
      ),
    );

    await _cargarDatos();
    if (mounted) {
      final resumen = "Importadas: ${exitosos.length}"
          "${conAdvertencia.isNotEmpty ? ' · Con advertencia: ${conAdvertencia.length}' : ''}"
          "${fallidos.isNotEmpty ? ' · Con error: ${fallidos.length}' : ''}";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resumen)));
      if (conAdvertencia.isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Facturas con el total descuadrado"),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Se cargaron igual, pero conviene revisar los precios de estas líneas contra el "
                      "comprobante original -- probablemente la IA leyó mal un precio:",
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Text(conAdvertencia.join("\n\n"), style: const TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
          ),
        );
      }
      if (fallidos.isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Archivos con error"),
            content: SingleChildScrollView(child: Text(fallidos.join("\n\n"))),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
          ),
        );
      }
    }
  }

  /// Lee un XML de proveedor, resuelve/crea el proveedor y los productos por
  /// CABYS (sin preguntar, ya que es un proceso masivo), y crea la compra.
  /// Devuelve el aviso de cuadre si el total de las líneas no coincide con
  /// el del comprobante (ver verificar_cuadre_lineas en el backend) -- como
  /// este flujo no muestra las líneas para revisar antes de guardar (a
  /// diferencia de Nueva Compra), es la única forma de que el descuadre no
  /// pase desapercibido.
  Future<Map?> _importarUnXml(Uint8List bytes, String nombreArchivo, List<Impuesto> impuestos) async {
    final response = await ApiService.postMultipartBytes(
      '/compras/leer-xml/',
      {'negocio': widget.negocio.id.toString()},
      'archivo',
      bytes,
      nombreArchivo,
    );
    // El motivo real (ej. "es una nota de crédito, no una factura"), no el
    // JSON crudo ni un "no se pudo" genérico.
    if (response.statusCode != 200) throw Exception(ApiService.mensajeError(response));
    final datos = json.decode(utf8.decode(response.bodyBytes));

    // Si el proveedor facturó en dólares, se convierte todo a colones acá
    // (con el tipo de cambio que trae el comprobante, o si no, el del día
    // según el BCCR) -- el resto de la app siempre trabaja en colones.
    final moneda = (datos['moneda'] as String?)?.toUpperCase() == 'USD' ? 'USD' : 'CRC';
    double tipoCambio = 1.0;
    if (moneda == 'USD') {
      final tcExtraido = (datos['tipo_cambio'] as num?)?.toDouble();
      tipoCambio = (tcExtraido != null && tcExtraido > 0) ? tcExtraido : await _obtenerTipoCambioDelDia();
    }

    int? proveedorId = datos['proveedor_id'];
    if (proveedorId == null && datos['proveedor_nombre'] != null) {
      final resProv = await ApiService.post('/proveedores/', {
        'negocio': widget.negocio.id,
        'nombre': datos['proveedor_nombre'],
        'cedula_juridica': datos['proveedor_cedula'] ?? '',
        'correo': datos['proveedor_correo'] ?? '',
      });
      // 200 = ya existía con esa cédula (el backend no duplica proveedores).
      if (resProv.statusCode != 201 && resProv.statusCode != 200) {
        throw Exception("No se pudo crear el proveedor: ${ApiService.mensajeError(resProv)}");
      }
      proveedorId = json.decode(utf8.decode(resProv.bodyBytes))['id'];
    }
    if (proveedorId == null) throw Exception("El XML no trae datos del proveedor");

    final List lineas = datos['lineas'] ?? [];
    if (lineas.isEmpty) throw Exception("El XML no trae líneas de detalle");

    final detallesCompra = [];
    double total = 0;
    for (final linea in lineas) {
      int? productoId = linea['producto_id'];
      final cantidad = ((linea['cantidad'] as num?) ?? 1);
      final precio = redondear2(((linea['precio_unitario'] as num?) ?? 0) * tipoCambio);
      if (productoId == null && linea['insumo_id'] != null) {
        detallesCompra.add({'insumo': linea['insumo_id'], 'cantidad': cantidad, 'precio_costo': precio});
        total += precio * cantidad;
        continue;
      }
      if (productoId == null) {
        // Busca el impuesto por el % que trae la línea (XML: <Impuesto><Tarifa>,
        // o el que Claude haya podido leer en un PDF/foto) para no dejar el
        // producto nuevo sin impuesto asignado -- si no viene tarifa, o no
        // hay un impuesto activo con ese %, queda sin asignar como antes.
        final tarifaLinea = (linea['tarifa'] as num?)?.toDouble();
        final impuestoId = tarifaLinea == null
            ? null
            : impuestos.firstWhere(
                (i) => (i.porcentaje - tarifaLinea).abs() < 0.01,
                orElse: () => Impuesto(id: -1, nombre: '', porcentaje: -1, codigoHacienda: ''),
              ).id;
        final resProd = await ApiService.post('/productos/', {
          'negocio': widget.negocio.id,
          'nombre': linea['detalle'] ?? 'Producto sin nombre',
          'codigo_cabys': linea['codigo_cabys'] ?? '',
          'unidad_medida': 'Unid',
          'precio_unitario': precio,
          'stock': 0,
          if (impuestoId != null && impuestoId != -1) 'impuesto': impuestoId,
        });
        if (resProd.statusCode != 201) {
          throw Exception("No se pudo crear el producto '${linea['detalle']}': ${ApiService.mensajeError(resProd)}");
        }
        productoId = json.decode(utf8.decode(resProd.bodyBytes))['id'];
      }
      detallesCompra.add({'producto': productoId, 'cantidad': cantidad, 'precio_costo': precio});
      total += precio * cantidad;
    }

    final totalComprobante = datos['total_comprobante'] as num?;
    final resCompra = await ApiService.post('/compras/', {
      'negocio': widget.negocio.id,
      'proveedor': proveedorId,
      'numero_factura_proveedor': datos['numero_factura'] ?? datos['clave'] ?? '',
      'moneda': moneda,
      'tipo_cambio': tipoCambio,
      'total_compra': redondear2(totalComprobante != null ? totalComprobante * tipoCambio : total),
      if (datos['fecha'] != null) 'fecha_compra': datos['fecha'],
      'detalles_compra': detallesCompra,
    });
    if (resCompra.statusCode != 201) throw Exception("No se pudo crear la compra: ${ApiService.mensajeError(resCompra)}");

    final compraId = json.decode(utf8.decode(resCompra.bodyBytes))['id'];
    final resAdjunto = await ApiService.uploadBytes('/compras/$compraId/', 'comprobante', bytes, nombreArchivo);
    if (resAdjunto.statusCode != 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("$nombreArchivo: la compra se registró, pero no se pudo adjuntar el archivo (${ApiService.mensajeError(resAdjunto)})."),
      ));
    }

    final cuadre = datos['cuadre'] as Map?;
    return (cuadre != null && cuadre['cuadra'] != true) ? cuadre : null;
  }

  Future<void> _abrirComprobante(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir el comprobante: $url")));
      }
    }
  }

  void _mostrarFormularioProveedor({Proveedor? proveedorExistente}) {
    final nombreCtrl = TextEditingController(text: proveedorExistente?.nombre ?? '');
    final cedulaCtrl = TextEditingController(text: proveedorExistente?.cedula ?? '');
    final correoCtrl = TextEditingController(text: proveedorExistente?.correo ?? '');
    final telefonoCtrl = TextEditingController(text: proveedorExistente?.telefono ?? '');
    final senasCtrl = TextEditingController(text: proveedorExistente?.otrasSenas ?? '');
    String tipoCedula = proveedorExistente?.tipoCedula ?? '01';
    String regimen = proveedorExistente?.regimen ?? '';
    String? provincia = proveedorExistente?.provincia;
    String? canton = proveedorExistente?.canton;
    String? distrito = proveedorExistente?.distrito;
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(proveedorExistente == null ? "Nuevo Proveedor" : "Editar Proveedor"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // La cédula primero: con ella se carga el nombre de Hacienda.
                CampoCedulaHacienda(
                  controller: cedulaCtrl,
                  nombreController: nombreCtrl,
                  labelText: "Cédula (opcional)",
                  // Hacienda dice el tipo de cédula y el régimen: así no hay
                  // que adivinar si es del régimen simplificado.
                  onEncontrado: (datos) => setStateDialog(() {
                    final tipo = (datos['tipo_cedula'] ?? '').toString();
                    if (tipo.isNotEmpty) tipoCedula = tipo;
                    final reg = (datos['regimen'] ?? '').toString().toLowerCase();
                    if (reg.isNotEmpty) regimen = reg.contains('simplific') ? 'simplificado' : 'tradicional';
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: "Nombre / Razón Social *", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: correoCtrl,
                  decoration: const InputDecoration(labelText: "Correo (Opcional)", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Teléfono / WhatsApp (Opcional)",
                    helperText: "Para mandarle las órdenes de compra",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: regimen,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Régimen tributario", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '', child: Text("Sin indicar")),
                    DropdownMenuItem(value: 'tradicional', child: Text("Tradicional (me da factura electrónica)")),
                    DropdownMenuItem(value: 'simplificado', child: Text("Simplificado (yo emito la factura de compra)")),
                  ],
                  onChanged: (v) => setStateDialog(() => regimen = v ?? ''),
                ),
                if (regimen == 'simplificado') ...[
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Ubicación del proveedor (Hacienda la exige en la factura de compra)",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  const SizedBox(height: 6),
                  SelectorUbicacionCR(
                    provincia: provincia,
                    canton: canton,
                    distrito: distrito,
                    onChanged: (p, c, d) {
                      provincia = p;
                      canton = c;
                      distrito = d;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: senasCtrl,
                    decoration: const InputDecoration(labelText: "Otras señas", border: OutlineInputBorder()),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Ingrese el nombre del proveedor.")));
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      final body = {
                        'negocio': widget.negocio.id.toString(),
                        'nombre': nombreCtrl.text.trim(),
                        'cedula_juridica': cedulaCtrl.text.trim(),
                        'correo': correoCtrl.text.trim(),
                        'telefono': telefonoCtrl.text.trim(),
                        'tipo_cedula': tipoCedula,
                        'regimen': regimen,
                        'provincia': provincia ?? '',
                        'canton': canton ?? '',
                        'distrito': distrito ?? '',
                        'otras_senas': senasCtrl.text.trim(),
                      };
                      try {
                        final response = proveedorExistente == null
                            ? await ApiService.post('/proveedores/', body)
                            : await ApiService.patch('/proveedores/${proveedorExistente.id}/', body);
                        if (response.statusCode == 200 || response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarDatos();
                        } else {
                          throw Exception(ApiService.mensajeError(response));
                        }
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
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
  }

  Future<void> _eliminarProveedor(Proveedor proveedor) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar proveedor?"),
        content: Text("Se eliminará \"${proveedor.nombre}\". Las compras ya registradas con este proveedor no se borran."),
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
      final response = await ApiService.delete('/proveedores/${proveedor.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarDatos();
      } else {
        throw Exception(ApiService.mensajeError(response));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al borrar: ${ApiService.textoError(e)}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_modoSeleccion ? "${_comprasSeleccionadas.length} seleccionadas" : "Compras"),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textStrong,
          leading: _modoSeleccion
              ? IconButton(icon: const Icon(Icons.close), onPressed: _salirModoSeleccion)
              : null,
          actions: _modoSeleccion
              ? [
                  IconButton(
                    icon: Icon(_comprasSeleccionadas.length == _comprasFiltradas.length ? Icons.deselect : Icons.select_all),
                    tooltip: _comprasSeleccionadas.length == _comprasFiltradas.length ? "Deseleccionar todas" : "Seleccionar todas",
                    onPressed: _alternarSeleccionTodas,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: "Borrar seleccionadas",
                    onPressed: _comprasSeleccionadas.isEmpty ? null : _borrarSeleccionadas,
                  ),
                ]
              : [
                  const BotonCalculadora(),
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    tooltip: "Seleccionar varias para borrar",
                    onPressed: () => setState(() => _modoSeleccion = true),
                  ),
                  IconButton(
                    key: GuiaCompras.importarVarios,
                    icon: const Icon(Icons.upload_file),
                    tooltip: "Importar varios XML de facturas",
                    onPressed: _importarVariosXml,
                  ),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
                  BotonGuia(iniciar: _mostrarGuia),
                ],
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textStrong,
            unselectedLabelColor: AppColors.textMuted,
            tabs: const [
              Tab(icon: Icon(Icons.receipt_long), text: "Historial"),
              Tab(icon: Icon(Icons.local_shipping_outlined), text: "Proveedores"),
              Tab(icon: Icon(Icons.assignment_outlined), text: "Órdenes"),
            ],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildHistorial(),
                  _buildProveedores(),
                  OrdenesCompraTab(negocio: widget.negocio),
                ],
              ),
        floatingActionButton: Builder(
          builder: (ctx) {
            if (_modoSeleccion) return const SizedBox.shrink();
            final tabIndex = DefaultTabController.of(ctx).index;
            // Órdenes trae su propio botón.
            if (tabIndex == 2) return const SizedBox.shrink();
            if (tabIndex == 1) {
              return FloatingActionButton.extended(
                heroTag: 'fab_proveedores',
                onPressed: () => _mostrarFormularioProveedor(),
                icon: const Icon(Icons.add),
                label: const Text("NUEVO PROVEEDOR"),
                backgroundColor: AppColors.primary,
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fab_importar_compras',
                  onPressed: () => importarArchivoExterno(
                    context: context,
                    negocio: widget.negocio,
                    endpoint: '/compras/importar-externo/',
                    tipoLabel: 'compras',
                    onImportado: _cargarDatos,
                  ),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text("Importar archivo"),
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textStrong,
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  key: GuiaCompras.nueva,
                  heroTag: 'fab_compras',
                  onPressed: _abrirNuevaCompra,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text("NUEVA COMPRA"),
                  backgroundColor: AppColors.primary,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _mostrarGuia() => GuiaCompras.mostrar(context, cedulaNegocio: widget.negocio.cedula);

  Widget _buildCorreosPendientes() {
    return Container(
      key: GuiaCompras.porRevisar,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${_correosPendientes.length} factura${_correosPendientes.length == 1 ? '' : 's'} de proveedor por revisar",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_correosPendientes.any((c) => correoAceptable(c)))
                TextButton(
                  onPressed: _progresoLote != null
                      ? null
                      : () => setState(() {
                            final aceptables = _correosPendientes.where((c) => correoAceptable(c)).map<int>((c) => c['id'] as int);
                            if (aceptables.every(_correosSeleccionados.contains)) {
                              _correosSeleccionados.clear();
                            } else {
                              _correosSeleccionados.addAll(aceptables);
                            }
                          }),
                  child: Text(_correosPendientes.where((c) => correoAceptable(c)).every((c) => _correosSeleccionados.contains(c['id']))
                      ? "Quitar selección"
                      : "Seleccionar todas"),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "Llegaron al correo de facturas de compra. Revisalas una por una o marcá varias y aceptalas de una vez.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ..._correosPendientes.map((correo) {
            final tieneError = (correo['error'] ?? '').toString().isNotEmpty;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: tieneError
                    ? const Icon(Icons.error_outline, color: Colors.red)
                    : Checkbox(
                        value: _correosSeleccionados.contains(correo['id']),
                        onChanged: _progresoLote != null
                            ? null
                            : (v) => setState(() => v == true
                                ? _correosSeleccionados.add(correo['id'] as int)
                                : _correosSeleccionados.remove(correo['id'])),
                      ),
                title: Text(correo['remitente']?.toString().isNotEmpty == true ? correo['remitente'].toString() : "Remitente desconocido"),
                subtitle: Text(
                  tieneError
                      ? correo['error'].toString()
                      : [
                          correo['asunto']?.toString() ?? '',
                          // Si la aceptación automática está encendida y esta no
                          // cumplió las condiciones, se dice por qué quedó acá.
                          if ((correo['datos_parseados'] as Map?)?['aceptacion_automatica'] is Map)
                            "${(correo['datos_parseados']['aceptacion_automatica'] as Map)['en_lote'] == true ? 'No se pudo aceptar' : 'No se aceptó sola'}: "
                                "${(correo['datos_parseados']['aceptacion_automatica'] as Map)['detalle']}",
                        ].join('\n'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!tieneError)
                      TextButton(
                        onPressed: () => _revisarCorreoPendiente(correo),
                        child: const Text("Revisar"),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: "Descartar",
                      onPressed: () => _descartarCorreoPendiente(correo),
                    ),
                  ],
                ),
                onTap: tieneError ? null : () => _revisarCorreoPendiente(correo),
              ),
            );
          }),
          if (_progresoLote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(_progresoLote!),
              ]),
            )
          else if (_correosSeleccionados.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _aceptarCorreosEnLote,
                icon: const Icon(Icons.done_all),
                label: Text("Aceptar seleccionadas (${_correosSeleccionados.length})"),
              ),
            ),
        ],
      ),
    );
  }

  String _textoEstadoMensajeReceptor(Compra c) {
    switch (c.mensajeReceptorEstado) {
      case 'ENVIADO':
        return "Mensaje Receptor enviado a Hacienda";
      case 'ACEPTADO':
        return "Aceptado por Hacienda";
      case 'RECHAZADO':
        return "Rechazado por Hacienda";
      case 'ERROR':
        return "Error al enviar el Mensaje Receptor";
      default:
        return "Pendiente de responder a Hacienda";
    }
  }

  /// Abre el diálogo para mandarle a Hacienda el Mensaje Receptor de esta
  /// compra -- la confirmación OFICIAL de aceptación/rechazo del
  /// comprobante del proveedor, separada de simplemente tenerla registrada
  /// en la contabilidad. Solo aparece si la compra vino de un XML real
  /// (c.claveHacienda != null, ver FormularioCompra/CorreoCompraRecibido).
  Future<void> _abrirMensajeReceptor(Compra c) async {
    String tipo = '1';
    final detalleCtrl = TextEditingController();
    bool enviando = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Mensaje Receptor a Hacienda"),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Es la respuesta OFICIAL ante Hacienda sobre la factura de ${c.nombreProveedor ?? 'este proveedor'} "
                    "(${formatearColones(c.totalCompra)}) -- una vez enviada, queda registrada como una declaración tributaria real. "
                    "No se puede deshacer.",
                    style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  if (c.mensajeReceptorEstado != null) ...[
                    const SizedBox(height: 10),
                    Text("Estado actual: ${_textoEstadoMensajeReceptor(c)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 14),
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Aceptar"),
                    value: '1',
                    groupValue: tipo,
                    onChanged: enviando ? null : (v) => setStateDialog(() => tipo = v!),
                  ),
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Aceptar parcialmente"),
                    value: '2',
                    groupValue: tipo,
                    onChanged: enviando ? null : (v) => setStateDialog(() => tipo = v!),
                  ),
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Rechazar"),
                    value: '3',
                    groupValue: tipo,
                    onChanged: enviando ? null : (v) => setStateDialog(() => tipo = v!),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detalleCtrl,
                    enabled: !enviando,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: "Detalle (opcional)", border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: enviando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: enviando
                  ? null
                  : () async {
                      setStateDialog(() => enviando = true);
                      try {
                        final res = await ApiService.post('/compras/${c.id}/mensaje-receptor/', {
                          'tipo': tipo,
                          'detalle': detalleCtrl.text.trim(),
                        });
                        if (res.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _cargarDatos();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Mensaje Receptor enviado a Hacienda. Consultando la respuesta...")),
                            );
                          }
                          // Hacienda lo procesa en unos segundos.
                          await Future.delayed(const Duration(seconds: 6));
                          await _consultarMensajeReceptorManual(c);
                        } else {
                          final error = json.decode(utf8.decode(res.bodyBytes))['detail'] ?? 'Error desconocido';
                          setStateDialog(() => enviando = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error.toString())));
                          }
                        }
                      } catch (e) {
                        setStateDialog(() => enviando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
                        }
                      }
                    },
              child: enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Mandar a Hacienda"),
            ),
          ],
        ),
      ),
    );
  }

  /// Pregunta a Hacienda cómo terminó el Mensaje Receptor de una compra
  /// (ENVIADO -> ACEPTADO/RECHAZADO) y actualiza la fila. Devuelve la
  /// compra actualizada, o null si Hacienda no respondió.
  Future<Compra?> _consultarMensajeReceptor(Compra c) async {
    try {
      final res = await ApiService.post('/compras/${c.id}/consultar-mensaje-receptor/', {});
      if (res.statusCode != 200) return null;
      final actualizada = Compra.fromJson(json.decode(utf8.decode(res.bodyBytes)));
      if (mounted) {
        setState(() {
          final i = _compras.indexWhere((x) => x.id == actualizada.id);
          if (i >= 0) _compras[i] = actualizada;
        });
      }
      return actualizada;
    } catch (_) {
      return null;
    }
  }

  /// Sin esto el Mensaje Receptor quedaba "Enviado" para siempre: nadie le
  /// volvía a preguntar a Hacienda. Se hace en segundo plano al cargar.
  Future<void> _consultarMensajesEnviados() async {
    for (final c in _compras.where((c) => c.mensajeReceptorEstado == 'ENVIADO').toList()) {
      if (!mounted) return;
      await _consultarMensajeReceptor(c);
    }
    for (final c in _compras.where((c) => c.fecEstado == 'ENVIADO').toList()) {
      if (!mounted) return;
      await _consultarFec(c, avisar: false);
    }
  }

  Future<void> _consultarMensajeReceptorManual(Compra c) async {
    final actualizada = await _consultarMensajeReceptor(c);
    if (!mounted) return;
    final texto = actualizada == null
        ? "No se pudo consultar a Hacienda. Intentá de nuevo en un momento."
        : actualizada.mensajeReceptorEstado == 'ENVIADO'
            ? "Hacienda todavía lo está procesando. Intentá de nuevo en unos minutos."
            : _textoEstadoMensajeReceptor(actualizada);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Factura Electrónica de Compra: el proveedor es del régimen
  /// simplificado y no da comprobante, así que el negocio lo emite.
  Future<void> _emitirFec(Compra c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Emitir factura de compra"),
        content: const Text(
          "Se va a generar, firmar y enviar a Hacienda una Factura Electrónica de Compra por esta compra, "
          "como respaldo de lo que le compraste a un proveedor del régimen simplificado.\n\n"
          "Usá esto solo si el proveedor NO te dio factura electrónica.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Emitir")),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      ApiService.verificar(await ApiService.post('/compras/${c.id}/emitir-fec/', {}));
      await _cargarDatos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Factura de compra enviada a Hacienda. Consultando la respuesta...")),
        );
      }
      await Future.delayed(const Duration(seconds: 6));
      await _consultarFec(c);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  Future<void> _consultarFec(Compra c, {bool avisar = true}) async {
    try {
      final res = await ApiService.post('/compras/${c.id}/consultar-fec/', {});
      if (res.statusCode != 200) throw Exception(ApiService.mensajeError(res));
      final actualizada = Compra.fromJson(json.decode(utf8.decode(res.bodyBytes)));
      if (!mounted) return;
      setState(() {
        final i = _compras.indexWhere((x) => x.id == actualizada.id);
        if (i >= 0) _compras[i] = actualizada;
      });
      if (avisar) {
        final texto = switch (actualizada.fecEstado) {
          'ACEPTADO' => "Factura de compra aceptada por Hacienda.",
          'RECHAZADO' => "Hacienda rechazó la factura de compra. Revisá los datos del proveedor.",
          'ERROR' => "Hubo un error con la factura de compra.",
          _ => "Hacienda todavía la está procesando. Intentá de nuevo en unos minutos.",
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
      }
    } catch (e) {
      if (avisar && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo consultar: ${ApiService.textoError(e)}")));
    }
  }

  /// En qué grupo del filtro cae una compra. Las que no tienen clave de
  /// Hacienda (tecleadas a mano, sin XML) no se le pueden responder a
  /// Hacienda, así que no cuentan como "pendientes".
  String? _grupoHacienda(Compra c) {
    // Compra a régimen simplificado: cuenta el estado de la FEC que emitió el negocio.
    if (c.fecEstado != null) {
      return switch (c.fecEstado) {
        'ACEPTADO' => 'aceptadas',
        'RECHAZADO' => 'rechazadas',
        _ => 'pendientes',
      };
    }
    switch (c.mensajeReceptorEstado) {
      case 'ACEPTADO':
        return c.mensajeReceptorTipo == '3' ? 'rechazadas' : 'aceptadas';
      case 'RECHAZADO':
        return 'rechazadas';
      default:
        return c.claveHacienda != null ? 'pendientes' : null;
    }
  }

  List<Compra> get _comprasFiltradas => _filtroHacienda == 'todas'
      ? _compras
      : _compras.where((c) => _grupoHacienda(c) == _filtroHacienda).toList();

  Widget _buildFiltroHacienda() {
    final opciones = [
      ('todas', 'Todas', _compras.length),
      ('aceptadas', 'Aceptadas', _compras.where((c) => _grupoHacienda(c) == 'aceptadas').length),
      ('pendientes', 'Pendientes', _compras.where((c) => _grupoHacienda(c) == 'pendientes').length),
      ('rechazadas', 'Rechazadas', _compras.where((c) => _grupoHacienda(c) == 'rechazadas').length),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (valor, texto, cantidad) in opciones)
            ChoiceChip(
              label: Text("$texto ($cantidad)"),
              selected: _filtroHacienda == valor,
              onSelected: (_) => setState(() {
                _filtroHacienda = valor;
                _comprasSeleccionadas.clear();
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildHistorial() {
    if (_compras.isEmpty && _correosPendientes.isEmpty) {
      return const Center(
        child: Text("Todavía no hay compras registradas.", style: TextStyle(color: Colors.grey)),
      );
    }
    final compras = _comprasFiltradas;
    final encabezados = <Widget>[
      if (_correosPendientes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildCorreosPendientes(),
        ),
      if (_compras.isNotEmpty) _buildFiltroHacienda(),
      if (_compras.isNotEmpty && compras.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text("No hay compras con ese estado.", style: TextStyle(color: Colors.grey))),
        ),
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: compras.length + encabezados.length,
      itemBuilder: (context, index) {
        if (index < encabezados.length) return encabezados[index];
        final c = compras[index - encabezados.length];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            leading: _modoSeleccion
                ? Checkbox(
                    value: _comprasSeleccionadas.contains(c.id),
                    onChanged: (_) => _alternarSeleccion(c.id),
                  )
                : CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Icon(Icons.arrow_downward, color: AppColors.primary),
                  ),
            onExpansionChanged: _modoSeleccion ? (_) => _alternarSeleccion(c.id) : null,
            title: Text(c.nombreProveedor ?? "Proveedor sin especificar", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              [
                if (c.numeroFacturaProveedor.isNotEmpty) "Factura: ${c.numeroFacturaProveedor}",
                "Total: ${formatearColones(c.totalCompra)}",
                if (c.moneda == 'USD')
                  "US\$${(c.totalCompra / c.tipoCambio).toStringAsFixed(2)} @ ₡${c.tipoCambio.toStringAsFixed(2)}",
                if (c.claveHacienda != null) _textoEstadoMensajeReceptor(c),
                if (c.fecEstado != null)
                  "Factura de compra: ${switch (c.fecEstado) {
                    'ACEPTADO' => 'aceptada por Hacienda',
                    'RECHAZADO' => 'rechazada por Hacienda',
                    'ERROR' => 'error al enviar',
                    _ => 'enviada, esperando respuesta',
                  }}",
              ].join(" · "),
            ),
            trailing: _modoSeleccion
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.comprobanteUrl != null && c.comprobanteUrl!.isNotEmpty)
                        Icon(Icons.attach_file, color: AppColors.primary),
                      PopupMenuButton<String>(
                        onSelected: (opcion) {
                          if (opcion == 'nota_debito') mostrarDialogoNotaDebito(context, c, onCreada: _cargarDatos);
                          if (opcion == 'mensaje_receptor') _abrirMensajeReceptor(c);
                          if (opcion == 'consultar_mensaje') _consultarMensajeReceptorManual(c);
                          if (opcion == 'emitir_fec') _emitirFec(c);
                          if (opcion == 'consultar_fec') _consultarFec(c);
                          if (opcion == 'borrar') _eliminarCompra(c);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'nota_debito', child: Text("Agregar Nota de Débito")),
                          if (c.claveHacienda != null)
                            PopupMenuItem(
                              value: 'mensaje_receptor',
                              child: Text(c.mensajeReceptorEstado == null ? "Responder a Hacienda" : "Ver / reenviar respuesta a Hacienda"),
                            ),
                          if (c.mensajeReceptorEstado == 'ENVIADO')
                            const PopupMenuItem(value: 'consultar_mensaje', child: Text("Consultar estado en Hacienda")),
                          if (c.claveHacienda == null && (c.fecEstado == null || c.fecEstado == 'ERROR' || c.fecEstado == 'RECHAZADO'))
                            const PopupMenuItem(value: 'emitir_fec', child: Text("Emitir factura de compra (régimen simplificado)")),
                          if (c.fecEstado == 'ENVIADO')
                            const PopupMenuItem(value: 'consultar_fec', child: Text("Consultar factura de compra en Hacienda")),
                          const PopupMenuItem(value: 'borrar', child: Text("Borrar compra")),
                        ],
                      ),
                    ],
                  ),
            children: [
              if (c.comprobanteUrl != null && c.comprobanteUrl!.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.description_outlined, color: AppColors.primary),
                  title: const Text("Ver comprobante adjunto"),
                  onTap: () => _abrirComprobante(c.comprobanteUrl!),
                ),
              ...c.detalles
                .map((d) => ListTile(
                      dense: true,
                      title: Text(d.nombreProducto),
                      trailing: Text("${formatearNumero(d.cantidad, decimales: 0)} x ${formatearColones(d.precioCosto)}"),
                    )),
              ...c.notasDebito.map((n) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.add_card, color: Colors.orange),
                    title: Text("Nota de Débito ${n.numeroDocumento}${n.motivo.isNotEmpty ? ' — ${n.motivo}' : ''}"),
                    trailing: Text("+${formatearColones(n.monto)}"),
                    onTap: n.comprobanteUrl != null && n.comprobanteUrl!.isNotEmpty
                        ? () => _abrirComprobante(n.comprobanteUrl!)
                        : null,
                  )),
            ],
          ),
        );
      },
    );
  }

  void _alternarSeleccion(int compraId) {
    setState(() {
      if (_comprasSeleccionadas.contains(compraId)) {
        _comprasSeleccionadas.remove(compraId);
      } else {
        _comprasSeleccionadas.add(compraId);
      }
    });
  }

  void _alternarSeleccionTodas() {
    setState(() {
      if (_comprasSeleccionadas.length == _comprasFiltradas.length) {
        _comprasSeleccionadas.clear();
      } else {
        _comprasSeleccionadas
          ..clear()
          ..addAll(_comprasFiltradas.map((c) => c.id));
      }
    });
  }

  void _salirModoSeleccion() {
    setState(() {
      _modoSeleccion = false;
      _comprasSeleccionadas.clear();
    });
  }

  Future<void> _borrarSeleccionadas() async {
    final cantidad = _comprasSeleccionadas.length;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar compras seleccionadas?"),
        content: Text(
          "Se eliminarán $cantidad ${cantidad == 1 ? 'compra' : 'compras'} y se revertirá el inventario "
          "que habían sumado. Las que tengan una Nota de Débito registrada no se podrán borrar.",
        ),
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

    final idsABorrar = _comprasSeleccionadas.toList();
    final List<String> fallidos = [];
    int procesados = 0;
    bool terminado = false;
    void Function(void Function())? refrescarDialogo;

    Future<void> procesarTodas() async {
      for (final id in idsABorrar) {
        try {
          final response = await ApiService.delete('/compras/$id/');
          if (response.statusCode != 204 && response.statusCode != 200) {
            final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'Error desconocido';
            fallidos.add("Compra #$id: $detalle");
          }
        } catch (e) {
          fallidos.add("Compra #$id: ${ApiService.textoError(e)}");
        }
        procesados++;
        refrescarDialogo?.call(() {});
      }
      terminado = true;
      refrescarDialogo?.call(() {});
    }

    procesarTodas();

    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) {
            refrescarDialogo = setStateDialog;
            return AlertDialog(
              title: const Text("Borrando compras"),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: idsABorrar.isEmpty ? 0 : procesados / idsABorrar.length),
                    const SizedBox(height: 16),
                    Text("$procesados de ${idsABorrar.length} procesadas"),
                  ],
                ),
              ),
              actions: [
                if (terminado)
                  ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
              ],
            );
          },
        ),
      );
    }

    _salirModoSeleccion();
    await _cargarDatos();
    if (mounted) {
      final resumen = "Borradas: ${idsABorrar.length - fallidos.length}${fallidos.isNotEmpty ? ' · No se pudieron borrar: ${fallidos.length}' : ''}";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resumen)));
      if (fallidos.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Compras que no se pudieron borrar"),
            content: SingleChildScrollView(child: Text(fallidos.join("\n"))),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
          ),
        );
      }
    }
  }

  Future<void> _eliminarCompra(Compra compra) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar compra?"),
        content: Text(
          "Se eliminará la compra a \"${compra.nombreProveedor ?? 'proveedor sin especificar'}\" "
          "y se revertirá el inventario que había sumado.",
        ),
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
      final response = await ApiService.delete('/compras/${compra.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarDatos();
      } else {
        final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? utf8.decode(response.bodyBytes);
        throw Exception(detalle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo borrar: ${ApiService.textoError(e)}")));
      }
    }
  }


  Widget _buildProveedores() {
    if (_proveedores.isEmpty) {
      return const Center(
        child: Text("Todavía no hay proveedores registrados.", style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _proveedores.length,
      itemBuilder: (context, index) {
        final p = _proveedores[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Icon(Icons.local_shipping_outlined, color: AppColors.primary),
            ),
            title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              [
                if (p.cedula != null && p.cedula!.isNotEmpty) "Cédula: ${p.cedula}",
                if (p.correo != null && p.correo!.isNotEmpty) p.correo!,
              ].join(" · "),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: "Editar",
                  onPressed: () => _mostrarFormularioProveedor(proveedorExistente: p),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: "Borrar",
                  onPressed: () => _eliminarProveedor(p),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
