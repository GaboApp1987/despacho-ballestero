import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'cambiar_plan_screen.dart';
import 'cliente.dart';
import 'negocio.dart';
import 'producto.dart';
import 'impuesto.dart';
import 'formato.dart';
import 'historial_precio_cliente.dart';

// Modelo temporal para los items del carrito
class LineaFactura {
  final Producto producto;
  int cantidad;
  double precioUnitario;
  Impuesto? impuesto;

  LineaFactura({
    required this.producto,
    required this.cantidad,
    this.impuesto,
  }) : precioUnitario = producto.precioUnitario;

  double get porcentajeIva => impuesto?.porcentaje ?? 0.0;
  double get subtotal => precioUnitario * cantidad;
  double get montoIva => subtotal * (porcentajeIva / 100);
  double get total => subtotal + montoIva;
}

class FormularioFactura extends StatefulWidget {
  final Negocio negocio;
  const FormularioFactura({super.key, required this.negocio});

  @override
  State<FormularioFactura> createState() => _FormularioFacturaState();
}

class _FormularioFacturaState extends State<FormularioFactura> {
  // Por debajo de este ancho el catálogo y el carrito se apilan en vertical
  // en vez de ir lado a lado (que en un teléfono no cabe: el panel del
  // carrito por sí solo mide 380px de ancho fijo).
  static const double _anchoBreakpointMovil = 700;

  final TextEditingController _consecutivoController = TextEditingController();
  final TextEditingController _plazoCreditoController = TextEditingController(text: "0");

  // Lista de productos en la factura actual
  final List<LineaFactura> _carrito = [];

  List<Cliente> _listaClientes = [];
  List<Producto> _listaProductos = [];

  Cliente? _clienteSeleccionado;
  bool _isLoading = true;
  bool _isSaving = false;

  // "01" Factura Electrónica (exige cliente identificado) o "04" Tiquete
  // Electrónico (venta a consumidor final, cliente opcional) -- ver
  // Factura.tipo_documento en el backend.
  String _tipoDocumento = '01';
  bool get _esTiquete => _tipoDocumento == '04';

  // Tiquete Interno (solo tiene sentido dentro de Tiquete): no es fiscal, no
  // se envía a Hacienda y no lleva impuestos -- ver Factura.es_interno en el
  // backend. Pensado para muestras, consumo propio, ajustes, etc.
  bool _esInterno = false;

  // Ultimo precio que se le cobro a CADA producto al cliente seleccionado
  // (producto.id -> ese registro), para sugerirlo al agregar/editar una
  // linea en vez de partir siempre del precio de catalogo -- ver
  // ClienteViewSet.historial_precios en el backend.
  Map<int, PrecioHistoricoCliente> _ultimoPrecioPorProducto = {};

  // Manejo de Crédito
  String _condicionVenta = "01"; // "01" = Contado, "02" = Crédito

  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  int? _categoriaFiltro;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
    _busquedaCtrl.addListener(() {
      setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _consecutivoController.dispose();
    _plazoCreditoController.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final responses = await Future.wait([
        ApiService.get('/clientes/?negocio=${widget.negocio.id}'),
        ApiService.get('/productos/?negocio=${widget.negocio.id}'),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final clientesData = json.decode(utf8.decode(responses[0].bodyBytes)) as List;
        final productosData = json.decode(utf8.decode(responses[1].bodyBytes)) as List;

        if (mounted) {
          setState(() {
            _listaClientes = clientesData.map((j) => Cliente.fromJson(j)).toList();
            _listaProductos = productosData.map((j) => Producto.fromJson(j)).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Trae el historial de precios del cliente y se queda solo con el mas
  /// reciente por producto (el backend ya lo devuelve ordenado del mas
  /// nuevo al mas viejo, asi que basta con quedarse con la primera
  /// aparicion de cada producto_id).
  Future<void> _cargarUltimosPreciosDe(Cliente cliente) async {
    try {
      final response = await ApiService.get('/clientes/${cliente.id}/historial-precios/');
      if (response.statusCode != 200) return;
      final data = json.decode(utf8.decode(response.bodyBytes)) as List;
      final historial = data.map((j) => PrecioHistoricoCliente.fromJson(j)).toList();
      final ultimos = <int, PrecioHistoricoCliente>{};
      for (final registro in historial) {
        ultimos.putIfAbsent(registro.productoId, () => registro);
      }
      if (mounted) setState(() => _ultimoPrecioPorProducto = ultimos);
    } catch (_) {
      // Si falla, simplemente no hay sugerencia de precio anterior -- no
      // bloquea poder facturar.
      if (mounted) setState(() => _ultimoPrecioPorProducto = {});
    }
  }

  // Totales generales de la factura
  double get _totalSubtotal => _carrito.fold(0, (sum, item) => sum + item.subtotal);
  // Un Tiquete Interno nunca lleva impuestos (ver Factura.es_interno en el
  // backend, que además rechaza cualquier IVA distinto de 0 en sus líneas).
  double get _totalIva => _esInterno ? 0 : _carrito.fold(0, (sum, item) => sum + item.montoIva);
  double get _totalFactura => _totalSubtotal + _totalIva;

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
  /// el producto en el catálogo, no aquí.
  void _agregarRapido(Producto p) {
    final idx = _carrito.indexWhere((l) => l.producto.id == p.id);
    if (idx != -1) {
      setState(() => _carrito[idx].cantidad++);
    } else {
      setState(() => _carrito.add(LineaFactura(producto: p, cantidad: 1, impuesto: p.impuesto)));
    }
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

  /// Edición rápida de una línea: solo cantidad y precio unitario. El
  /// impuesto no se toca aquí — es el que tiene asignado el producto; para
  /// cambiarlo hay que editar el producto en el catálogo.
  void _editarLineaCarrito(int index) {
    final item = _carrito[index];
    final cantidadCtrl = TextEditingController(text: item.cantidad.toString());
    final precioCtrl = TextEditingController(text: item.precioUnitario.toStringAsFixed(2));

    // No se debe facturar por debajo del costo + 10% de margen mínimo. Si el
    // producto no tiene costo cargado (0), no hay piso que exigir.
    final double costo = item.producto.costo;
    final double precioMinimo = redondear2(costo * 1.10);

    // Si a ESTE cliente ya se le vendió este producto antes a otro precio,
    // se lo sugerimos con un botón de un toque en vez de que tenga que
    // acordarse o ir a revisar el historial.
    final PrecioHistoricoCliente? anterior = _ultimoPrecioPorProducto[item.producto.id];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
                onChanged: (_) => setDialogState(() {}),
              ),
              if (anterior != null && precioCtrl.text != anterior.precioUnitario.toStringAsFixed(2)) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "A este cliente se le vendió antes a ${formatearColones(anterior.precioUnitario)} "
                          "(F-${anterior.facturaConsecutivo}).",
                          style: TextStyle(fontSize: 12, color: AppColors.primary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          precioCtrl.text = anterior.precioUnitario.toStringAsFixed(2);
                        }),
                        child: const Text("Usar", style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
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
      ),
    );
  }

  Future<void> _guardarFactura() async {
    // En Tiquete Electrónico el cliente es opcional (venta a consumidor
    // final sin identificar) -- en Factura Electrónica sigue siendo
    // obligatorio, igual que antes.
    if ((!_esTiquete && _clienteSeleccionado == null) || _carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_esTiquete
            ? "Agregue al menos un producto."
            : "Por favor seleccione un cliente y al menos un producto.")),
      );
      return;
    }

    final int plazoCredito = int.tryParse(_plazoCreditoController.text) ?? 0;
    // Hacienda exige el plazo de crédito (Art. 27 Ley IVA) en toda factura a
    // crédito -- sin esto la factura se crea bien pero Alanube la rechaza
    // al enviarla (queda en "Error Técnico"), un error que solo se ve
    // despues, no al guardar.
    if (_condicionVenta == "02" && plazoCredito <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingrese los días de crédito: son obligatorios para Hacienda en una venta a crédito.")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final body = {
        'negocio': widget.negocio.id,
        'tipo_documento': _tipoDocumento,
        'es_interno': _esInterno,
        if (_clienteSeleccionado != null) 'cliente': _clienteSeleccionado!.id,
        'consecutivo': _consecutivoController.text.trim(),
        'receptor_nombre': _clienteSeleccionado?.nombre ?? '',
        'receptor_cedula': _clienteSeleccionado?.cedula,
        'total_iva': redondear2(_totalIva),
        'total_factura': redondear2(_totalFactura),
        'condicion_venta': _condicionVenta,
        'plazo_credito': plazoCredito,
        'detalles': _carrito.map((item) => {
          'producto': item.producto.id,
          'cantidad': item.cantidad,
          'precio_unitario': redondear2(item.precioUnitario),
          // Tiquete Interno nunca lleva IVA -- el backend también lo exige
          // (ver FacturaSerializer.validate).
          'monto_iva': _esInterno ? 0 : redondear2(item.montoIva),
          'subtotal': redondear2(item.subtotal)
        }).toList(),
      };

      final response = await ApiService.post('/facturas/', body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else if (response.statusCode == 403) {
        // Ademas de la suscripcion suspendida, este 403 tambien cubre el
        // limite mensual de facturas del plan (ver
        // FacturaViewSet.perform_create) -- si es ese caso, se ofrece ir
        // directo a cambiar de plan en vez de solo mostrar el error.
        final datos = json.decode(utf8.decode(response.bodyBytes));
        final detalle = (datos['detail'] ?? 'No se pudo registrar la factura.').toString();
        if (mounted) {
          final esLimiteDePlan = detalle.toLowerCase().contains('límite') || detalle.toLowerCase().contains('limite');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(detalle),
              duration: const Duration(seconds: 8),
              action: esLimiteDePlan
                  ? SnackBarAction(
                      label: "Actualizar plan",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CambiarPlanScreen(negocio: widget.negocio)),
                        );
                      },
                    )
                  : null,
            ),
          );
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al registrar factura: $e")),
        );
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
        title: Text(_esInterno ? "Nuevo Tiquete Interno" : (_esTiquete ? "Nuevo Tiquete" : "Nueva Factura")),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
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

              // 🧾 Panel tipo "Tu Factura"
              final panelFactura = Container(
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
                // En móvil primero va lo que ya se decidió (cliente,
                // condición y los productos ya seleccionados con su total),
                // y hasta abajo el catálogo para seguir agregando más.
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      panelFactura,
                      const Divider(height: 1),
                      construirCatalogo(expandirGrid: false),
                    ],
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(flex: 7, child: construirCatalogo(expandirGrid: true)),
                  SizedBox(width: 380, child: panelFactura),
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
              const Text("Tu Factura", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '01', label: Text("Factura"), icon: Icon(Icons.receipt_long_outlined)),
                  ButtonSegment(value: '04', label: Text("Tiquete"), icon: Icon(Icons.confirmation_number_outlined)),
                ],
                selected: {_tipoDocumento},
                onSelectionChanged: (seleccion) => setState(() {
                  _tipoDocumento = seleccion.first;
                  if (!_esTiquete) _esInterno = false;
                }),
              ),
              if (_esTiquete) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _esInterno,
                  onChanged: (v) => setState(() => _esInterno = v ?? false),
                  title: const Text("Tiquete interno", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    "Sin impuestos y no se envía a Hacienda (uso interno, muestras, ajustes).",
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<Cliente>(
                value: _clienteSeleccionado,
                decoration: InputDecoration(
                  labelText: _esTiquete ? "Cliente (opcional)" : "Cliente *",
                  isDense: true,
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: _listaClientes.map((c) => DropdownMenuItem(value: c, child: Text(c.nombre, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) {
                  setState(() {
                    _clienteSeleccionado = v;
                    _ultimoPrecioPorProducto = {};
                  });
                  if (v != null) _cargarUltimosPreciosDe(v);
                },
              ),
              if (_esTiquete) ...[
                const SizedBox(height: 4),
                Text(
                  "Sin cliente se factura a Consumidor Final.",
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _condicionVenta,
                      decoration: InputDecoration(
                        labelText: "Condición",
                        isDense: true,
                        prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: "01", child: Text("Contado")),
                        DropdownMenuItem(value: "02", child: Text("Crédito")),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _condicionVenta = val!;
                          if (_condicionVenta == "01") {
                            _plazoCreditoController.text = "0";
                          }
                        });
                      },
                    ),
                  ),
                  if (_condicionVenta == "02") ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _plazoCreditoController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Días",
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
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
              _filaResumen("Subtotal", formatearColones(_totalSubtotal)),
              _filaResumen("IVA", formatearColones(_totalIva)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(formatearColones(_totalFactura), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_carrito.isEmpty || (!_esTiquete && _clienteSeleccionado == null) || _isSaving)
                      ? null
                      : _guardarFactura,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Text(_esInterno ? "EMITIR TIQUETE INTERNO" : (_esTiquete ? "EMITIR TIQUETE" : "EMITIR FACTURA"),
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                _esInterno
                    ? "${formatearColones(item.precioUnitario)} c/u · Sin impuesto (interno)"
                    : "${formatearColones(item.precioUnitario)} c/u · ${item.impuesto?.nombre ?? 'Sin impuesto'} (${formatearNumero(item.porcentajeIva)}%)",
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Builder(builder: (context) {
                final anterior = _ultimoPrecioPorProducto[item.producto.id];
                if (anterior == null || anterior.precioUnitario == item.precioUnitario) {
                  return const SizedBox.shrink();
                }
                return InkWell(
                  onTap: () => setState(() => item.precioUnitario = anterior.precioUnitario),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      "A este cliente: ${formatearColones(anterior.precioUnitario)} antes · tocar para usar",
                      style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }),
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
            Text(formatearColones(_esInterno ? item.subtotal : item.total), style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _filaResumen(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
