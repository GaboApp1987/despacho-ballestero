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
import 'actividad_economica.dart';
import 'factura.dart';
import 'widgets/automatizacion_factura.dart';

// Modelo temporal para los items del carrito
class LineaFactura {
  final Producto producto;
  int cantidad;
  // Precio en la moneda en que se definió (la del producto, o la de la
  // factura si se editó a mano): un alquiler cobrado en dólares queda en
  // US$ exactos aunque cambie el tipo de cambio. precioUnitario (abajo)
  // siempre da colones, que es como lo guarda el backend.
  double precioBase;
  String monedaPrecio; // 'CRC' | 'USD'
  final double Function() tipoCambio;
  Impuesto? impuesto;
  // Descuento por línea (AUDITORIA.md hallazgo A3) -- monto fijo en
  // colones, no porcentaje, para que quede claro exactamente cuánto se
  // rebajó (lo que exige Hacienda documentar en el XML, ver
  // generar_xml_v44/<Descuento>).
  double montoDescuento;
  String naturalezaDescuento;
  // Exoneración de IVA por línea (AUDITORIA.md hallazgo A3) -- para
  // vender sin impuesto (total o parcial) a clientes con autorización de
  // Hacienda. porcentajeExoneracion 100 = totalmente exenta.
  double porcentajeExoneracion;
  String tipoDocExoneracion;
  String numeroDocExoneracion;
  String nombreInstitucionExoneracion;
  DateTime? fechaEmisionDocExoneracion;

  LineaFactura({
    required this.producto,
    required this.cantidad,
    required this.tipoCambio,
    this.impuesto,
    this.montoDescuento = 0,
    this.naturalezaDescuento = '',
    this.porcentajeExoneracion = 0,
    this.tipoDocExoneracion = '',
    this.numeroDocExoneracion = '',
    this.nombreInstitucionExoneracion = '',
    this.fechaEmisionDocExoneracion,
  })  : precioBase = producto.precioUnitario,
        monedaPrecio = producto.monedaPrecio;

  /// Precio unitario en COLONES (lo que se guarda y se manda al backend).
  double get precioUnitario => monedaPrecio == 'USD' ? precioBase * tipoCambio() : precioBase;

  /// Fija un precio en colones (ej. el precio que se le dio antes a este cliente).
  set precioUnitario(double colones) {
    precioBase = colones;
    monedaPrecio = 'CRC';
  }

  void fijarPrecio(double valor, String moneda) {
    precioBase = valor;
    monedaPrecio = moneda;
  }

  double get porcentajeIva => impuesto?.porcentaje ?? 0.0;
  double get montoBruto => precioUnitario * cantidad;
  // Neto, ya con el descuento restado -- el IVA (abajo) se calcula sobre
  // esto, no sobre el bruto, igual que en el backend (ver
  // DetalleFactura.subtotal en models.py).
  double get subtotal => montoBruto - montoDescuento;
  // IVA a tarifa completa (bruto, sin exonerar) sobre el neto post-descuento.
  double get montoIvaBruto => subtotal * (porcentajeIva / 100);
  // Cuánto de ese IVA se perdona por la exoneración.
  double get montoExoneracion => montoIvaBruto * (porcentajeExoneracion / 100);
  // IVA NETO realmente cobrado -- este es el que se manda al backend como
  // monto_iva (ver DetalleFactura.monto_iva).
  double get montoIva => montoIvaBruto - montoExoneracion;
  double get total => subtotal + montoIva;
}

class FormularioFactura extends StatefulWidget {
  final Negocio negocio;
  /// "Repetir factura": se arma una nueva con los mismos datos que esta
  /// (cliente, productos, cantidades, precios, descuentos, moneda,
  /// condición) para revisarla y emitirla con la fecha de hoy -- nunca se
  /// emite sola.
  final Factura? plantilla;
  /// Cobro de una mesa del restaurante: llega con los platos ya puestos
  /// (como tiquete) y `camposExtra` (orden_restaurante) va en el POST para
  /// que el backend cierre la cuenta y libere la mesa.
  final List<({int productoId, int cantidad, double precio})>? lineasIniciales;
  final Map<String, dynamic>? camposExtra;
  /// 10% de servicio de restaurante: se muestra como línea aparte (con un
  /// interruptor por si el cliente no lo paga) y va como monto_servicio.
  final double servicioPorcentaje;
  /// Cobro de restaurante: campo de propina voluntaria. No suma en el total
  /// ni va a Hacienda; solo se registra (propina) para repartirla.
  final bool pedirPropina;
  const FormularioFactura({
    super.key,
    required this.negocio,
    this.plantilla,
    this.lineasIniciales,
    this.camposExtra,
    this.servicioPorcentaje = 0,
    this.pedirPropina = false,
  });

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
  // Actividades económicas adicionales del negocio (además de la principal,
  // configurada en Ajustes) -- si hay al menos una, se puede elegir cuál
  // aplica a esta venta puntual (ver ConfiguracionScreen). null = usar la
  // principal del negocio, igual que siempre.
  List<ActividadEconomica> _actividades = [];
  ActividadEconomica? _actividadSeleccionada;

  Cliente? _clienteSeleccionado;
  bool _isLoading = true;
  bool _isSaving = false;

  // "01" Factura Electrónica (exige cliente identificado) o "04" Tiquete
  // Electrónico (venta a consumidor final, cliente opcional) -- ver
  // Factura.tipo_documento en el backend.
  String _tipoDocumento = '01';
  late bool _cobrarServicio = widget.servicioPorcentaje > 0;
  double _propina = 0;
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
  // Recordatorios de cobro para esta factura (solo a crédito; ver
  // CobroAutomaticoEnFormulario).
  bool _cobroAutomatico = true;

  // El carrito/catálogo siempre trabaja en colones (precios del catálogo,
  // reportes, IVA/Renta, todo internamente en colones) -- si el cliente
  // pide facturar en dólares, esto solo afecta el documento final (XML/
  // Alanube dividen por tipoCambio, ver generar_xml_v44 en el backend) y
  // la vista previa del total en dólares acá abajo.
  String _moneda = 'CRC';
  final TextEditingController _tipoCambioController = TextEditingController(text: '1.00');

  // Tipo de cambio del día para convertir productos con precio en dólares
  // cuando la factura es en colones (con factura en dólares se usa el del
  // campo "Tipo de cambio").
  double? _tipoCambioDia;

  bool get _enDolares => _moneda == 'USD';

  double get _tipoCambioFactura {
    final tc = double.tryParse(_tipoCambioController.text.trim().replaceAll(',', '.')) ?? 0;
    return tc > 0 ? tc : 1.0;
  }

  /// Tipo de cambio para pasar precios en dólares a colones.
  double _tipoCambioConversion() => _enDolares ? _tipoCambioFactura : (_tipoCambioDia ?? _tipoCambioFactura);

  /// Muestra un monto (guardado en colones) en la moneda de la factura.
  String _fmt(double colones) => _enDolares ? formatearDolares(colones / _tipoCambioFactura) : formatearColones(colones);

  double _enMonedaFactura(double colones) => _enDolares ? colones / _tipoCambioFactura : colones;

  double _aColones(double valorEnMonedaFactura) => _enDolares ? valorEnMonedaFactura * _tipoCambioFactura : valorEnMonedaFactura;

  String get _simbolo => _enDolares ? r'$' : '₡';

  /// Llena el formulario con los datos de [p] (ver FormularioFactura.plantilla).
  /// Los precios se respetan en la moneda original de la factura: una de
  /// US$1500 se repite por US$1500 con el tipo de cambio de hoy.
  void _aplicarLineasIniciales(List<({int productoId, int cantidad, double precio})> lineas) {
    setState(() {
      _tipoDocumento = '04';
      _carrito.clear();
      for (final l in lineas) {
        final producto = _listaProductos.where((x) => x.id == l.productoId).firstOrNull;
        if (producto == null) continue;
        final linea = LineaFactura(producto: producto, cantidad: l.cantidad, impuesto: producto.impuesto, tipoCambio: _tipoCambioConversion);
        linea.fijarPrecio(l.precio, 'CRC');
        _carrito.add(linea);
      }
    });
  }

  Future<void> _aplicarPlantilla(Factura p) async {
    final esDolares = p.moneda == 'USD';
    if (esDolares) {
      _tipoCambioController.text = _textoTipoCambio(await _obtenerTipoCambioDelDia());
    }
    if (!mounted) return;
    final tcOriginal = p.tipoCambio > 0 ? p.tipoCambio : 1.0;
    final faltantes = <String>[];
    setState(() {
      _tipoDocumento = p.tipoDocumento;
      _esInterno = p.esInterno;
      _moneda = esDolares ? 'USD' : 'CRC';
      _condicionVenta = p.condicionVenta;
      _plazoCreditoController.text = '${p.plazoCredito}';
      _clienteSeleccionado = _listaClientes.where((c) => c.id == p.clienteId).firstOrNull ??
          _listaClientes.where((c) => c.cedula.isNotEmpty && c.cedula == p.receptorCedula).firstOrNull;
      _actividadSeleccionada = _actividades.where((a) => a.codigoActividad == p.codigoActividad).firstOrNull;
      _carrito.clear();
      for (final d in p.detalles) {
        final producto = _listaProductos.where((x) => x.id == d.productoId).firstOrNull;
        if (producto == null) {
          faltantes.add(d.nombreProducto);
          continue;
        }
        final linea = LineaFactura(
          producto: producto,
          cantidad: d.cantidad,
          impuesto: producto.impuesto,
          tipoCambio: _tipoCambioConversion,
          porcentajeExoneracion: d.porcentajeExoneracion,
          tipoDocExoneracion: d.tipoDocExoneracion,
          numeroDocExoneracion: d.numeroDocExoneracion,
          nombreInstitucionExoneracion: d.nombreInstitucionExoneracion,
          fechaEmisionDocExoneracion: DateTime.tryParse(d.fechaEmisionDocExoneracion ?? ''),
          naturalezaDescuento: d.naturalezaDescuento,
        );
        // Mismo precio y descuento que la original, en su moneda.
        if (esDolares) {
          linea.fijarPrecio(d.precioUnitario / tcOriginal, 'USD');
          linea.montoDescuento = d.montoDescuento / tcOriginal * _tipoCambioFactura;
        } else {
          linea.fijarPrecio(d.precioUnitario, 'CRC');
          linea.montoDescuento = d.montoDescuento;
        }
        _carrito.add(linea);
      }
    });
    if (_clienteSeleccionado != null) _cargarUltimosPreciosDe(_clienteSeleccionado!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(
        "Nueva factura armada a partir de la ${p.consecutivo}: revisala y emitila (sale con la fecha de hoy)."
        "${faltantes.isEmpty ? '' : ' No se agregaron porque ya no están en el catálogo: ${faltantes.join(', ')}.'}"
        "${!p.esTiquete && _clienteSeleccionado == null ? ' Elegí el cliente: ya no está en tu lista.' : ''}",
      ),
    ));
  }

  /// Tipo de cambio de venta de hoy (Hacienda/BCCR, ver /tipo-cambio/).
  /// Si no se pudo obtener devuelve 0 y avisa: nunca 1, que facturaba
  /// "en dólares" el mismo número que en colones.
  Future<double> _obtenerTipoCambioDelDia() async {
    try {
      final r = await ApiService.get('/tipo-cambio/');
      if (r.statusCode == 200) {
        final d = json.decode(utf8.decode(r.bodyBytes));
        if (d['disponible'] == true) return (d['venta'] as num).toDouble();
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("No se pudo obtener el tipo de cambio de hoy: escribilo a mano."),
      ));
    }
    return 0.0;
  }

  /// Texto para el campo de tipo de cambio: vacío si no se pudo obtener.
  String _textoTipoCambio(double tc) => tc > 1 ? tc.toStringAsFixed(2) : '';

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
    _tipoCambioController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final responses = await Future.wait([
        ApiService.get('/clientes/?negocio=${widget.negocio.id}'),
        ApiService.get('/productos/?negocio=${widget.negocio.id}'),
        ApiService.get('/actividades-economicas/?negocio=${widget.negocio.id}'),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final clientesData = json.decode(utf8.decode(responses[0].bodyBytes)) as List;
        final productosData = json.decode(utf8.decode(responses[1].bodyBytes)) as List;
        final actividadesData = responses[2].statusCode == 200
            ? json.decode(utf8.decode(responses[2].bodyBytes)) as List
            : [];

        if (mounted) {
          setState(() {
            _listaClientes = clientesData.map((j) => Cliente.fromJson(j)).toList();
            _listaProductos = productosData.map((j) => Producto.fromJson(j)).toList();
            _actividades = actividadesData.map((j) => ActividadEconomica.fromJson(j)).toList();
            _isLoading = false;
          });
          if (widget.plantilla != null) await _aplicarPlantilla(widget.plantilla!);
          if (widget.lineasIniciales != null) _aplicarLineasIniciales(widget.lineasIniciales!);
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
  double get _montoServicio => _cobrarServicio ? redondear2(_totalSubtotal * widget.servicioPorcentaje / 100) : 0;
  double get _totalFactura => _totalSubtotal + _totalIva + _montoServicio;

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
  Future<void> _agregarRapido(Producto p) async {
    final idx = _carrito.indexWhere((l) => l.producto.id == p.id);
    if (idx != -1) {
      setState(() => _carrito[idx].cantidad++);
      return;
    }
    // Producto con precio en dólares en una factura en colones: hace falta
    // el tipo de cambio del día para convertirlo.
    if (p.monedaPrecio == 'USD' && !_enDolares && _tipoCambioDia == null) {
      final tc = await _obtenerTipoCambioDelDia();
      _tipoCambioDia = tc > 1 ? tc : null;
      if (!mounted) return;
    }
    setState(() => _carrito.add(LineaFactura(producto: p, cantidad: 1, impuesto: p.impuesto, tipoCambio: _tipoCambioConversion)));
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

  /// Reparte un descuento general de toda la factura entre las líneas del
  /// carrito, proporcional al peso (precio*cantidad) de cada una -- Hacienda
  /// solo permite declarar descuentos POR LÍNEA (nodo <Descuento>, ver
  /// backend generar_xml_v44), no existe un "descuento de factura completa"
  /// en el XML v4.4, así que esto es lo que hace posible ofrecer un campo
  /// único en la UI sin dejar de declarar cada línea correctamente. La
  /// última línea se lleva el resto exacto (en vez de su parte
  /// proporcional redondeada) para que la suma de los descuentos por línea
  /// dé exactamente el monto pedido, sin quedar descuadrado por redondeo.
  /// Devuelve la lista de productos que quedarían por debajo del piso de
  /// costo+10% con ese descuento (vacía si todo bien) -- no aplica nada si
  /// la lista no está vacía, para no dejar precios por debajo del costo.
  List<String> _aplicarDescuentoGeneral(double montoTotalDescuento, String motivo) {
    if (_carrito.isEmpty) return [];
    final totalBruto = _carrito.fold<double>(0, (s, i) => s + i.montoBruto);
    if (totalBruto <= 0) return [];
    final montoLimitado = montoTotalDescuento.clamp(0, totalBruto).toDouble();

    final nuevosDescuentos = <double>[];
    double acumulado = 0;
    for (var i = 0; i < _carrito.length; i++) {
      final item = _carrito[i];
      double parte;
      if (i == _carrito.length - 1) {
        parte = redondear2(montoLimitado - acumulado);
      } else {
        parte = redondear2(montoLimitado * (item.montoBruto / totalBruto));
        acumulado += parte;
      }
      nuevosDescuentos.add(parte);
    }

    final productosBajoMinimo = <String>[];
    for (var i = 0; i < _carrito.length; i++) {
      final item = _carrito[i];
      final costo = item.producto.costo;
      if (costo <= 0) continue;
      final precioNetoUnitario = (item.montoBruto - nuevosDescuentos[i]) / item.cantidad;
      if (precioNetoUnitario < redondear2(costo * 1.10)) {
        productosBajoMinimo.add(item.producto.nombre);
      }
    }
    if (productosBajoMinimo.isNotEmpty) return productosBajoMinimo;

    setState(() {
      for (var i = 0; i < _carrito.length; i++) {
        _carrito[i].montoDescuento = nuevosDescuentos[i];
        _carrito[i].naturalezaDescuento = nuevosDescuentos[i] > 0 ? motivo : '';
      }
    });
    return [];
  }

  void _quitarDescuentoGeneral() {
    setState(() {
      for (final item in _carrito) {
        item.montoDescuento = 0;
        item.naturalezaDescuento = '';
      }
    });
  }

  void _editarDescuentoGeneral() {
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Agregue al menos un producto antes de aplicar un descuento general.")),
      );
      return;
    }
    String tipo = 'porcentaje'; // 'porcentaje' o 'monto'
    final valorCtrl = TextEditingController();
    final motivoCtrl = TextEditingController(text: 'Descuento general de factura');
    final totalBruto = _carrito.fold<double>(0, (s, i) => s + i.montoBruto);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final valor = double.tryParse(valorCtrl.text.replaceAll(',', '.')) ?? 0;
          // En colones: el monto fijo se escribe en la moneda de la factura.
          final montoResultante = tipo == 'porcentaje' ? totalBruto * (valor / 100) : _aColones(valor);
          return AlertDialog(
            title: const Text("Descuento general de la factura"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Se reparte proporcionalmente entre las ${_carrito.length} línea(s) del carrito "
                    "(Hacienda exige declarar el descuento por línea, no de la factura completa).",
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'porcentaje', label: Text("Porcentaje")),
                      ButtonSegment(value: 'monto', label: Text("Monto fijo")),
                    ],
                    selected: {tipo},
                    onSelectionChanged: (nuevo) => setDialogState(() => tipo = nuevo.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valorCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: tipo == 'porcentaje' ? "Porcentaje de descuento" : "Monto del descuento ($_simbolo)",
                      border: const OutlineInputBorder(),
                      prefixText: tipo == 'porcentaje' ? null : "$_simbolo ",
                      suffixText: tipo == 'porcentaje' ? "%" : null,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: motivoCtrl,
                    decoration: const InputDecoration(labelText: "Motivo", border: OutlineInputBorder()),
                  ),
                  if (valor > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      "Descuento total: ${_fmt(montoResultante)}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _quitarDescuentoGeneral();
                },
                child: const Text("Quitar descuento", style: TextStyle(color: Colors.red)),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () {
                  if (valor <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text("Ingrese un descuento válido")),
                    );
                    return;
                  }
                  final productosBajoMinimo = _aplicarDescuentoGeneral(montoResultante, motivoCtrl.text.trim());
                  if (productosBajoMinimo.isNotEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(
                        "Ese descuento deja por debajo del costo+10% a: ${productosBajoMinimo.join(', ')}. "
                        "Reduzca el descuento o ajuste el precio de esos productos.",
                      )),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                },
                child: const Text("Aplicar"),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Edición rápida de una línea: solo cantidad y precio unitario. El
  /// impuesto no se toca aquí — es el que tiene asignado el producto; para
  /// cambiarlo hay que editar el producto en el catálogo.
  // Catálogo de Hacienda para el tipo de documento de exoneración (v4.4) --
  // se usa tal cual en el XML (ver generar_xml_v44/<Exoneracion>/
  // TipoDocumento), así que hay que mandar el código, no el texto.
  static const Map<String, String> _tiposDocExoneracion = {
    '01': 'Compras autorizadas (régimen especial)',
    '05': 'Zona Franca',
    '07': 'Exenciones Dirección General de Hacienda',
    '09': 'Instituciones públicas',
    '99': 'Otros',
  };

  void _editarLineaCarrito(int index) {
    final item = _carrito[index];
    final cantidadCtrl = TextEditingController(text: item.cantidad.toString());
    final precioCtrl = TextEditingController(
      text: (item.monedaPrecio == _moneda ? item.precioBase : _enMonedaFactura(item.precioUnitario)).toStringAsFixed(2),
    );
    final descuentoCtrl = TextEditingController(text: item.montoDescuento > 0 ? _enMonedaFactura(item.montoDescuento).toStringAsFixed(2) : '');
    final naturalezaCtrl = TextEditingController(text: item.naturalezaDescuento);
    bool exonerado = item.porcentajeExoneracion > 0;
    final porcentajeExoneracionCtrl = TextEditingController(
      text: item.porcentajeExoneracion > 0 ? item.porcentajeExoneracion.toStringAsFixed(0) : '100',
    );
    String tipoDocExoneracion = item.tipoDocExoneracion.isNotEmpty ? item.tipoDocExoneracion : '99';
    final numeroDocExoneracionCtrl = TextEditingController(text: item.numeroDocExoneracion);
    final institucionExoneracionCtrl = TextEditingController(text: item.nombreInstitucionExoneracion);
    DateTime? fechaExoneracion = item.fechaEmisionDocExoneracion;

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
                decoration: InputDecoration(labelText: "Precio unitario ($_simbolo)", border: const OutlineInputBorder(), prefixText: "$_simbolo "),
                onChanged: (_) => setDialogState(() {}),
              ),
              if (anterior != null && precioCtrl.text != _enMonedaFactura(anterior.precioUnitario).toStringAsFixed(2)) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "A este cliente se le vendió antes a ${_fmt(anterior.precioUnitario)} "
                          "(F-${anterior.facturaConsecutivo}).",
                          style: TextStyle(fontSize: 12, color: AppColors.primary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          precioCtrl.text = _enMonedaFactura(anterior.precioUnitario).toStringAsFixed(2);
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
                    "Costo del producto: ${_fmt(costo)}\n"
                    "Precio mínimo permitido (costo + 10%): ${_fmt(precioMinimo)}",
                    style: TextStyle(fontSize: 12, color: Colors.amber[900], fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: descuentoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: "Descuento ($_simbolo, opcional)",
                  border: const OutlineInputBorder(),
                  prefixText: "$_simbolo ",
                  helperText: "Monto fijo, no porcentaje -- se resta del total de la línea.",
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
              if ((double.tryParse(descuentoCtrl.text.replaceAll(',', '.')) ?? 0) > 0) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: naturalezaCtrl,
                  decoration: const InputDecoration(
                    labelText: "Motivo del descuento",
                    border: OutlineInputBorder(),
                    hintText: "Ej. Pronto pago, promoción, cliente frecuente...",
                  ),
                ),
              ],
              const Divider(height: 28),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Venta exonerada de IVA"),
                subtitle: const Text("Cliente con autorización de Hacienda (institución pública, zona franca, etc.)", style: TextStyle(fontSize: 12)),
                value: exonerado,
                onChanged: (v) => setDialogState(() => exonerado = v),
              ),
              if (exonerado) ...[
                TextField(
                  controller: porcentajeExoneracionCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "% exonerado del IVA",
                    border: OutlineInputBorder(),
                    suffixText: "%",
                    helperText: "100 = totalmente exenta. Menos de 100 exonera solo esa parte del impuesto.",
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tipoDocExoneracion,
                  decoration: const InputDecoration(labelText: "Tipo de documento de exoneración", border: OutlineInputBorder()),
                  items: _tiposDocExoneracion.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => tipoDocExoneracion = v ?? '99'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numeroDocExoneracionCtrl,
                  decoration: const InputDecoration(labelText: "Número del documento de exoneración", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: institucionExoneracionCtrl,
                  decoration: const InputDecoration(
                    labelText: "Institución que autoriza",
                    border: OutlineInputBorder(),
                    hintText: "Ej. Ministerio de Hacienda, una municipalidad...",
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: ctx,
                      initialDate: fechaExoneracion ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (fecha != null) setDialogState(() => fechaExoneracion = fecha);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: "Fecha de emisión del documento", border: OutlineInputBorder()),
                    child: Text(
                      fechaExoneracion != null
                          ? "${fechaExoneracion!.day.toString().padLeft(2, '0')}/${fechaExoneracion!.month.toString().padLeft(2, '0')}/${fechaExoneracion!.year}"
                          : "Toque para elegir (hoy si se deja vacío)",
                    ),
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
              // Se escriben en la moneda de la factura; las validaciones de
              // abajo (costo, mínimo) trabajan en colones.
              final precioEscrito = double.tryParse(precioCtrl.text.replaceAll(',', '.'));
              final nuevoPrecio = precioEscrito == null ? null : _aColones(precioEscrito);
              final nuevoDescuento = _aColones(double.tryParse(descuentoCtrl.text.replaceAll(',', '.')) ?? 0);
              if (nuevaCantidad == null || nuevaCantidad <= 0 || nuevoPrecio == null || nuevoPrecio < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("Ingrese una cantidad y un precio válidos")),
                );
                return;
              }
              if (nuevoDescuento < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("El descuento no puede ser negativo")),
                );
                return;
              }
              final double montoBruto = nuevoPrecio * nuevaCantidad;
              if (nuevoDescuento > montoBruto) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("El descuento no puede ser mayor al total de la línea")),
                );
                return;
              }
              // El piso de costo+10% aplica al precio NETO (ya con el
              // descuento aplicado) -- si no, el descuento sería una forma
              // de esquivar el mínimo sin que se note.
              final double precioNetoUnitario = (montoBruto - nuevoDescuento) / nuevaCantidad;
              if (costo > 0 && precioNetoUnitario < precioMinimo) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(
                    "Con ese descuento, el precio neto (${_fmt(precioNetoUnitario)}) queda por debajo "
                    "del mínimo permitido (${_fmt(precioMinimo)})",
                  )),
                );
                return;
              }
              double nuevoPorcentajeExoneracion = 0;
              if (exonerado) {
                nuevoPorcentajeExoneracion = double.tryParse(porcentajeExoneracionCtrl.text.replaceAll(',', '.')) ?? 0;
                if (nuevoPorcentajeExoneracion <= 0 || nuevoPorcentajeExoneracion > 100) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("El porcentaje exonerado debe estar entre 1 y 100")),
                  );
                  return;
                }
                if (numeroDocExoneracionCtrl.text.trim().isEmpty || institucionExoneracionCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Complete el número de documento y la institución de la exoneración")),
                  );
                  return;
                }
              }
              setState(() {
                item.cantidad = nuevaCantidad;
                item.fijarPrecio(precioEscrito!, _moneda);
                item.montoDescuento = nuevoDescuento;
                item.naturalezaDescuento = nuevoDescuento > 0 ? naturalezaCtrl.text.trim() : '';
                item.porcentajeExoneracion = exonerado ? nuevoPorcentajeExoneracion : 0;
                item.tipoDocExoneracion = exonerado ? tipoDocExoneracion : '';
                item.numeroDocExoneracion = exonerado ? numeroDocExoneracionCtrl.text.trim() : '';
                item.nombreInstitucionExoneracion = exonerado ? institucionExoneracionCtrl.text.trim() : '';
                item.fechaEmisionDocExoneracion = exonerado ? (fechaExoneracion ?? DateTime.now()) : null;
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

    // Si el tipo de cambio quedó vacío o inválido, antes se guardaba
    // silenciosamente en 1 (factura en dólares con el mismo valor numérico
    // que en colones) -- mejor avisar y no dejar seguir.
    final tipoCambio = double.tryParse(_tipoCambioController.text.trim().replaceAll(',', '.'));
    if (_moneda == 'USD' && (tipoCambio == null || tipoCambio <= 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingrese un tipo de cambio válido para facturar en dólares.")),
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
        'monto_servicio': redondear2(_montoServicio),
        if (widget.pedirPropina) 'propina': redondear2(_propina),
        'condicion_venta': _condicionVenta,
        'cobro_automatico': _condicionVenta == "02" ? _cobroAutomatico : true,
        'plazo_credito': plazoCredito,
        'moneda': _moneda,
        'tipo_cambio': tipoCambio ?? 1.0,
        if (_actividadSeleccionada != null) ...{
          'codigo_actividad': _actividadSeleccionada!.codigoActividad,
          'alanube_economic_activity': _actividadSeleccionada!.alanubeEconomicActivity ?? '',
        },
        'detalles': _carrito.map((item) => {
          'producto': item.producto.id,
          'cantidad': item.cantidad,
          'precio_unitario': redondear2(item.precioUnitario),
          // Tiquete Interno nunca lleva IVA -- el backend también lo exige
          // (ver FacturaSerializer.validate). Por lo mismo, tampoco tiene
          // sentido una exoneración de un impuesto que ya es 0 ahí.
          'monto_iva': _esInterno ? 0 : redondear2(item.montoIva),
          'subtotal': redondear2(item.subtotal),
          'monto_descuento': redondear2(item.montoDescuento),
          'naturaleza_descuento': item.naturalezaDescuento,
          'porcentaje_exoneracion': _esInterno ? 0 : item.porcentajeExoneracion,
          'monto_exoneracion': _esInterno ? 0 : redondear2(item.montoExoneracion),
          'tipo_doc_exoneracion': item.tipoDocExoneracion,
          'numero_doc_exoneracion': item.numeroDocExoneracion,
          'nombre_institucion_exoneracion': item.nombreInstitucionExoneracion,
          if (item.fechaEmisionDocExoneracion != null)
            'fecha_emision_doc_exoneracion': item.fechaEmisionDocExoneracion!.toIso8601String().split('T')[0],
        }).toList(),
        ...?widget.camposExtra,
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

  Widget _filaPropina() {
    final base = _totalSubtotal;
    Widget opcion(String texto, double monto) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(texto),
            selected: (_propina - monto).abs() < 0.01,
            onSelected: (_) => setState(() => _propina = monto),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text("Propina", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Expanded(child: Text("(aparte, no va en el comprobante)", style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          if (_propina > 0) Text(_fmt(_propina), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            opcion("Ninguna", 0),
            opcion("5%", redondear2(base * 0.05)),
            opcion("10%", redondear2(base * 0.10)),
            ActionChip(
              label: const Text("Otro monto"),
              onPressed: () async {
                final ctrl = TextEditingController(text: _propina > 0 ? _propina.toStringAsFixed(0) : '');
                final monto = await showDialog<double>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Propina"),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: "₡ ", border: OutlineInputBorder()),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
                      FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0), child: const Text("Listo")),
                    ],
                  ),
                );
                if (monto != null) setState(() => _propina = monto < 0 ? 0 : monto);
              },
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.plantilla != null
            ? "Repetir ${widget.plantilla!.esTiquete ? 'tiquete' : 'factura'} ${widget.plantilla!.consecutivo}"
            : (_esInterno ? "Nuevo Tiquete Interno" : (_esTiquete ? "Nuevo Tiquete" : "Nueva Factura"))),
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

              // 🧾 Panel tipo "Tu Factura". En móvil este panel ya vive
              // dentro del SingleChildScrollView de toda la página (ver
              // más abajo), pero en escritorio no tiene ningún ancestro con
              // scroll -- ahí el encabezado (cliente, condición, actividad,
              // moneda/tipo de cambio) comparte una altura FIJA con
              // Expanded(child: listaCarrito), así que cuanto más creciera
              // el encabezado, más se apretaba el carrito hasta casi
              // desaparecer ("estático", sin ver lo que se agregaba). Se le
              // da su propio scroll para que el carrito siempre se vea
              // completo sin importar cuántos campos tenga arriba.
              final panelFactura = Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    left: anchoCorto ? BorderSide.none : BorderSide(color: AppColors.border),
                    top: anchoCorto ? BorderSide(color: AppColors.border) : BorderSide.none,
                  ),
                ),
                child: anchoCorto
                    ? _panelCarrito(dentroDeScrollExterno: true)
                    : SingleChildScrollView(child: _panelCarrito(dentroDeScrollExterno: true)),
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
                Text(p.monedaPrecio == 'USD' ? formatearDolares(p.precioUnitario) : formatearColones(p.precioUnitario),
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
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
              if (_condicionVenta == "02" && !_esInterno)
                CobroAutomaticoEnFormulario(
                  negocioId: widget.negocio.id,
                  activo: _cobroAutomatico,
                  onCambio: (v) => setState(() => _cobroAutomatico = v),
                ),
              if (_actividades.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<ActividadEconomica?>(
                  value: _actividadSeleccionada,
                  decoration: InputDecoration(
                    labelText: "Actividad económica",
                    isDense: true,
                    prefixIcon: const Icon(Icons.work_outline, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: [
                    const DropdownMenuItem<ActividadEconomica?>(value: null, child: Text("Principal del negocio")),
                    ..._actividades.map((a) => DropdownMenuItem(value: a, child: Text(a.etiqueta, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _actividadSeleccionada = v),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _moneda,
                      decoration: InputDecoration(
                        labelText: "Moneda",
                        isDense: true,
                        prefixIcon: const Icon(Icons.currency_exchange, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: "CRC", child: Text("Colones")),
                        DropdownMenuItem(value: "USD", child: Text("Dólares")),
                      ],
                      onChanged: (val) async {
                        final tcActual = double.tryParse(_tipoCambioController.text.trim().replaceAll(',', '.')) ?? 0;
                        if (val == 'USD' && tcActual <= 1) {
                          _tipoCambioController.text = _textoTipoCambio(await _obtenerTipoCambioDelDia());
                        }
                        // Si ya hay productos en dólares en el carrito, la factura en
                        // colones los convierte con el tipo de cambio del día.
                        if (val == 'CRC' && _tipoCambioDia == null && _carrito.any((l) => l.monedaPrecio == 'USD')) {
                          final tc = await _obtenerTipoCambioDelDia();
                          _tipoCambioDia = tc > 1 ? tc : null;
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
                        // Sin esto la vista previa "≈ US$" de abajo no se
                        // refresca al escribir un tipo de cambio nuevo (sigue
                        // mostrando el cálculo con el valor anterior), dando
                        // la impresión de que el cambio no se guardó aunque
                        // sí quede en el controller.
                        onChanged: (_) => setState(() {}),
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
                  "Los montos se muestran y se editan en dólares. Los productos con precio en "
                  "colones se convierten con este tipo de cambio (según BCCR, ajustable).",
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(builder: (context) {
                    final totalDescuento = _carrito.fold<double>(0, (s, i) => s + i.montoDescuento);
                    return totalDescuento > 0
                        ? Text(
                            "Descuento general: -${_fmt(totalDescuento)}",
                            style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                          )
                        : const SizedBox.shrink();
                  }),
                  TextButton.icon(
                    onPressed: _isSaving ? null : _editarDescuentoGeneral,
                    icon: const Icon(Icons.sell_outlined, size: 16),
                    label: const Text("Descuento general", style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  ),
                ],
              ),
              _filaResumen("Subtotal", _fmt(_totalSubtotal)),
              _filaResumen("IVA", _fmt(_totalIva)),
              if (widget.servicioPorcentaje > 0)
                Row(children: [
                  SizedBox(
                    height: 32,
                    child: Switch(value: _cobrarServicio, onChanged: (v) => setState(() => _cobrarServicio = v)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text("Servicio ${widget.servicioPorcentaje.toStringAsFixed(0)}%")),
                  Text(_fmt(_montoServicio)),
                ]),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(_fmt(_totalFactura), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary)),
                ],
              ),
              if (widget.pedirPropina) _filaPropina(),
              if (_moneda == 'USD') ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "≈ ${formatearColones(_totalFactura)} (tipo de cambio ${formatearNumero(_tipoCambioFactura)})",
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ),
              ],
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
                    ? "${_fmt(item.precioUnitario)} c/u · Sin impuesto (interno)"
                    : "${_fmt(item.precioUnitario)} c/u · ${item.impuesto?.nombre ?? 'Sin impuesto'} (${formatearNumero(item.porcentajeIva)}%)",
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              if (item.montoDescuento > 0)
                Text(
                  "Descuento: -${_fmt(item.montoDescuento)}"
                  "${item.naturalezaDescuento.isNotEmpty ? ' (${item.naturalezaDescuento})' : ''}",
                  style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                ),
              if (item.porcentajeExoneracion > 0)
                Text(
                  "Exonerado ${item.porcentajeExoneracion.toStringAsFixed(0)}% del IVA: -${_fmt(item.montoExoneracion)}"
                  "${item.nombreInstitucionExoneracion.isNotEmpty ? ' (${item.nombreInstitucionExoneracion})' : ''}",
                  style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
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
                      "A este cliente: ${_fmt(anterior.precioUnitario)} antes · tocar para usar",
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
            Text(_fmt(_esInterno ? item.subtotal : item.total), style: const TextStyle(fontWeight: FontWeight.bold)),
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
