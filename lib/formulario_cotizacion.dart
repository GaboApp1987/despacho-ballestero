import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'cliente.dart';
import 'negocio.dart';
import 'producto.dart';
import 'impuesto.dart';
import 'formato.dart';

class LineaCotizacion {
  final Producto producto;
  int cantidad;
  double precioUnitario;
  Impuesto? impuesto;

  LineaCotizacion({required this.producto, required this.cantidad, this.impuesto})
      : precioUnitario = producto.precioUnitario;

  double get porcentajeIva => impuesto?.porcentaje ?? 0.0;
  double get subtotal => precioUnitario * cantidad;
  double get montoIva => subtotal * (porcentajeIva / 100);
  double get total => subtotal + montoIva;
}

class FormularioCotizacion extends StatefulWidget {
  final Negocio negocio;
  const FormularioCotizacion({super.key, required this.negocio});

  @override
  State<FormularioCotizacion> createState() => _FormularioCotizacionState();
}

class _FormularioCotizacionState extends State<FormularioCotizacion> {
  // Por debajo de este ancho el catálogo y el carrito se apilan en vertical
  // en vez de ir lado a lado (que en un teléfono no cabe: el panel del
  // carrito por sí solo mide 380px de ancho fijo).
  static const double _anchoBreakpointMovil = 700;

  final List<LineaCotizacion> _carrito = [];
  List<Cliente> _listaClientes = [];
  List<Producto> _listaProductos = [];
  Cliente? _clienteSeleccionado;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _procesandoNota = false;

  /// En Web y en el celular (Android/iOS empaquetados con este mismo
  /// código) sí tiene sentido ofrecer "Tomar foto" -- en el armado de
  /// escritorio (Windows/Linux/macOS) no hay una cámara "del navegador"
  /// que ofrecer, así que ahí se salta directo al selector de archivos.
  bool get _esEscritorio {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  int? _categoriaFiltro;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _busquedaCtrl.addListener(() {
      setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    try {
      final res = await Future.wait([
        ApiService.get('/clientes/?negocio=${widget.negocio.id}'),
        ApiService.get('/productos/?negocio=${widget.negocio.id}'),
      ]);
      if (mounted) {
        setState(() {
          _listaClientes = (json.decode(utf8.decode(res[0].bodyBytes)) as List).map((j) => Cliente.fromJson(j)).toList();
          _listaProductos = (json.decode(utf8.decode(res[1].bodyBytes)) as List).map((j) => Producto.fromJson(j)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _totalGeneral => _carrito.fold(0, (sum, item) => sum + item.total);

  Map<int, String> get _categoriasDisponibles {
    final mapa = <int, String>{};
    for (final p in _listaProductos) {
      if (p.categoriaId != null) mapa[p.categoriaId!] = p.nombreCategoria ?? 'Categoría';
    }
    return mapa;
  }

  List<Producto> get _productosFiltrados {
    return _listaProductos.where((p) {
      final matchTexto = _busqueda.isEmpty || p.nombre.toLowerCase().contains(_busqueda);
      final matchCategoria = _categoriaFiltro == null || p.categoriaId == _categoriaFiltro;
      return matchTexto && matchCategoria;
    }).toList();
  }

  /// Toque rápido tipo kiosko: un tap agrega 1 unidad usando el impuesto que
  /// ya tiene asignado el producto (sin interrumpir con un diálogo); si el
  /// producto ya está en el carrito, simplemente le suma una unidad más. El
  /// impuesto de una línea siempre es el del producto — se cambia editando
  /// el producto, no aquí.
  void _agregarRapido(Producto p) {
    final idx = _carrito.indexWhere((l) => l.producto.id == p.id);
    if (idx != -1) {
      setState(() => _carrito[idx].cantidad++);
    } else {
      setState(() => _carrito.add(LineaCotizacion(producto: p, cantidad: 1, impuesto: p.impuesto)));
    }
  }

  /// Le manda una foto de una nota de pedido (a mano o no) a Claude
  /// (backend: CotizacionViewSet.interpretar_nota) para que interprete qué
  /// productos del catálogo se están pidiendo y en qué cantidad, y los
  /// agrega al carrito -- en vez de tipear todo a mano. Nunca guarda nada
  /// solo: el negocio revisa el carrito resultante antes de confirmar la
  /// cotización, igual que si lo hubiera armado a mano.
  /// Antes usaba solo FilePicker (un selector de archivos genérico): en el
  /// navegador eso NO ofrece la opción de "Tomar foto" con la cámara, solo
  /// elegir un archivo ya guardado -- reportado real por un usuario que
  /// quería fotografiar una nota a mano en el momento. Con image_picker y
  /// ImageSource.camera el navegador sí pide permiso de cámara y abre la
  /// captura directa (en Android/iOS/Web); en el armado de escritorio
  /// (Windows) no hay una cámara "nativa" del navegador que ofrecer, así
  /// que ahí se salta directo al selector de archivos de siempre.
  Future<Uint8List?> _tomarFotoConCamara() async {
    final foto = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (foto == null) return null;
    return foto.readAsBytes();
  }

  Future<void> _escanearNota() async {
    Uint8List? bytes;
    String nombre = 'nota.jpg';

    if (!_esEscritorio) {
      final origen = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text("Tomar foto"),
                onTap: () => Navigator.pop(ctx, 'camara'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text("Elegir archivo"),
                onTap: () => Navigator.pop(ctx, 'archivo'),
              ),
            ],
          ),
        ),
      );
      if (origen == null) return;
      if (origen == 'camara') {
        bytes = await _tomarFotoConCamara();
        if (bytes == null) return;
      }
    }

    if (bytes == null) {
      final resultado = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (resultado == null || resultado.files.single.bytes == null) return;
      bytes = resultado.files.single.bytes!;
      nombre = resultado.files.single.name;
    }

    setState(() => _procesandoNota = true);
    try {
      final response = await ApiService.postMultipartBytes(
        '/cotizaciones/interpretar-nota/',
        {'negocio': widget.negocio.id.toString()},
        'imagen',
        bytes,
        nombre,
      );
      if (response.statusCode != 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(data['detail'] ?? 'Error desconocido');
      }
      final data = json.decode(utf8.decode(response.bodyBytes));
      final items = (data['items'] as List? ?? []);
      final noReconocidos = (data['no_reconocidos'] as List? ?? []);
      final presentacionesFaltantes = (data['presentaciones_faltantes'] as List? ?? []);
      final clienteIdDetectado = data['cliente_id'];
      final clienteNombreSugerido = data['cliente_nombre_sugerido'] as String?;

      String? mensajeCliente;
      if (clienteIdDetectado != null) {
        Cliente? clienteDetectado;
        for (final c in _listaClientes) {
          if (c.id == clienteIdDetectado) {
            clienteDetectado = c;
            break;
          }
        }
        if (clienteDetectado != null) {
          setState(() => _clienteSeleccionado = clienteDetectado);
          mensajeCliente = "Cliente detectado y seleccionado: ${clienteDetectado.nombre}.";
        }
      } else if (clienteNombreSugerido != null && clienteNombreSugerido.trim().isNotEmpty) {
        mensajeCliente = "Se detectó el nombre \"$clienteNombreSugerido\" en la nota, pero no "
            "coincide con ningún cliente registrado. Seleccioná uno o creá uno nuevo.";
      }

      int agregados = 0;
      for (final item in items) {
        Producto? producto;
        for (final p in _listaProductos) {
          if (p.id == item['producto_id']) {
            producto = p;
            break;
          }
        }
        if (producto == null) continue;
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 1;
        final idx = _carrito.indexWhere((l) => l.producto.id == producto!.id);
        if (idx != -1) {
          _carrito[idx].cantidad += cantidad;
        } else {
          _carrito.add(LineaCotizacion(producto: producto, cantidad: cantidad, impuesto: producto.impuesto));
        }
        agregados++;
      }
      if (mounted) setState(() {});

      // Presentaciones que Claude no pudo convertir (ej. "1 caja" pero ese
      // producto no tiene ninguna Caja registrada): se pregunta la
      // equivalencia una vez, se guarda para la próxima, y recién ahí se
      // agrega al carrito con la cantidad ya convertida.
      int agregadosPorPresentacion = 0;
      if (mounted) {
        agregadosPorPresentacion = await _resolverPresentacionesFaltantes(presentacionesFaltantes);
      }

      if (mounted) {
        final partes = <String>[];
        if (mensajeCliente != null) partes.add(mensajeCliente);
        final totalAgregados = agregados + agregadosPorPresentacion;
        if (totalAgregados > 0) partes.add("Se agregaron $totalAgregados producto(s) al carrito.");
        if (noReconocidos.isNotEmpty) {
          final descripciones = noReconocidos.map((n) => "• ${n['descripcion']}").join('\n');
          partes.add("No se pudieron emparejar con el catálogo:\n$descripciones");
        }
        if (partes.isEmpty) partes.add("No se detectó ningún producto en la imagen.");
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Nota interpretada"),
            content: Text(partes.join('\n\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al interpretar la nota: $e"), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoNota = false);
    }
  }

  /// Por cada presentación desconocida que Claude marcó (ej. "1 caja de
  /// tomate" sin tener ninguna Caja registrada para ese producto), pregunta
  /// una vez cuánto trae, la guarda en el backend (PresentacionProducto)
  /// para que la próxima nota ya la reconozca sola, y agrega el producto al
  /// carrito con la cantidad ya convertida. Devuelve cuántos se agregaron.
  Future<int> _resolverPresentacionesFaltantes(List presentacionesFaltantes) async {
    int agregados = 0;
    for (final pf in presentacionesFaltantes) {
      if (!mounted) break;
      final productoId = pf['producto_id'];
      Producto? producto;
      for (final p in _listaProductos) {
        if (p.id == productoId) {
          producto = p;
          break;
        }
      }
      if (producto == null) continue;

      final nombrePresentacion = pf['presentacion_nombre'] ?? 'Presentación';
      final cantidadPedida = (pf['cantidad_pedida'] as num?)?.toDouble() ?? 1;
      final unidad = pf['unidad_medida'] ?? producto.unidadMedida;
      final equivalenciaCtrl = TextEditingController();

      final equivalencia = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('¿Cuánto trae "$nombrePresentacion" de ${producto!.nombre}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La nota pidió $cantidadPedida $nombrePresentacion(s), pero no hay registrada '
                'una equivalencia en $unidad para esa presentación de este producto.',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: equivalenciaCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Una $nombrePresentacion trae cuántos $unidad',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Omitir")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(equivalenciaCtrl.text.replaceAll(',', '.'))),
              child: const Text("Guardar y agregar"),
            ),
          ],
        ),
      );
      if (equivalencia == null || equivalencia <= 0) continue;

      try {
        final response = await ApiService.post('/presentaciones-producto/', {
          'producto': producto.id,
          'nombre': nombrePresentacion,
          'equivalencia': equivalencia,
        });
        if (response.statusCode != 201) {
          throw Exception(utf8.decode(response.bodyBytes));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("No se pudo guardar la presentación: $e"), backgroundColor: Colors.red),
          );
        }
        continue;
      }

      final cantidadTotal = (equivalencia * cantidadPedida).round();
      final idx = _carrito.indexWhere((l) => l.producto.id == producto!.id);
      if (idx != -1) {
        _carrito[idx].cantidad += cantidadTotal;
      } else {
        _carrito.add(LineaCotizacion(producto: producto, cantidad: cantidadTotal, impuesto: producto.impuesto));
      }
      agregados++;
    }
    if (mounted) setState(() {});
    return agregados;
  }

  void _incrementar(int index) => setState(() => _carrito[index].cantidad++);

  void _decrementar(int index) => setState(() {
        if (_carrito[index].cantidad > 1) {
          _carrito[index].cantidad--;
        } else {
          _carrito.removeAt(index);
        }
      });

  void _quitar(int index) => setState(() => _carrito.removeAt(index));

  /// Edición rápida de una línea: solo cantidad y precio unitario (para un
  /// descuento puntual, por ejemplo). El impuesto no se toca aquí — es el
  /// que tiene asignado el producto; para cambiarlo hay que editar el
  /// producto en el catálogo.
  void _editarLineaCarrito(int index) {
    final item = _carrito[index];
    final cantidadCtrl = TextEditingController(text: item.cantidad.toString());
    final precioCtrl = TextEditingController(text: item.precioUnitario.toStringAsFixed(2));

    // No se debe cotizar por debajo del costo + 10% de margen mínimo. Si el
    // producto no tiene costo cargado (0), no hay piso que exigir.
    final double costo = item.producto.costo;
    final double precioMinimo = redondear2(costo * 1.10);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Editar ${item.producto.nombre}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: cantidadCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(labelText: "Cantidad", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Precio unitario (₡)", border: OutlineInputBorder(), prefixText: "₡ "),
              ),
              if (costo > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    "Costo del producto: ${formatearColones(costo)}\n"
                    "Precio mínimo permitido (costo + 10%): ${formatearColones(precioMinimo)}",
                    style: TextStyle(fontSize: 12, color: Colors.amber[900], fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              final nuevaCantidad = int.tryParse(cantidadCtrl.text);
              final nuevoPrecio = double.tryParse(precioCtrl.text.replaceAll(',', '.'));
              if (nuevaCantidad == null || nuevaCantidad <= 0 || nuevoPrecio == null || nuevoPrecio < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("Ingrese una cantidad y un precio válidos")),
                );
                return;
              }
              if (costo > 0 && nuevoPrecio < precioMinimo) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text("El precio no puede ser menor a ${formatearColones(precioMinimo)} (costo + 10%)")),
                );
                return;
              }
              setState(() {
                item.cantidad = nuevaCantidad;
                item.precioUnitario = nuevoPrecio;
              });
              Navigator.pop(ctx);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    if (_clienteSeleccionado == null || _carrito.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final subtotal = _carrito.fold(0.0, (sum, i) => sum + i.subtotal);
      final montoIva = _carrito.fold(0.0, (sum, i) => sum + i.montoIva);
      final body = {
        'negocio': widget.negocio.id,
        'cliente': _clienteSeleccionado!.id,
        'subtotal': redondear2(subtotal),
        'monto_iva': redondear2(montoIva),
        'total': redondear2(_totalGeneral),
        'detalles': _carrito.map((i) => {
          'producto': i.producto.id,
          'cantidad': i.cantidad,
          'precio_unitario': redondear2(i.precioUnitario),
          'monto_iva': redondear2(i.montoIva),
          'subtotal': redondear2(i.subtotal),
        }).toList(),
      };
      final res = await ApiService.post('/cotizaciones/', body);
      if (res.statusCode == 201) {
        // La cotización ya quedó guardada: se cierra de inmediato. Imprimir
        // o compartir el PDF se hace luego desde la lista (no se debe
        // esperar aquí a un diálogo de impresión: si no hay impresora
        // configurada se queda "guardando" para siempre y parece que falló).
        if (mounted) Navigator.pop(context, true);
      } else {
        throw Exception(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al guardar: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Nueva Cotización"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          IconButton(
            icon: _procesandoNota
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner_outlined),
            tooltip: "Escanear nota de pedido (foto o escrita a mano)",
            onPressed: _procesandoNota ? null : _escanearNota,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final bool anchoCorto = constraints.maxWidth < _anchoBreakpointMovil;

              // 🛍️ Catálogo tipo kiosko de autoservicio. En móvil el grid no
              // se recorta a una altura fija (eso hacía que pareciera
              // "atorado" al no poder ver ni bajar más productos): se dibuja
              // completo (shrinkWrap) dentro del scroll único de toda la
              // pantalla.
              Widget construirCatalogo({required bool expandirGrid}) {
                final grid = _productosFiltrados.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text("No se encontraron productos", style: TextStyle(color: Colors.grey))),
                      )
                    : GridView.builder(
                        shrinkWrap: !expandirGrid,
                        physics: expandirGrid ? null : const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          childAspectRatio: 0.95,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _productosFiltrados.length,
                        itemBuilder: (context, i) => _tarjetaProducto(_productosFiltrados[i]),
                      );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: expandirGrid ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: TextField(
                        controller: _busquedaCtrl,
                        decoration: InputDecoration(
                          hintText: "Buscar producto por nombre...",
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _busqueda.isEmpty
                              ? null
                              : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _busquedaCtrl.clear()),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    if (_categoriasDisponibles.isNotEmpty)
                      SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            _chipCategoria(null, "Todas"),
                            ..._categoriasDisponibles.entries.map((e) => _chipCategoria(e.key, e.value)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    expandirGrid ? Expanded(child: grid) : grid,
                  ],
                );
              }

              // 🧾 Panel tipo "Tu Orden"
              final panelOrden = Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    left: anchoCorto ? BorderSide.none : BorderSide(color: AppColors.border),
                    top: anchoCorto ? BorderSide(color: AppColors.border) : BorderSide.none,
                  ),
                ),
                child: _panelCarrito(dentroDeScrollExterno: anchoCorto),
              );

              if (anchoCorto) {
                // En móvil primero va lo que ya se decidió (cliente y los
                // productos ya seleccionados con su total), y hasta abajo el
                // catálogo para seguir agregando más.
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      panelOrden,
                      const Divider(height: 1),
                      construirCatalogo(expandirGrid: false),
                    ],
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(flex: 7, child: construirCatalogo(expandirGrid: true)),
                  SizedBox(width: 380, child: panelOrden),
                ],
              );
            }),
    );
  }

  Widget _chipCategoria(int? id, String nombre) {
    final seleccionado = _categoriaFiltro == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(nombre),
        selected: seleccionado,
        onSelected: (_) => setState(() => _categoriaFiltro = id),
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(color: seleccionado ? Colors.black : AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
        backgroundColor: AppColors.surfaceSubtle,
        shape: StadiumBorder(side: BorderSide(color: seleccionado ? AppColors.primary : AppColors.border)),
      ),
    );
  }

  Widget _iconoProductoPlaceholder() {
    return Container(
      color: AppColors.primary.withOpacity(0.08),
      alignment: Alignment.center,
      child: Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 24),
    );
  }

  Widget _tarjetaProducto(Producto p) {
    final idx = _carrito.indexWhere((l) => l.producto.id == p.id);
    final cantidadEnCarrito = idx == -1 ? 0 : _carrito[idx].cantidad;
    final seleccionado = cantidadEnCarrito > 0;

    return InkWell(
      onTap: () => _agregarRapido(p),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: seleccionado ? AppColors.primary : AppColors.border, width: seleccionado ? 2 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: (p.imagenUrl != null && p.imagenUrl!.isNotEmpty)
                        ? Image.network(
                            p.imagenUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _iconoProductoPlaceholder(),
                          )
                        : _iconoProductoPlaceholder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  p.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textStrong),
                ),
                const SizedBox(height: 6),
                Text(formatearColones(p.precioUnitario), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  "Stock: ${p.stock}",
                  style: TextStyle(fontSize: 11, color: p.stock > 0 ? Colors.grey[500] : Colors.red),
                ),
              ],
            ),
            if (seleccionado)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                  child: Text("$cantidadEnCarrito", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // [dentroDeScrollExterno]: en móvil este panel va dentro de un
  // SingleChildScrollView que ya envuelve toda la pantalla (catálogo +
  // carrito), así que la lista de items no puede tener su propio scroll con
  // altura acotada (Expanded) porque el alto disponible es infinito ahí.
  Widget _panelCarrito({bool dentroDeScrollExterno = false}) {
    final Widget carritoVacio = Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            "Toca un producto\npara agregarlo aquí",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400]),
          ),
        ],
      ),
    );
    final Widget listaCarrito = _carrito.isEmpty
        ? (dentroDeScrollExterno ? carritoVacio : Center(child: carritoVacio))
        : ListView.separated(
            shrinkWrap: dentroDeScrollExterno,
            physics: dentroDeScrollExterno ? const NeverScrollableScrollPhysics() : null,
            padding: const EdgeInsets.all(16),
            itemCount: _carrito.length,
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemBuilder: (context, i) => _lineaCarrito(i),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: dentroDeScrollExterno ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Tu Cotización", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<Cliente>(
                value: _clienteSeleccionado,
                decoration: InputDecoration(
                  labelText: "Cliente *",
                  isDense: true,
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: _listaClientes.map((c) => DropdownMenuItem(value: c, child: Text(c.nombre, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _clienteSeleccionado = v),
              ),
            ],
          ),
        ),
        dentroDeScrollExterno
            ? listaCarrito
            : Expanded(child: listaCarrito),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.surfaceSubtle, border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(
            children: [
              _filaTotal("Subtotal", _carrito.fold(0.0, (s, i) => s + i.subtotal)),
              _filaTotal("IVA", _carrito.fold(0.0, (s, i) => s + i.montoIva)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(formatearColones(_totalGeneral), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_carrito.isEmpty || _clienteSeleccionado == null || _isSaving) ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text("GENERAR COTIZACIÓN", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lineaCarrito(int i) {
    final item = _carrito[i];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.producto.nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                "${formatearColones(item.precioUnitario)} c/u · ${item.impuesto?.nombre ?? 'Sin impuesto'} (${formatearNumero(item.porcentajeIva)}%)",
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _botonCantidad(Icons.remove, () => _decrementar(i)),
                  SizedBox(
                    width: 32,
                    child: Text("${item.cantidad}", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  _botonCantidad(Icons.add, () => _incrementar(i)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                    tooltip: "Editar precio y cantidad",
                    onPressed: () => _editarLineaCarrito(i),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatearColones(item.total), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _quitar(i),
              child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            ),
          ],
        ),
      ],
    );
  }

  Widget _botonCantidad(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 14),
      ),
    );
  }

  Widget _filaTotal(String label, double valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(formatearColones(valor), style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
