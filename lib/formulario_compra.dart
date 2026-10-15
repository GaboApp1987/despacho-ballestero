import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'impuesto.dart';
import 'negocio.dart';
import 'ordenes_compra.dart';
import 'recorridos.dart';
import 'widgets/recorrido_guiado.dart';
import 'producto.dart';
import 'formato.dart';
import 'widgets/campo_cedula_hacienda.dart';

class FormularioCompra extends StatefulWidget {
  final Negocio negocio;
  // Si esta compra se abre a partir de un correo que llegó solo al buzón de
  // facturas de compra del negocio (ver CorreoCompraRecibido), estos dos
  // vienen con datos: los datos ya parseados del XML (misma forma que
  // devuelve /compras/leer-xml/) y el id del correo, para poder descartarlo
  // de la lista de pendientes una vez que la compra se guarda de verdad.
  final Map<String, dynamic>? datosPrecarga;
  final int? correoId;
  // Abierta desde una orden de compra: queda ligada y precarga lo pendiente.
  final int? ordenId;
  const FormularioCompra({super.key, required this.negocio, this.datosPrecarga, this.correoId, this.ordenId});

  @override
  State<FormularioCompra> createState() => _FormularioCompraState();
}

class _FormularioCompraState extends State<FormularioCompra> {
  final TextEditingController _facturaProveedorController = TextEditingController();
  List<Proveedor> _listaProveedores = [];
  List<Producto> _listaProductos = [];
  List<InsumoCompra> _listaInsumos = [];
  final List<LineaCompra> _carritoCompra = [];
  InsumoCompra? _insumoSeleccionado;

  Proveedor? _proveedorSeleccionado;
  Producto? _productoSeleccionado;
  // Órdenes de compra abiertas del negocio y la que esta factura cumple
  // (ver ordenes_compra.dart): con ella se comparan cantidades y precios.
  List<OrdenCompra> _ordenesAbiertas = [];
  OrdenCompra? _orden;
  String _condicionCompra = "01"; // "01" = Contado, "02" = Crédito
  // Antes esta compra siempre se guardaba con la fecha de HOY, sin importar
  // que el XML/foto/factura del proveedor fuera de otro día -- ahora se
  // precarga con la fecha real leída (ver _aplicarDatosParseados) y queda
  // editable, con hoy como default cuando no se pudo leer ninguna.
  DateTime _fecha = DateTime.now();
  List<Impuesto> _listaImpuestos = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _procesandoXml = false;
  Uint8List? _bytesComprobante;
  String? _nombreComprobante;
  // Clave de 50 dígitos del comprobante electrónico del proveedor (solo
  // presente si esta compra vino de un XML real): se guarda para poder
  // mandarle después a Hacienda el Mensaje Receptor de esta compra.
  String? _claveHacienda;
  // Si la compra trae clave de Hacienda (vino de un XML), al confirmarla se
  // manda de una vez el Mensaje Receptor de aceptación -- antes había que
  // hacerlo aparte desde el Historial y se olvidaba.
  bool _aceptarEnHacienda = true;
  // Si lo que suman las líneas leídas no cuadra con el total del
  // comprobante (ver verificar_cuadre_lineas en el backend), probablemente
  // la IA leyó mal un precio en el PDF/foto -- se avisa acá para que se
  // revise ANTES de guardar, en vez de notarlo después en los reportes.
  Map<String, dynamic>? _avisoCuadre;
  // Si el comprobante venía en dólares, todo el carrito ya se convirtió a
  // colones con este tipo de cambio (ver _aplicarDatosParseados) -- queda
  // editable por si el que trae el XML/foto no es el que se quiere usar.
  String _moneda = 'CRC';
  final TextEditingController _tipoCambioController = TextEditingController(text: '1.00');

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

  Future<void> _elegirComprobante() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'xml'],
      withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
    );
    if (resultado == null || resultado.files.single.bytes == null) return;
    final bytes = resultado.files.single.bytes!;
    final nombre = resultado.files.single.name;
    setState(() {
      _bytesComprobante = bytes;
      _nombreComprobante = nombre;
    });
    // XML: se lee exacto, sin IA. PDF/foto: la mayoría de proveedores
    // pequeños no facturan electrónicamente y solo dan un recibo en PDF o
    // una foto -- se le pide a Claude que lo lea (ver leer_xml en el
    // backend, que ahora acepta ambos formatos y decide según el archivo).
    final esLeible = nombre.toLowerCase().endsWith('.xml') ||
        nombre.toLowerCase().endsWith('.pdf') ||
        nombre.toLowerCase().endsWith('.jpg') ||
        nombre.toLowerCase().endsWith('.jpeg') ||
        nombre.toLowerCase().endsWith('.png');
    if (esLeible) {
      await _leerXmlProveedor(bytes, nombre);
    }
  }

  /// Lee el comprobante del proveedor y precarga proveedor, número de
  /// factura y las líneas de producto -- un XML de Hacienda se lee exacto;
  /// un PDF o foto de un recibo común se lee con IA (ver leer_xml en el
  /// backend).
  Future<void> _leerXmlProveedor(Uint8List bytes, String nombreArchivo) async {
    setState(() => _procesandoXml = true);
    try {
      final response = await ApiService.postMultipartBytes(
        '/compras/leer-xml/',
        {'negocio': widget.negocio.id.toString()},
        'archivo',
        bytes,
        nombreArchivo,
      );
      if (response.statusCode != 200) {
        // Ej. una nota de crédito: el servidor explica qué es y qué hacer.
        final motivo = ApiService.mensajeError(response);
        if (mounted) {
          setState(() {
            _bytesComprobante = null;
            _nombreComprobante = null;
          });
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Este archivo no es una factura de compra"),
              content: Text(motivo),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendido"))],
            ),
          );
        }
        return;
      }
      await _aplicarDatosParseados(json.decode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo leer el archivo: ${ApiService.textoError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoXml = false);
    }
  }

  /// Misma precarga que _leerXmlProveedor, pero a partir de datos YA
  /// parseados -- usado tanto ahí como al abrir esta pantalla desde un
  /// CorreoCompraRecibido (factura que llegó sola por correo al buzón del
  /// negocio, ver widget.datosPrecarga).
  Future<void> _aplicarDatosParseados(Map datos) async {
    try {
      _facturaProveedorController.text = datos['numero_factura'] ?? datos['clave'] ?? '';
      if ((datos['clave'] as String?)?.isNotEmpty == true) {
        _claveHacienda = datos['clave'] as String;
      }
      final cuadre = datos['cuadre'] as Map?;
      setState(() => _avisoCuadre = (cuadre != null && cuadre['cuadra'] != true) ? Map<String, dynamic>.from(cuadre) : null);
      final fechaLeida = datos['fecha'] as String?;
      if (fechaLeida != null && fechaLeida.isNotEmpty) {
        final parseada = DateTime.tryParse(fechaLeida);
        if (parseada != null) setState(() => _fecha = parseada);
      }

      // Si el proveedor facturó en dólares, se convierte todo a colones acá
      // (con el tipo de cambio que trae el comprobante, o si no, el del día
      // según el BCCR) para que el resto de la app -- que siempre trabaja en
      // colones -- no tenga que distinguir monedas en ningún otro lado.
      double tipoCambioAplicar = 1.0;
      if ((datos['moneda'] as String?)?.toUpperCase() == 'USD') {
        final tcExtraido = (datos['tipo_cambio'] as num?)?.toDouble();
        tipoCambioAplicar = (tcExtraido != null && tcExtraido > 0) ? tcExtraido : await _obtenerTipoCambioDelDia();
        setState(() {
          _moneda = 'USD';
          _tipoCambioController.text = tipoCambioAplicar.toStringAsFixed(2);
        });
      }

      // Proveedor: si ya existe (por cédula) se selecciona; si no, se crea
      // automáticamente con los datos del XML.
      // Se busca por id (si el backend ya lo reconoció) o por cédula en la
      // lista actual (pudo crearse después de que llegó el correo). OJO: acá
      // nunca se llama a _cargarDatos() -- con datosPrecarga eso vuelve a
      // ejecutar esta misma precarga y creaba el proveedor en bucle.
      final proveedorId = datos['proveedor_id'];
      final cedulaProveedor = (datos['proveedor_cedula'] ?? '').toString().trim();
      Proveedor? encontrado;
      for (final p in _listaProveedores) {
        if ((proveedorId != null && p.id == proveedorId) ||
            (cedulaProveedor.isNotEmpty && (p.cedula ?? '').trim() == cedulaProveedor)) {
          encontrado = p;
          break;
        }
      }
      if (encontrado != null) {
        setState(() => _proveedorSeleccionado = encontrado);
      } else if (datos['proveedor_nombre'] != null) {
        final resProv = await ApiService.post('/proveedores/', {
          'negocio': widget.negocio.id,
          'nombre': datos['proveedor_nombre'],
          'cedula_juridica': cedulaProveedor,
          'correo': datos['proveedor_correo'] ?? '',
        });
        // 201 = creado; 200 = ya existía con esa cédula (el backend no duplica).
        if (resProv.statusCode == 201 || resProv.statusCode == 200) {
          final proveedor = Proveedor.fromJson(json.decode(utf8.decode(resProv.bodyBytes)));
          if (mounted) {
            setState(() {
              if (!_listaProveedores.any((p) => p.id == proveedor.id)) _listaProveedores.add(proveedor);
              _proveedorSeleccionado = _listaProveedores.firstWhere((p) => p.id == proveedor.id);
            });
            if (resProv.statusCode == 201) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Proveedor agregado automáticamente: ${datos['proveedor_nombre']}")),
              );
            }
          }
        }
      }

      // Líneas de producto: las que ya coinciden por CABYS se agregan
      // directo; las que no, piden vincular o crear un producto.
      // El producto_id de un CorreoCompraRecibido se calculó cuando llegó el
      // correo: si el producto se creó después (p. ej. al revisarlo una vez
      // antes), venía null y pedía vincular de nuevo en cada "Revisar" --
      // por eso también se busca por CABYS en la lista actual.
      final List lineas = datos['lineas'] ?? [];
      for (final linea in lineas) {
        final productoId = linea['producto_id'];
        final cabysLinea = (linea['codigo_cabys'] as String? ?? '').trim();
        Producto? producto;
        for (final p in _listaProductos) {
          if ((productoId != null && p.id == productoId) ||
              (cabysLinea.isNotEmpty && p.codigoCabys.trim() == cabysLinea)) {
            producto = p;
            break;
          }
        }
        if (producto != null && (linea['cantidad'] as num) % 1 == 0) {
          final productoLinea = producto;
          setState(() {
            _carritoCompra.add(LineaCompra(
              producto: productoLinea,
              cantidad: (linea['cantidad'] as num).toDouble(),
              precioCosto: redondear2((linea['precio_unitario'] as num) * tipoCambioAplicar),
              tarifa: (linea['tarifa'] as num?)?.toDouble() ?? productoLinea.impuesto?.porcentaje,
              descripcion: (linea['detalle'] ?? '').toString(),
            ));
          });
        } else if (mounted) {
          await _resolverLineaSinProducto(linea, tipoCambio: tipoCambioAplicar);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al precargar los datos: ${ApiService.textoError(e)}")),
        );
      }
    }
  }

  /// Cuando una línea del XML no coincide con ningún producto ya registrado
  /// (por CABYS), se pide vincularla a uno existente o crear uno nuevo.
  /// [tipoCambio] ya viene aplicado sobre el precio si el comprobante venía
  /// en dólares (ver _aplicarDatosParseados) -- acá se recibe listo en colones.
  Future<void> _resolverLineaSinProducto(Map linea, {double tipoCambio = 1.0}) async {
    final cabys = linea['codigo_cabys'] as String? ?? '';
    final detalle = linea['detalle'] as String? ?? 'Producto sin nombre';
    final cantidad = ((linea['cantidad'] as num?) ?? 1).toDouble();
    final precio = ((linea['precio_unitario'] as num?) ?? 0).toDouble() * tipoCambio;
    final tarifaLinea = (linea['tarifa'] as num?)?.toDouble();

    // Materia prima (papa, aceite...) va como insumo: suma existencias con
    // decimales y su costo promedio, sin digitarlo dos veces.
    bool comoInsumo = cantidad % 1 != 0;
    InsumoCompra? insumoExistente;
    String unidadNueva = 'kg';
    Producto? productoExistente;
    final nombreCtrl = TextEditingController(text: detalle);
    final cabysCtrl = TextEditingController(text: cabys);
    final precioCtrl = TextEditingController(text: precio.toString());
    // Precargado con la tarifa que trae el XML/foto (<Impuesto><Tarifa> o lo
    // que Claude haya leído) -- sigue editable, solo ahorra tener que
    // buscarlo a mano cuando ya viene en el comprobante.
    Impuesto? impuestoSeleccionado = tarifaLinea == null
        ? null
        : _listaImpuestos.cast<Impuesto?>().firstWhere(
            (i) => i != null && (i.porcentaje - tarifaLinea).abs() < 0.01,
            orElse: () => null,
          );
    bool guardando = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Vincular: $detalle"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("CABYS del XML: ${cabys.isNotEmpty ? cabys : '(no incluido)'}",
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text("Producto (mercadería)")),
                      ButtonSegment(value: true, label: Text("Insumo (materia prima)")),
                    ],
                    selected: {comoInsumo},
                    onSelectionChanged: (v) => setStateDialog(() => comoInsumo = v.first),
                  ),
                  const SizedBox(height: 10),
                  if (comoInsumo) ...[
                    DropdownButtonFormField<InsumoCompra?>(
                      value: insumoExistente,
                      decoration: const InputDecoration(labelText: "Insumo", border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<InsumoCompra?>(value: null, child: Text("Crear insumo nuevo")),
                        ..._listaInsumos.map((i) => DropdownMenuItem<InsumoCompra?>(value: i, child: Text("${i.nombre} (${i.unidadTexto})"))),
                      ],
                      onChanged: (v) => setStateDialog(() => insumoExistente = v),
                    ),
                    if (insumoExistente == null) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(labelText: "Nombre del insumo", border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: unidadNueva,
                        decoration: const InputDecoration(labelText: "Se mide en", border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
                          DropdownMenuItem(value: 'g', child: Text('g')),
                          DropdownMenuItem(value: 'l', child: Text('litros')),
                          DropdownMenuItem(value: 'ml', child: Text('ml')),
                          DropdownMenuItem(value: 'unid', child: Text('unidades')),
                        ],
                        onChanged: (v) => setStateDialog(() => unidadNueva = v ?? 'kg'),
                      ),
                    ],
                  ] else
                  DropdownButtonFormField<Producto?>(
                    value: productoExistente,
                    decoration: const InputDecoration(labelText: "Vincular a producto existente", border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<Producto?>(value: null, child: Text("Crear producto nuevo")),
                      ..._listaProductos.map((p) => DropdownMenuItem<Producto?>(value: p, child: Text(p.nombre))),
                    ],
                    onChanged: (v) => setStateDialog(() => productoExistente = v),
                  ),
                  if (!comoInsumo && productoExistente == null) ...[
                    const Divider(height: 24),
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(labelText: "Nombre del producto nuevo", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: cabysCtrl,
                      decoration: const InputDecoration(labelText: "Código CABYS", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<Impuesto>(
                      value: impuestoSeleccionado,
                      decoration: const InputDecoration(labelText: "Impuesto (opcional)", border: OutlineInputBorder()),
                      items: _listaImpuestos.map((i) => DropdownMenuItem(value: i, child: Text(i.toString()))).toList(),
                      onChanged: (v) => setStateDialog(() => impuestoSeleccionado = v),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: precioCtrl,
                    decoration: const InputDecoration(labelText: "Precio de costo (₡)", border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Omitir esta línea")),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      setStateDialog(() => guardando = true);
                      if (comoInsumo) {
                        InsumoCompra? insumoFinal = insumoExistente;
                        if (insumoFinal == null) {
                          if (nombreCtrl.text.trim().isEmpty) {
                            setStateDialog(() => guardando = false);
                            return;
                          }
                          final res = await ApiService.post('/insumos/', {
                            'negocio': widget.negocio.id,
                            'nombre': nombreCtrl.text.trim(),
                            'unidad': unidadNueva,
                            'codigo_cabys': cabys,
                          });
                          if (res.statusCode != 201) {
                            setStateDialog(() => guardando = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("No se pudo crear el insumo: ${ApiService.mensajeError(res)}")));
                            }
                            return;
                          }
                          insumoFinal = InsumoCompra.fromJson(json.decode(utf8.decode(res.bodyBytes)));
                          setState(() => _listaInsumos.add(insumoFinal!));
                        }
                        setState(() {
                          _carritoCompra.add(LineaCompra(
                            insumo: insumoFinal,
                            cantidad: cantidad,
                            precioCosto: redondear2(double.tryParse(precioCtrl.text.trim()) ?? precio),
                            tarifa: tarifaLinea,
                            descripcion: detalle,
                          ));
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        return;
                      }
                      Producto? productoFinal = productoExistente;
                      if (productoFinal == null) {
                        if (nombreCtrl.text.trim().isEmpty) {
                          setStateDialog(() => guardando = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Ingrese el nombre del producto.")));
                          return;
                        }
                        final res = await ApiService.post('/productos/', {
                          'negocio': widget.negocio.id,
                          'nombre': nombreCtrl.text.trim(),
                          'codigo_cabys': cabysCtrl.text.trim(),
                          'unidad_medida': 'Unid',
                          'precio_unitario': redondear2(double.tryParse(precioCtrl.text.trim()) ?? 0),
                          'stock': 0,
                          'impuesto': impuestoSeleccionado?.id,
                        });
                        if (res.statusCode == 201) {
                          final nuevo = json.decode(utf8.decode(res.bodyBytes));
                          productoFinal = Producto.fromJson(nuevo);
                          setState(() => _listaProductos.add(productoFinal!));
                        } else {
                          setStateDialog(() => guardando = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error al crear el producto: ${utf8.decode(res.bodyBytes)}")));
                          }
                          return;
                        }
                      }
                      setState(() {
                        _carritoCompra.add(LineaCompra(
                          producto: productoFinal!,
                          cantidad: cantidad.roundToDouble(),
                          precioCosto: redondear2(double.tryParse(precioCtrl.text.trim()) ?? precio),
                          tarifa: tarifaLinea ?? productoFinal.impuesto?.porcentaje,
                          descripcion: detalle,
                        ));
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: guardando
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Agregar a la compra"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _facturaProveedorController.dispose();
    _tipoCambioController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    try {
      final responses = await Future.wait([
        ApiService.get('/proveedores/?negocio=${widget.negocio.id}'),
        ApiService.get('/productos/?negocio=${widget.negocio.id}'),
        ApiService.get('/impuestos/'),
        ApiService.get('/insumos/?negocio=${widget.negocio.id}'),
        ApiService.get('/ordenes-compra/?negocio=${widget.negocio.id}&abiertas=true'),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final proveedoresData = json.decode(utf8.decode(responses[0].bodyBytes)) as List;
        final productosData = json.decode(utf8.decode(responses[1].bodyBytes)) as List;
        final impuestosData = responses[2].statusCode == 200
            ? json.decode(utf8.decode(responses[2].bodyBytes)) as List
            : [];

        if (mounted) {
          setState(() {
            _listaProveedores = proveedoresData.map((j) => Proveedor.fromJson(j)).toList();
            _listaProductos = productosData.map((j) => Producto.fromJson(j)).toList();
            _listaImpuestos = impuestosData.map((j) => Impuesto.fromJson(j)).toList();
            if (responses[3].statusCode == 200) {
              _listaInsumos = [for (final j in json.decode(utf8.decode(responses[3].bodyBytes)) as List) InsumoCompra.fromJson(j)];
            }
            if (responses[4].statusCode == 200) {
              _ordenesAbiertas = [for (final j in json.decode(utf8.decode(responses[4].bodyBytes)) as List) OrdenCompra.fromJson(j)];
            }
            _isLoading = false;
          });
          final ordenInicial = _ordenesAbiertas.where((o) => o.id == widget.ordenId).firstOrNull;
          if (ordenInicial != null) {
            setState(() {
              _proveedorSeleccionado = _listaProveedores.where((p) => p.id == ordenInicial.proveedorId).firstOrNull;
              _orden = ordenInicial;
            });
            if (widget.datosPrecarga == null) _cargarPendientesDeOrden();
          }
          ofrecerRecorrido(context, clave: GuiaCompra.clave, titulo: "se registra una compra", iniciar: () => GuiaCompra.mostrar(context));
          if (widget.datosPrecarga != null) {
            await _aplicarDatosParseados(widget.datosPrecarga!);
          }
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- REGISTRO RÁPIDO DE PROVEEDOR ---
  void _mostrarDialogoRapidoProveedor() {
    final nombreCtrl = TextEditingController();
    final cedulaCtrl = TextEditingController();
    final correoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nuevo Proveedor"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // La cédula primero: con ella se carga el nombre de Hacienda.
            CampoCedulaHacienda(controller: cedulaCtrl, nombreController: nombreCtrl, labelText: "Cédula (opcional)"),
            const SizedBox(height: 8),
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: "Nombre / Razón Social"),
            ),
            TextField(
              controller: correoCtrl,
              decoration: const InputDecoration(labelText: "Correo (Opcional)"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nombreCtrl.text.trim().isEmpty) return;

              final response = await ApiService.post('/proveedores/', {
                'negocio': widget.negocio.id,
                'nombre': nombreCtrl.text.trim(),
                'cedula_juridica': cedulaCtrl.text.trim(),
                'correo': correoCtrl.text.trim(),
              });

              if (response.statusCode == 201 || response.statusCode == 200) {
                final nuevo = json.decode(utf8.decode(response.bodyBytes));
                if (mounted) {
                  Navigator.pop(context);
                  await _cargarDatos();
                  setState(() {
                    _proveedorSeleccionado = _listaProveedores.firstWhere(
                          (p) => p.id == nuevo['id'],
                      orElse: () => _listaProveedores.first,
                    );
                  });
                }
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  /// Selector del % de IVA de una línea (13, 4, 2, 1, 0...).
  Widget _selectorTarifa(double? tarifa, ValueChanged<double?> onCambio) {
    final tarifas = {13.0, 4.0, 2.0, 1.0, 0.5, 0.0, if (tarifa != null) tarifa}.toList()..sort((a, b) => b.compareTo(a));
    return DropdownButtonFormField<double?>(
      value: tarifa,
      decoration: const InputDecoration(labelText: "IVA de la línea"),
      items: [
        const DropdownMenuItem<double?>(value: null, child: Text("Sin IVA / no sé")),
        for (final t in tarifas) DropdownMenuItem<double?>(value: t, child: Text("${formatearNumero(t, decimales: t % 1 == 0 ? 0 : 1)} %")),
      ],
      onChanged: onCambio,
    );
  }

  void _agregarInsumoACompra(InsumoCompra insumo) {
    final cantCtrl = TextEditingController(text: "1");
    final costoCtrl = TextEditingController(text: insumo.costo > 0 ? insumo.costo.toStringAsFixed(2) : '');
    double? tarifa = 13;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text("Compra de ${insumo.nombre}"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: cantCtrl,
              decoration: InputDecoration(labelText: "Cantidad (${insumo.unidadTexto})", helperText: "Con decimales, ej. 50,5"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: costoCtrl,
              decoration: InputDecoration(labelText: "Costo por ${insumo.unidadTexto} sin IVA (₡)"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            _selectorTarifa(tarifa, (v) => setD(() => tarifa = v)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _insumoSeleccionado = null);
              },
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                final cantidad = double.tryParse(cantCtrl.text.replaceAll(',', '.')) ?? 0;
                final costo = double.tryParse(costoCtrl.text.replaceAll(',', '.')) ?? 0;
                if (cantidad <= 0) return;
                setState(() {
                  _carritoCompra.add(LineaCompra(insumo: insumo, cantidad: cantidad, precioCosto: costo, tarifa: tarifa));
                  _insumoSeleccionado = null;
                });
                Navigator.pop(context);
              },
              child: const Text("Agregar"),
            ),
          ],
        ),
      ),
    );
  }

  void _agregarProductoACompra(Producto prod) {
    final cantCtrl = TextEditingController(text: "1");
    final costoCtrl = TextEditingController(text: prod.precioUnitario.toString());
    double? tarifa = prod.impuesto?.porcentaje;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setD) => AlertDialog(
        title: Text("Ingreso de ${prod.nombre}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cantCtrl,
              decoration: const InputDecoration(labelText: "Cantidad comprada"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: costoCtrl,
              decoration: const InputDecoration(labelText: "Precio de costo sin IVA (₡)"),
              keyboardType: TextInputType.number,
            ),
            _selectorTarifa(tarifa, (v) => setD(() => tarifa = v)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _productoSeleccionado = null);
            },
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              final cantidad = int.tryParse(cantCtrl.text) ?? 1;
              final costo = double.tryParse(costoCtrl.text.replaceAll(',', '.')) ?? prod.precioUnitario;

              setState(() {
                _carritoCompra.add(LineaCompra(
                  producto: prod,
                  cantidad: cantidad.toDouble(),
                  precioCosto: costo,
                  tarifa: tarifa,
                ));
                _productoSeleccionado = null;
              });
              Navigator.pop(context);
            },
            child: const Text("Aumentar Inventario"),
          )
        ],
      )),
    );
  }

  void _cargarPendientesDeOrden() {
    if (_orden == null) return;
    setState(() => _carritoCompra.addAll(lineasPendientesDeOrden(_orden!, _listaProductos, _listaInsumos)));
  }

  List<OrdenCompra> get _ordenesDelProveedor =>
      _ordenesAbiertas.where((o) => o.proveedorId == _proveedorSeleccionado?.id).toList();

  /// Si la factura no cuadra con la orden y se va a aceptar ante Hacienda,
  /// se pregunta antes: una vez aceptada ya no se puede rechazar.
  Future<bool> _confirmarDiferencias() async {
    if (_orden == null || _claveHacienda == null || !_aceptarEnHacienda) return true;
    final alertas = compararConOrden(_orden!, _carritoCompra).where((d) => d.alerta).toList();
    if (alertas.isEmpty) return true;
    final opcion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("La factura no cuadra con la orden"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final d in alertas) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text("• ${d.texto}")),
            const SizedBox(height: 6),
            const Text("Si la aceptás ante Hacienda ya no se puede rechazar. Podés guardarla sin responder y "
                "aceptarla o rechazarla después desde el Historial."),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Revisar")),
          TextButton(onPressed: () => Navigator.pop(ctx, 'sin'), child: const Text("Guardar sin responder")),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'aceptar'), child: const Text("Guardar y aceptar")),
        ],
      ),
    );
    if (opcion == 'sin') setState(() => _aceptarEnHacienda = false);
    return opcion != null;
  }

  double get _subtotal => _carritoCompra.fold(0.0, (s, l) => s + redondear2(l.subtotal));
  double get _iva => _carritoCompra.fold(0.0, (s, l) => s + redondear2(l.iva));

  Future<void> _guardarCompra() async {
    if (_proveedorSeleccionado == null || _carritoCompra.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seleccione un proveedor y al menos un producto.")),
      );
      return;
    }
    if (!await _confirmarDiferencias()) return;

    setState(() => _isSaving = true);

    try {
      final body = {
        'negocio': widget.negocio.id,
        'proveedor': _proveedorSeleccionado!.id,
        'numero_factura_proveedor': _facturaProveedorController.text.trim(),
        'condicion_compra': _condicionCompra,
        'fecha_compra': "${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}",
        'moneda': _moneda,
        'tipo_cambio': double.tryParse(_tipoCambioController.text.trim().replaceAll(',', '.')) ?? 1.0,
        // Total = lo que se le debe o se le pagó al proveedor, con IVA (el
        // IVA va aparte como crédito fiscal en el asiento).
        'subtotal_compra': redondear2(_subtotal),
        'iva_compra': redondear2(_iva),
        'total_compra': redondear2(_subtotal + _iva),
        'detalles_compra': _carritoCompra.map((item) => item.toJson()).toList(),
        if (_claveHacienda != null) 'clave_hacienda': _claveHacienda,
        if (_orden != null) 'orden_compra': _orden!.id,
      };

      final res = await ApiService.post('/compras/', body);

      if (res.statusCode == 201 || res.statusCode == 200) {
        final compraId = json.decode(utf8.decode(res.bodyBytes))['id'];
        if (_bytesComprobante != null) {
          final resAdjunto = await ApiService.uploadBytes('/compras/$compraId/', 'comprobante', _bytesComprobante!, _nombreComprobante ?? 'comprobante');
          if (resAdjunto.statusCode != 200 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("La compra se registró, pero no se pudo adjuntar el comprobante: ${ApiService.mensajeError(resAdjunto)}"),
            ));
          }
        }
        if (_claveHacienda != null && _aceptarEnHacienda) {
          // La compra ya quedó registrada: si la aceptación falla (ej. sin
          // llave criptográfica) solo se avisa, se puede reintentar desde
          // el Historial con "Responder a Hacienda".
          String? errorAceptacion;
          try {
            final resMr = await ApiService.post('/compras/$compraId/mensaje-receptor/', {'tipo': '1', 'detalle': ''});
            if (resMr.statusCode != 200) {
              errorAceptacion = (json.decode(utf8.decode(resMr.bodyBytes))['detail'] ?? 'Error desconocido').toString();
            }
          } catch (e) {
            errorAceptacion = e.toString();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(errorAceptacion == null
                  ? "Compra registrada y aceptada ante Hacienda."
                  : "Compra registrada, pero no se pudo aceptar ante Hacienda: $errorAceptacion"),
            ));
          }
        }
        if (widget.correoId != null) {
          try {
            await ApiService.delete('/correos-compra-recibidos/${widget.correoId}/');
          } catch (_) {}
        }
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(ApiService.mensajeError(res));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al registrar la compra: ${ApiService.textoError(e)}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _filaTotal(String texto, double monto, {bool fuerte = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(texto, style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.normal))),
      Text(formatearColones(monto), style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ingreso de Mercadería"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [BotonGuia(iniciar: () => GuiaCompra.mostrar(context))],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                // FILA PROVEEDOR CON BOTÓN +
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<Proveedor>(
                        key: GuiaCompra.proveedor,
                        value: _proveedorSeleccionado,
                        decoration: const InputDecoration(
                          labelText: "Proveedor",
                          border: OutlineInputBorder(),
                        ),
                        items: _listaProveedores
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
                            .toList(),
                        onChanged: (val) => setState(() {
                          _proveedorSeleccionado = val;
                          if (_orden?.proveedorId != val?.id) _orden = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _mostrarDialogoRapidoProveedor,
                      icon: const Icon(Icons.person_add),
                      style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                    ),
                  ],
                ),
                if (_ordenesDelProveedor.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: _orden?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Orden de compra",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.assignment_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text("Sin orden")),
                      for (final o in _ordenesDelProveedor)
                        DropdownMenuItem<int?>(value: o.id, child: Text("${o.codigo} · ${formatearColones(o.total)} · ${textoEstadoOrden(o.estado)}")),
                    ],
                    onChanged: (id) => setState(() => _orden = _ordenesDelProveedor.where((o) => o.id == id).firstOrNull),
                  ),
                ],
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final elegida = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                    );
                    if (elegida != null) setState(() => _fecha = elegida);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Fecha de la factura",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text("${_fecha.day.toString().padLeft(2, '0')}/${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}"),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _facturaProveedorController,
                  decoration: const InputDecoration(
                    labelText: "Número Factura Proveedor",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: GuiaCompra.condicion,
                  value: _condicionCompra,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: "Condición",
                    isDense: true,
                    prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: "01", child: Text("Contado")),
                    DropdownMenuItem(value: "02", child: Text("Crédito (Cuentas por Pagar)")),
                  ],
                  onChanged: (val) => setState(() => _condicionCompra = val!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _moneda,
                        decoration: InputDecoration(
                          labelText: "Moneda",
                          isDense: true,
                          prefixIcon: const Icon(Icons.attach_money, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: const [
                          DropdownMenuItem(value: "CRC", child: Text("Colones")),
                          DropdownMenuItem(value: "USD", child: Text("Dólares")),
                        ],
                        onChanged: (val) async {
                          if (val == 'USD' && _tipoCambioController.text.trim() == '1.00') {
                            _tipoCambioController.text = (await _obtenerTipoCambioDelDia()).toStringAsFixed(2);
                          }
                          setState(() => _moneda = val!);
                        },
                      ),
                    ),
                    if (_moneda == 'USD') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _tipoCambioController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: "Tipo de cambio",
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_moneda == 'USD') ...[
                  const SizedBox(height: 6),
                  Text(
                    "Los precios de las líneas siguen en colones -- este dato es solo para llevar registro "
                    "de que la factura del proveedor venía en dólares y a qué tipo de cambio.",
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: GuiaCompra.adjuntar,
                  onPressed: _procesandoXml ? null : _elegirComprobante,
                  icon: _procesandoXml
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file),
                  label: Text(
                    _procesandoXml
                        ? "Leyendo comprobante..."
                        : _nombreComprobante ?? "Adjuntar comprobante (PDF, imagen o XML de Hacienda)",
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45),
                    alignment: Alignment.centerLeft,
                  ),
                ),
                if (_avisoCuadre != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(builder: (context) {
                            final totalLineas = (_avisoCuadre!['total_calculado'] as num).toDouble();
                            final diferencia = (_avisoCuadre!['diferencia'] as num).toDouble();
                            final totalComprobante = totalLineas + diferencia;
                            return Text(
                              "El comprobante dice ${formatearColones(totalComprobante)} pero las líneas de abajo suman "
                              "${formatearColones(totalLineas)} -- revisá los precios contra el comprobante antes de confirmar.",
                              style: const TextStyle(fontSize: 12, color: Colors.orange),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<Producto>(
                  value: _productoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: "Seleccionar Producto para Aumentar",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.add_box),
                  ),
                  items: _listaProductos
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _productoSeleccionado = val);
                      _agregarProductoACompra(val);
                    }
                  },
                ),
                if (_listaInsumos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<InsumoCompra>(
                    value: _insumoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: "Agregar insumo (materia prima)",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.kitchen_outlined),
                    ),
                    items: _listaInsumos.map((i) => DropdownMenuItem(value: i, child: Text("${i.nombre} (${i.unidadTexto})"))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _insumoSeleccionado = val);
                        _agregarInsumoACompra(val);
                      }
                    },
                  ),
                ],
                if (_orden != null) ...[
                  const SizedBox(height: 10),
                  if (_carritoCompra.isEmpty)
                    OutlinedButton.icon(
                      onPressed: _cargarPendientesDeOrden,
                      icon: const Icon(Icons.playlist_add),
                      label: Text("Cargar lo pendiente de ${_orden!.codigo}"),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 45)),
                    )
                  else
                    PanelDiferenciasOrden(orden: _orden!, diferencias: compararConOrden(_orden!, _carritoCompra)),
                ],
                const SizedBox(height: 10),
                // El carrito iba en un Expanded/ListView aparte, con una
                // altura fija sobrante debajo de todo este encabezado -- al
                // agregarle Moneda/Tipo de cambio y el aviso de cuadre, el
                // encabezado creció y ese espacio sobrante se achicaba tanto
                // que el carrito quedaba invisible ("estático"). Ahora es
                // parte del mismo scroll que el resto del formulario, así
                // que siempre se ve por más larga que sea la lista.
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _carritoCompra.length,
                  itemBuilder: (context, i) {
                    final item = _carritoCompra[i];
                    final unidad = item.insumo != null ? item.insumo!.unidadTexto : 'unid.';
                    return ListTile(
                      leading: Icon(item.insumo != null ? Icons.kitchen_outlined : Icons.arrow_upward, color: AppColors.primary),
                      title: Text(item.nombre),
                      subtitle: Text(
                        "Entran: ${formatearNumero(item.cantidad, decimales: item.cantidad % 1 == 0 ? 0 : 3)} $unidad · "
                        "Costo: ${formatearColones(item.precioCosto)} · "
                        "${item.tarifa == null ? 'sin IVA' : 'IVA ${formatearNumero(item.tarifa!, decimales: item.tarifa! % 1 == 0 ? 0 : 1)} %'}",
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => setState(() => _carritoCompra.removeAt(i)),
                      ),
                    );
                  },
                ),
              ],
                ),
              ),
            ),
          ),
          if (_carritoCompra.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Column(children: [
                _filaTotal("Subtotal", _subtotal),
                _filaTotal("IVA (crédito fiscal)", _iva),
                _filaTotal("Total de la factura", _subtotal + _iva, fuerte: true),
              ]),
            ),
          if (_claveHacienda != null)
            CheckboxListTile(
              key: GuiaCompra.aceptar,
              value: _aceptarEnHacienda,
              onChanged: _isSaving ? null : (v) => setState(() => _aceptarEnHacienda = v ?? true),
              title: const Text("Aceptar ante Hacienda al confirmar"),
              subtitle: const Text("Manda el Mensaje Receptor de aceptación (crédito fiscal del IVA)"),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              key: GuiaCompra.confirmar,
              onPressed: _isSaving ? null : _guardarCompra,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 55),
              ),
              child: _isSaving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
              )
                  : const Text(
                "CONFIRMAR INGRESO",
                style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
    );
  }
}