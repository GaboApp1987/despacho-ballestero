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
import 'negocio.dart';
import 'formato.dart';

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
  List<Proveedor> _proveedores = [];
  bool _modoSeleccion = false;
  final Set<int> _comprasSeleccionadas = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final respuestas = await Future.wait([
        ApiService.get('/compras/?negocio=${widget.negocio.id}'),
        ApiService.get('/proveedores/?negocio=${widget.negocio.id}'),
      ]);
      if (!mounted) return;
      if (respuestas[0].statusCode == 200 && respuestas[1].statusCode == 200) {
        final List comprasData = json.decode(utf8.decode(respuestas[0].bodyBytes));
        final List proveedoresData = json.decode(utf8.decode(respuestas[1].bodyBytes));
        setState(() {
          _compras = comprasData.map((j) => Compra.fromJson(j)).toList();
          _proveedores = proveedoresData.map((j) => Proveedor.fromJson(j)).toList();
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar compras: $e")));
    }
  }

  Future<void> _abrirNuevaCompra() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => FormularioCompra(negocio: widget.negocio)),
    );
    if (resultado == true) _cargarDatos();
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

    final archivos = resultado.files.where((f) => f.bytes != null).toList();
    final List<String> exitosos = [];
    final List<String> fallidos = [];
    // Estos viven FUERA del builder del diálogo a propósito: si estuvieran
    // declarados dentro de StatefulBuilder.builder, cada setState los
    // reiniciaría a su valor inicial (por eso el contador se quedaba en 0).
    int procesados = 0;
    bool terminado = false;
    void Function(void Function())? refrescarDialogo;

    Future<void> procesarTodos() async {
      for (final archivo in archivos) {
        try {
          await _importarUnXml(archivo.bytes!, archivo.name);
          exitosos.add(archivo.name);
        } catch (e) {
          fallidos.add("${archivo.name}: $e");
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
      final resumen = "Importadas: ${exitosos.length}${fallidos.isNotEmpty ? ' · Con error: ${fallidos.length}' : ''}";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resumen)));
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
  Future<void> _importarUnXml(Uint8List bytes, String nombreArchivo) async {
    final response = await ApiService.postMultipartBytes(
      '/compras/leer-xml/',
      {'negocio': widget.negocio.id.toString()},
      'archivo',
      bytes,
      nombreArchivo,
    );
    if (response.statusCode != 200) {
      throw Exception(utf8.decode(response.bodyBytes));
    }
    final datos = json.decode(utf8.decode(response.bodyBytes));

    int? proveedorId = datos['proveedor_id'];
    if (proveedorId == null && datos['proveedor_nombre'] != null) {
      final resProv = await ApiService.post('/proveedores/', {
        'negocio': widget.negocio.id,
        'nombre': datos['proveedor_nombre'],
        'cedula_juridica': datos['proveedor_cedula'] ?? '',
        'correo': datos['proveedor_correo'] ?? '',
      });
      if (resProv.statusCode != 201) throw Exception("No se pudo crear el proveedor");
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
      final precio = redondear2((linea['precio_unitario'] as num?) ?? 0);
      if (productoId == null) {
        final resProd = await ApiService.post('/productos/', {
          'negocio': widget.negocio.id,
          'nombre': linea['detalle'] ?? 'Producto sin nombre',
          'codigo_cabys': linea['codigo_cabys'] ?? '',
          'unidad_medida': 'Unid',
          'precio_unitario': precio,
          'stock': 0,
        });
        if (resProd.statusCode != 201) throw Exception("No se pudo crear el producto '${linea['detalle']}'");
        productoId = json.decode(utf8.decode(resProd.bodyBytes))['id'];
      }
      detallesCompra.add({'producto': productoId, 'cantidad': cantidad.toInt(), 'precio_costo': precio});
      total += precio * cantidad;
    }

    final resCompra = await ApiService.post('/compras/', {
      'negocio': widget.negocio.id,
      'proveedor': proveedorId,
      'numero_factura_proveedor': datos['numero_factura'] ?? datos['clave'] ?? '',
      'total_compra': redondear2(datos['total_comprobante'] ?? total),
      'detalles_compra': detallesCompra,
    });
    if (resCompra.statusCode != 201) throw Exception("No se pudo crear la compra");

    final compraId = json.decode(utf8.decode(resCompra.bodyBytes))['id'];
    await ApiService.uploadBytes('/compras/$compraId/', 'comprobante', bytes, nombreArchivo);
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
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: "Nombre / Razón Social *", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cedulaCtrl,
                  decoration: const InputDecoration(labelText: "Cédula Jurídica (Opcional)", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: correoCtrl,
                  decoration: const InputDecoration(labelText: "Correo (Opcional)", border: OutlineInputBorder()),
                ),
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
                      };
                      try {
                        final response = proveedorExistente == null
                            ? await ApiService.post('/proveedores/', body)
                            : await ApiService.patch('/proveedores/${proveedorExistente.id}/', body);
                        if (response.statusCode == 200 || response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarDatos();
                        } else {
                          throw Exception(utf8.decode(response.bodyBytes));
                        }
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error: $e")));
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
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al borrar: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
                    icon: Icon(_comprasSeleccionadas.length == _compras.length ? Icons.deselect : Icons.select_all),
                    tooltip: _comprasSeleccionadas.length == _compras.length ? "Deseleccionar todas" : "Seleccionar todas",
                    onPressed: _alternarSeleccionTodas,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: "Borrar seleccionadas",
                    onPressed: _comprasSeleccionadas.isEmpty ? null : _borrarSeleccionadas,
                  ),
                ]
              : [
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    tooltip: "Seleccionar varias para borrar",
                    onPressed: () => setState(() => _modoSeleccion = true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file),
                    tooltip: "Importar varios XML de facturas",
                    onPressed: _importarVariosXml,
                  ),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
                ],
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textStrong,
            unselectedLabelColor: AppColors.textMuted,
            tabs: const [
              Tab(icon: Icon(Icons.receipt_long), text: "Historial"),
              Tab(icon: Icon(Icons.local_shipping_outlined), text: "Proveedores"),
            ],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildHistorial(),
                  _buildProveedores(),
                ],
              ),
        floatingActionButton: Builder(
          builder: (ctx) {
            if (_modoSeleccion) return const SizedBox.shrink();
            final tabIndex = DefaultTabController.of(ctx).index;
            if (tabIndex == 1) {
              return FloatingActionButton.extended(
                heroTag: 'fab_proveedores',
                onPressed: () => _mostrarFormularioProveedor(),
                icon: const Icon(Icons.add),
                label: const Text("NUEVO PROVEEDOR"),
                backgroundColor: AppColors.primary,
              );
            }
            return FloatingActionButton.extended(
              heroTag: 'fab_compras',
              onPressed: _abrirNuevaCompra,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text("NUEVA COMPRA"),
              backgroundColor: AppColors.primary,
            );
          },
        ),
      ),
    );
  }

  Widget _buildHistorial() {
    if (_compras.isEmpty) {
      return const Center(
        child: Text("Todavía no hay compras registradas.", style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _compras.length,
      itemBuilder: (context, index) {
        final c = _compras[index];
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
                          if (opcion == 'nota_debito') _mostrarDialogoNotaDebito(c);
                          if (opcion == 'borrar') _eliminarCompra(c);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'nota_debito', child: Text("Agregar Nota de Débito")),
                          PopupMenuItem(value: 'borrar', child: Text("Borrar compra")),
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
      if (_comprasSeleccionadas.length == _compras.length) {
        _comprasSeleccionadas.clear();
      } else {
        _comprasSeleccionadas
          ..clear()
          ..addAll(_compras.map((c) => c.id));
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
          fallidos.add("Compra #$id: $e");
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo borrar: $e")));
      }
    }
  }

  Future<void> _mostrarDialogoNotaDebito(Compra compra) async {
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
                          _cargarDatos();
                        } else {
                          throw Exception(utf8.decode(response.bodyBytes));
                        }
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error: $e")));
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
