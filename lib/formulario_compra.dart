import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'impuesto.dart';
import 'negocio.dart';
import 'producto.dart';
import 'formato.dart';

class FormularioCompra extends StatefulWidget {
  final Negocio negocio;
  // Si esta compra se abre a partir de un correo que llegó solo al buzón de
  // facturas de compra del negocio (ver CorreoCompraRecibido), estos dos
  // vienen con datos: los datos ya parseados del XML (misma forma que
  // devuelve /compras/leer-xml/) y el id del correo, para poder descartarlo
  // de la lista de pendientes una vez que la compra se guarda de verdad.
  final Map<String, dynamic>? datosPrecarga;
  final int? correoId;
  const FormularioCompra({super.key, required this.negocio, this.datosPrecarga, this.correoId});

  @override
  State<FormularioCompra> createState() => _FormularioCompraState();
}

class _FormularioCompraState extends State<FormularioCompra> {
  final TextEditingController _facturaProveedorController = TextEditingController();
  List<Proveedor> _listaProveedores = [];
  List<Producto> _listaProductos = [];
  final List<LineaCompra> _carritoCompra = [];

  Proveedor? _proveedorSeleccionado;
  Producto? _productoSeleccionado;
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
        throw Exception(utf8.decode(response.bodyBytes));
      }
      await _aplicarDatosParseados(json.decode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al leer el XML: $e")),
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
      final fechaLeida = datos['fecha'] as String?;
      if (fechaLeida != null && fechaLeida.isNotEmpty) {
        final parseada = DateTime.tryParse(fechaLeida);
        if (parseada != null) setState(() => _fecha = parseada);
      }

      // Proveedor: si ya existe (por cédula) se selecciona; si no, se crea
      // automáticamente con los datos del XML.
      final proveedorId = datos['proveedor_id'];
      if (proveedorId != null) {
        setState(() {
          _proveedorSeleccionado = _listaProveedores.firstWhere(
            (p) => p.id == proveedorId,
            orElse: () => _listaProveedores.first,
          );
        });
      } else if (datos['proveedor_nombre'] != null) {
        final resProv = await ApiService.post('/proveedores/', {
          'negocio': widget.negocio.id,
          'nombre': datos['proveedor_nombre'],
          'cedula_juridica': datos['proveedor_cedula'] ?? '',
          'correo': datos['proveedor_correo'] ?? '',
        });
        if (resProv.statusCode == 201) {
          final nuevo = json.decode(utf8.decode(resProv.bodyBytes));
          await _cargarDatos();
          setState(() {
            _proveedorSeleccionado = _listaProveedores.firstWhere(
              (p) => p.id == nuevo['id'],
              orElse: () => _listaProveedores.first,
            );
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Proveedor creado automáticamente: ${datos['proveedor_nombre']}")),
            );
          }
        }
      }

      // Líneas de producto: las que ya coinciden por CABYS se agregan
      // directo; las que no, piden vincular o crear un producto.
      final List lineas = datos['lineas'] ?? [];
      for (final linea in lineas) {
        final productoId = linea['producto_id'];
        if (productoId != null) {
          final producto = _listaProductos.firstWhere(
            (p) => p.id == productoId,
            orElse: () => _listaProductos.first,
          );
          setState(() {
            _carritoCompra.add(LineaCompra(
              producto: producto,
              cantidad: (linea['cantidad'] as num).toInt(),
              precioCosto: redondear2(linea['precio_unitario'] as num),
            ));
          });
        } else if (mounted) {
          await _resolverLineaSinProducto(linea);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al precargar los datos: $e")),
        );
      }
    }
  }

  /// Cuando una línea del XML no coincide con ningún producto ya registrado
  /// (por CABYS), se pide vincularla a uno existente o crear uno nuevo.
  Future<void> _resolverLineaSinProducto(Map linea) async {
    final cabys = linea['codigo_cabys'] as String? ?? '';
    final detalle = linea['detalle'] as String? ?? 'Producto sin nombre';
    final cantidad = ((linea['cantidad'] as num?) ?? 1).toInt();
    final precio = ((linea['precio_unitario'] as num?) ?? 0).toDouble();
    final tarifaLinea = (linea['tarifa'] as num?)?.toDouble();

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
                  DropdownButtonFormField<Producto?>(
                    value: productoExistente,
                    decoration: const InputDecoration(labelText: "Vincular a producto existente", border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<Producto?>(value: null, child: Text("Crear producto nuevo")),
                      ..._listaProductos.map((p) => DropdownMenuItem<Producto?>(value: p, child: Text(p.nombre))),
                    ],
                    onChanged: (v) => setStateDialog(() => productoExistente = v),
                  ),
                  if (productoExistente == null) ...[
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
                          cantidad: cantidad,
                          precioCosto: redondear2(double.tryParse(precioCtrl.text.trim()) ?? precio),
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
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    try {
      final responses = await Future.wait([
        ApiService.get('/proveedores/?negocio=${widget.negocio.id}'),
        ApiService.get('/productos/?negocio=${widget.negocio.id}'),
        ApiService.get('/impuestos/'),
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
            _isLoading = false;
          });
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
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: "Nombre / Razón Social"),
            ),
            TextField(
              controller: cedulaCtrl,
              decoration: const InputDecoration(labelText: "Cédula Jurídica (Opcional)"),
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

  void _agregarProductoACompra(Producto prod) {
    final cantCtrl = TextEditingController(text: "1");
    final costoCtrl = TextEditingController(text: prod.precioUnitario.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              decoration: const InputDecoration(labelText: "Precio de costo (₡)"),
              keyboardType: TextInputType.number,
            ),
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
              final costo = double.tryParse(costoCtrl.text) ?? prod.precioUnitario;

              setState(() {
                _carritoCompra.add(LineaCompra(
                  producto: prod,
                  cantidad: cantidad,
                  precioCosto: costo,
                ));
                _productoSeleccionado = null;
              });
              Navigator.pop(context);
            },
            child: const Text("Aumentar Inventario"),
          )
        ],
      ),
    );
  }

  Future<void> _guardarCompra() async {
    if (_proveedorSeleccionado == null || _carritoCompra.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seleccione un proveedor y al menos un producto.")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final body = {
        'negocio': widget.negocio.id,
        'proveedor': _proveedorSeleccionado!.id,
        'numero_factura_proveedor': _facturaProveedorController.text.trim(),
        'condicion_compra': _condicionCompra,
        'fecha_compra': "${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}",
        'total_compra': redondear2(_carritoCompra.fold(0.0, (sum, item) => sum + item.subtotal)),
        'detalles_compra': _carritoCompra.map((item) => {
          'producto': item.producto.id,
          'cantidad': item.cantidad,
          'precio_costo': redondear2(item.precioCosto),
        }).toList(),
        if (_claveHacienda != null) 'clave_hacienda': _claveHacienda,
      };

      final res = await ApiService.post('/compras/', body);

      if (res.statusCode == 201 || res.statusCode == 200) {
        if (_bytesComprobante != null) {
          final compraId = json.decode(utf8.decode(res.bodyBytes))['id'];
          await ApiService.uploadBytes('/compras/$compraId/', 'comprobante', _bytesComprobante!, _nombreComprobante ?? 'comprobante');
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
        throw Exception(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al registrar la compra: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ingreso de Mercadería"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // FILA PROVEEDOR CON BOTÓN +
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<Proveedor>(
                        value: _proveedorSeleccionado,
                        decoration: const InputDecoration(
                          labelText: "Proveedor",
                          border: OutlineInputBorder(),
                        ),
                        items: _listaProveedores
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
                            .toList(),
                        onChanged: (val) => setState(() => _proveedorSeleccionado = val),
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
                  value: _condicionCompra,
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
                OutlinedButton.icon(
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
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _carritoCompra.length,
              itemBuilder: (context, i) {
                final item = _carritoCompra[i];
                return ListTile(
                  leading: Icon(Icons.arrow_upward, color: AppColors.primary),
                  title: Text(item.producto.nombre),
                  subtitle: Text("Entran: ${formatearNumero(item.cantidad, decimales: 0)} unidades | Costo: ${formatearColones(item.precioCosto)}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => setState(() => _carritoCompra.removeAt(i)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
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