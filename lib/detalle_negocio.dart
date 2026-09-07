import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

import 'api_service.dart';
import 'cliente.dart';
import 'configuracion_screen.dart';
import 'cotizacion.dart';
import 'crear_cliente.dart';
import 'detalle_factura_screen.dart';
import 'factura.dart';
import 'compras_screen.dart';
import 'gastos_screen.dart';
import 'declaracion_fiscal_widgets.dart';
import 'formulario_factura.dart';
import 'historial_precios_cliente_screen.dart';
import 'inventario_screen.dart';
import 'negocio.dart';
import 'cuentas_por_cobrar_screen.dart';
import 'cuentas_por_pagar_screen.dart';
import 'empleados_screen.dart';
import 'export_service.dart';
import 'impuestos_screen.dart';
import 'reportes_screen.dart';
import 'tarjeta_lealtad_screen.dart';
import 'addons_screen.dart';
import 'login.dart';
import 'formato.dart';
import 'widgets/bloqueo_salida_raiz.dart';
import 'widgets/soporte_chat.dart';

class DetalleNegocio extends StatefulWidget {
  final Negocio negocio;
  // null = dueño del negocio (o socio/despacho administrandolo): acceso
  // completo. 'cajero' o 'completo' = un EmpleadoNegocio -- ver
  // _menuItemsVisibles, que oculta secciones para 'cajero' (el backend ya
  // bloquea las escrituras correspondientes de todas formas; esto es para
  // que la UI no muestre botones que van a fallar).
  final String? rolEmpleado;

  const DetalleNegocio({super.key, required this.negocio, this.rolEmpleado});

  @override
  _DetalleNegocioState createState() => _DetalleNegocioState();
}

class _DetalleNegocioState extends State<DetalleNegocio> {
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  String _nombreUsuario = "Usuario";

  int _seccionActiva = 1;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Por debajo de este ancho la navegacion pasa a un Drawer deslizable (con
  // la lista vertical de siempre) en vez de la barra de pildoras horizontal
  // de escritorio, que en un telefono no entra.
  static const double _anchoBreakpointMovil = 700;

  // Cada seccion de la app, compartida entre la barra de pildoras de
  // escritorio (_buildPillTabsBar) y la lista vertical del Drawer movil
  // (_itemsMenu) -- un solo lugar para agregar/quitar secciones.
  static const List<({int id, IconData icono, String titulo})> _menuItems = [
    (id: 1, icono: Icons.pie_chart_outline, titulo: "Dashboard"),
    (id: 0, icono: Icons.receipt_long_outlined, titulo: "Facturas"),
    (id: 2, icono: Icons.people_outline, titulo: "Clientes"),
    (id: 6, icono: Icons.monetization_on_outlined, titulo: "Cuentas por Cobrar"),
    (id: 3, icono: Icons.inventory_2_outlined, titulo: "Inventario"),
    (id: 8, icono: Icons.shopping_cart_outlined, titulo: "Compras"),
    (id: 13, icono: Icons.local_shipping_outlined, titulo: "Cuentas por Pagar"),
    (id: 9, icono: Icons.receipt_long_outlined, titulo: "Gastos"),
    (id: 4, icono: Icons.request_quote_outlined, titulo: "Cotizaciones"),
    (id: 7, icono: Icons.percent, titulo: "Impuestos"),
    (id: 10, icono: Icons.bar_chart_outlined, titulo: "Reportes"),
    (id: 11, icono: Icons.loyalty_outlined, titulo: "Tarjeta de Lealtad"),
    (id: 12, icono: Icons.extension_outlined, titulo: "Add-ons"),
    (id: 5, icono: Icons.settings_outlined, titulo: "Ajustes"),
    (id: 14, icono: Icons.badge_outlined, titulo: "Empleados"),
  ];

  // Secciones ocultas para un empleado con rol 'cajero' -- el backend ya
  // bloquea la escritura/lectura correspondiente de todas formas (ver
  // BloqueaCajeroMixin y los chequeos de es_cajero en views.py), esto es
  // solo para no mostrar botones que van a fallar. 'completo' ve todo esto.
  static const Set<int> _idsOcultosParaCajero = {6, 8, 13, 9, 7, 10, 11, 12, 5};

  List<({int id, IconData icono, String titulo})> get _menuItemsVisibles {
    // "Empleados" (id 14) es exclusivo del dueño real -- ni 'cajero' ni
    // 'completo' pueden gestionar otros empleados (ver
    // SoloDuenoDelNegocioMixin en el backend).
    var items = widget.rolEmpleado == null ? _menuItems : _menuItems.where((m) => m.id != 14).toList();
    if (widget.rolEmpleado == 'cajero') {
      items = items.where((m) => !_idsOcultosParaCajero.contains(m.id)).toList();
    }
    return items;
  }

  Map<String, dynamic>? _tipoCambio;
  Negocio? _negocioActualizado;

  late Future<List<Factura>> _facturasFuture;
  late Future<Map<String, dynamic>> _metricasFuture;
  late Future<List<Cliente>> _clientesFuture;
  late Future<List<dynamic>> _saldosCxCFuture;
  late Future<List<Factura>> _vencidasFuture; // 👈 Nuevo: Facturas vencidas globales
  late Future<Map<String, dynamic>> _declaracionIvaFuture;
  late int _anioRenta;
  late Future<Map<String, dynamic>> _declaracionRentaFuture;

  final TextEditingController _busquedaClientesCtrl = TextEditingController();
  String _busquedaClientes = '';

  @override
  void initState() {
    super.initState();
    DateTime ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month + 1, 0);
    _anioRenta = ahora.year;
    _cargarNombreUsuario();
    _cargarTipoCambio();
    _cargarNegocioActualizado();
    _busquedaClientesCtrl.addListener(() {
      setState(() => _busquedaClientes = _busquedaClientesCtrl.text.trim().toLowerCase());
    });

    _facturasFuture = obtenerFacturas();
    _metricasFuture = obtenerMetricasDashboard();
    _clientesFuture = obtenerClientes();
    _saldosCxCFuture = obtenerSaldosGlobales();
    _vencidasFuture = obtenerFacturasVencidas();
    _declaracionIvaFuture = obtenerDeclaracionIva();
    _declaracionRentaFuture = obtenerDeclaracionRenta();
  }

  @override
  void dispose() {
    _busquedaClientesCtrl.dispose();
    super.dispose();
  }

  void _cambiarAnioRenta(int nuevoAnio) {
    if (!mounted) return;
    setState(() {
      _anioRenta = nuevoAnio;
      _declaracionRentaFuture = obtenerDeclaracionRenta();
    });
  }

  Future<void> _cargarTipoCambio() async {
    try {
      final response = await ApiService.get('/tipo-cambio/');
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _tipoCambio = json.decode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {
      // Si falla, simplemente no se muestra el tipo de cambio.
    }
  }

  Future<void> _cargarNegocioActualizado() async {
    try {
      final response = await ApiService.get('/negocios/${widget.negocio.id}/');
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _negocioActualizado = Negocio.fromJson(json.decode(utf8.decode(response.bodyBytes))));
      }
    } catch (_) {
      // Si falla, se sigue usando la cuota que traía el negocio al entrar.
    }
  }

  Negocio get _negocioConCuota => _negocioActualizado ?? widget.negocio;

  Future<void> _cargarNombreUsuario() async {
    try {
      final response = await ApiService.get('/mi-perfil/');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() => _nombreUsuario = data['nombre'] ?? "Usuario");
      }
    } catch (_) {
      // Si falla, se queda con el valor por defecto "Usuario".
    }
  }

  void _recargarDatos({bool facturas = true, bool clientes = false}) {
    if (!mounted) return;
    setState(() {
      if (facturas) {
        _facturasFuture = obtenerFacturas();
        _metricasFuture = obtenerMetricasDashboard();
        _saldosCxCFuture = obtenerSaldosGlobales();
        _vencidasFuture = obtenerFacturasVencidas();
        _declaracionIvaFuture = obtenerDeclaracionIva();
        _cargarNegocioActualizado();
      }
      if (clientes) {
        _clientesFuture = obtenerClientes();
      }
    });
  }

  void _cambiarSeccion(int id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _seccionActiva = id);
    });
  }

  Future<List<Factura>> obtenerFacturas() async {
    String inicioStr = "${_fechaInicio.year}-${_fechaInicio.month.toString().padLeft(2, '0')}-${_fechaInicio.day.toString().padLeft(2, '0')}";
    String finStr = "${_fechaFin.year}-${_fechaFin.month.toString().padLeft(2, '0')}-${_fechaFin.day.toString().padLeft(2, '0')}";

    final response = await ApiService.get(
      '/facturas/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr',
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((item) => Factura.fromJson(item)).toList();
    } else {
      throw Exception('Error al obtener facturas: ${response.statusCode}');
    }
  }

  Future<List<Factura>> obtenerFacturasVencidas() async {
    // Buscamos todas las facturas a crédito no pagadas del negocio
    final response = await ApiService.get(
      '/facturas/?negocio=${widget.negocio.id}&pagada=false&condicion_venta=02',
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      List<Factura> pend = data.map((item) => Factura.fromJson(item)).toList();
      final ahora = DateTime.now();
      return pend.where((f) {
        try {
          DateTime emision = DateTime.parse(f.fechaEmision);
          DateTime vencimiento = emision.add(Duration(days: f.plazoCredito));
          return vencimiento.isBefore(ahora);
        } catch (_) {
          return false;
        }
      }).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> obtenerMetricasDashboard() async {
    final data = await ApiService.getDashboardComercial(widget.negocio.id);
    return data ?? {};
  }

  Future<Map<String, dynamic>> obtenerDeclaracionIva() async {
    String inicioStr = "${_fechaInicio.year}-${_fechaInicio.month.toString().padLeft(2, '0')}-${_fechaInicio.day.toString().padLeft(2, '0')}";
    String finStr = "${_fechaFin.year}-${_fechaFin.month.toString().padLeft(2, '0')}-${_fechaFin.day.toString().padLeft(2, '0')}";

    final response = await ApiService.get(
      '/facturas/declaracion-iva/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr',
    );
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return {};
  }

  Future<Map<String, dynamic>> obtenerDeclaracionRenta() async {
    final response = await ApiService.get(
      '/facturas/declaracion-renta/?negocio=${widget.negocio.id}&periodo_fiscal=$_anioRenta',
    );
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return {};
  }

  Future<List<Cliente>> obtenerClientes() async {
    final response = await ApiService.get('/clientes/?negocio=${widget.negocio.id}');
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((item) => Cliente.fromJson(item)).toList();
    }
    return [];
  }

  Future<List<dynamic>> obtenerSaldosGlobales() async {
    final response = await ApiService.get('/clientes/saldos/?negocio=${widget.negocio.id}');
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return [];
  }

  String _tituloSeccionActiva() {
    switch (_seccionActiva) {
      case 1:
        return "Dashboard";
      case 0:
        return "Facturas";
      case 2:
        return "Clientes";
      case 6:
        return "Cuentas por Cobrar";
      case 3:
        return "Inventario";
      case 4:
        return "Cotizaciones";
      case 7:
        return "Impuestos";
      case 8:
        return "Compras";
      case 13:
        return "Cuentas por Pagar";
      case 14:
        return "Empleados";
      case 10:
        return "Reportes";
      case 11:
        return "Tarjeta de Lealtad";
      case 12:
        return "Add-ons";
      case 5:
        return "Ajustes";
      default:
        return widget.negocio.nombreComercial;
    }
  }

  Widget _pillAppBar({required IconData icono, required String texto, required String tooltip, Color? colorTexto}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.textMuted.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 16, color: colorTexto ?? Colors.white),
              const SizedBox(width: 6),
              Text(texto, style: TextStyle(color: colorTexto ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPillTipoCambio() {
    final venta = (_tipoCambio!['venta'] as num?)?.toDouble() ?? 0;
    final compra = (_tipoCambio!['compra'] as num?)?.toDouble() ?? 0;
    return _pillAppBar(
      icono: Icons.attach_money,
      texto: "₡${formatearNumero(venta)}",
      tooltip: "Tipo de cambio USD (BCCR) — Compra: ₡${formatearNumero(compra)} · Venta: ₡${formatearNumero(venta)}",
    );
  }

  Widget _buildPillCuotaFacturas() {
    final disponibles = _negocioConCuota.facturasDisponibles ?? 0;
    final limite = _negocioConCuota.limiteFacturasMensual ?? 0;
    Color? color;
    if (limite > 0) {
      final proporcion = disponibles / limite;
      if (proporcion <= 0.1) {
        color = Colors.redAccent.shade100;
      } else if (proporcion <= 0.3) {
        color = Colors.amber.shade100;
      }
    }
    return _pillAppBar(
      icono: Icons.receipt_long,
      texto: "$disponibles/$limite",
      tooltip: "Plan ${_negocioConCuota.planNombre}: $disponibles de $limite facturas electrónicas disponibles este mes",
      colorTexto: color,
    );
  }

  Widget _construirCuerpoSeccion() {
    switch (_seccionActiva) {
      case 0:
        return FutureBuilder<List<Factura>>(
          future: _facturasFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No hay facturas en este periodo."));
            return _renderizarFacturas(snapshot.data!);
          },
        );
      case 1:
        return FutureBuilder<List<Factura>>(
          future: _facturasFuture,
          builder: (context, snapshot) {
            final facturas = snapshot.data ?? [];
            return _renderizarDashboard(facturas, snapshot.connectionState == ConnectionState.waiting);
          },
        );
      case 2:
        return _buildListaClientes();
      case 3:
        return InventarioScreen(negocio: widget.negocio);
      case 4:
        return CotizacionScreen(negocio: widget.negocio, onFacturaCreada: () => _recargarDatos());
      case 5:
        return ConfiguracionScreen(negocio: _negocioConCuota, onGuardado: _cargarNegocioActualizado);
      case 6:
        return CuentasPorCobrarScreen(negocio: widget.negocio);
      case 7:
        return const ImpuestosScreen();
      case 8:
        return ComprasScreen(negocio: widget.negocio);
      case 9:
        return GastosScreen(negocio: widget.negocio);
      case 10:
        return ReportesScreen(negocio: widget.negocio);
      case 11:
        return TarjetaLealtadScreen(negocio: widget.negocio);
      case 12:
        return AddonsScreen(negocio: widget.negocio);
      case 13:
        return CuentasPorPagarScreen(negocio: widget.negocio);
      case 14:
        return EmpleadosScreen(negocio: widget.negocio);
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final bool esMovil = MediaQuery.of(context).size.width < _anchoBreakpointMovil;

    return BloqueoSalidaRaiz(
      child: Scaffold(
      key: _scaffoldKey,
      drawer: esMovil ? _buildDrawerMovil() : null,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(color: AppColors.surface),
        ),
        // En escritorio la navegacion ya esta siempre visible como pildoras
        // (ver bottom: mas abajo), asi que no hace falta un boton de menu
        // ahi -- solo en movil, para abrir el Drawer con la lista vertical.
        leadingWidth: Navigator.canPop(context) ? 96 : null,
        leading: Navigator.canPop(context)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: "Volver",
                    onPressed: () => Navigator.pop(context),
                  ),
                  if (esMovil)
                    IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                ],
              )
            : (esMovil
                ? IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  )
                : null),
        title: Text(_tituloSeccionActiva()),
        bottom: esMovil ? null : PreferredSize(preferredSize: const Size.fromHeight(56), child: _buildPillTabsBar()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualizar",
            onPressed: () => _recargarDatos(clientes: true),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: themeController,
            builder: (context, esOscuro, _) => IconButton(
              icon: Icon(esOscuro ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              tooltip: esOscuro ? "Cambiar a modo claro" : "Cambiar a modo oscuro",
              onPressed: themeController.alternar,
            ),
          ),
          if (_tipoCambio != null && _tipoCambio!['disponible'] == true) _buildPillTipoCambio(),
          if (_negocioConCuota.planNombre != null && _negocioConCuota.planNombre!.isNotEmpty) _buildPillCuotaFacturas(),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: "Cambiar Periodo",
            onPressed: () async {
              final DateTimeRange? rango = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2023),
                lastDate: DateTime(2030),
                initialDateRange: DateTimeRange(start: _fechaInicio, end: _fechaFin),
              );
              if (rango != null) {
                setState(() {
                  _fechaInicio = rango.start;
                  _fechaFin = rango.end;
                });
                _recargarDatos();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.support_agent),
            tooltip: "Soporte",
            onPressed: () => mostrarSoporteChat(context, contexto: 'usuario', negocioId: widget.negocio.id),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar sesión",
            onPressed: () async {
              await ApiService.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      // En escritorio ya no hay menu lateral (ver bottom: del AppBar, la
      // barra de pildoras horizontal) -- el contenido usa todo el ancho
      // disponible, igual que en el diseño de referencia.
      body: KeyedSubtree(
        key: ValueKey(_seccionActiva),
        child: _construirCuerpoSeccion(),
      ),
      floatingActionButton: () {
        if ([3, 4, 5, 6, 7, 8, 9, 10, 11, 12].contains(_seccionActiva)) return null;
        if (_seccionActiva == 2) {
          return FloatingActionButton(
            heroTag: "fab_negocio_cliente",
            backgroundColor: AppColors.primary,
            tooltip: "Agregar Nuevo Cliente",
            child: const Icon(Icons.person_add, color: Colors.black),
            onPressed: () async {
              bool? creado = await Navigator.push(context, MaterialPageRoute(builder: (context) => CrearClienteScreen(negocio: widget.negocio)));
              if (creado == true) _recargarDatos(facturas: false, clientes: true);
            },
          );
        }
        return FloatingActionButton(
          heroTag: "fab_negocio_factura",
          backgroundColor: tema.colorScheme.primary,
          tooltip: "Emitir Factura",
          child: const Icon(Icons.add, color: Colors.black),
          onPressed: () async {
            bool? guardado = await Navigator.push(context, MaterialPageRoute(builder: (context) => FormularioFactura(negocio: widget.negocio)));
            if (guardado == true) _recargarDatos();
          },
        );
      }(),
    ),
    );
  }

  /// Lista de secciones del menú, reutilizada tanto por la columna lateral
  /// fija (escritorio/web ancho) como por el Drawer deslizable (móvil).
  List<Widget> _itemsMenu({bool cerrarAlSeleccionar = false}) {
    return _menuItemsVisibles
        .map((it) => _buildItemMenu(
              id: it.id,
              icono: it.icono,
              titulo: it.titulo,
              cerrarAlSeleccionar: cerrarAlSeleccionar,
            ))
        .toList();
  }

  Widget _buildDrawerMovil() {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: ListView(
          children: [
            _buildSidebarHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: AppColors.border, height: 1),
            ),
            const SizedBox(height: 14),
            ..._itemsMenu(cerrarAlSeleccionar: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarHeader() {
    final tieneLogo = widget.negocio.logoUrl != null && widget.negocio.logoUrl!.isNotEmpty;
    const double diametro = 40;
    final avatar = Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withOpacity(0.15),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: tieneLogo
          ? Image.network(
              widget.negocio.logoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.business_center_rounded, color: AppColors.textStrong, size: 19),
            )
          : Icon(Icons.business_center_rounded, color: AppColors.textStrong, size: 19),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.negocio.nombreComercial,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.bold, fontSize: 15, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemMenu({
    required int id,
    required IconData icono,
    required String titulo,
    bool cerrarAlSeleccionar = false,
  }) {
    final bool seleccionado = _seccionActiva == id;

    final chip = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: seleccionado ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icono, color: seleccionado ? Colors.black : AppColors.textMuted, size: 21),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          hoverColor: AppColors.primary.withOpacity(0.08),
          splashColor: AppColors.primary.withOpacity(0.15),
          onTap: () {
            _cambiarSeccion(id);
            if (cerrarAlSeleccionar) Navigator.pop(context);
          },
          child: Row(
            children: [
              chip,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: seleccionado ? AppColors.primary : AppColors.textMuted,
                    fontWeight: seleccionado ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cada seccion de la app como pastilla horizontal en la barra de
  /// navegacion superior (estilo del diseño de referencia: "Dashboard /
  /// Structure / Costs / Budget" como pildoras junto al logo, en vez de un
  /// menu lateral vertical). Se recorre con scroll horizontal porque esta
  /// app tiene bastantes mas secciones que el diseño original.
  Widget _pildoraNav({required int id, required IconData icono, required String titulo}) {
    final bool seleccionado = _seccionActiva == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: seleccionado ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _cambiarSeccion(id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: seleccionado ? null : Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 16, color: seleccionado ? Colors.black : AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: seleccionado ? Colors.black : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillTabsBar() {
    return Container(
      height: 56,
      color: AppColors.surface,
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: _menuItemsVisibles
              .map((it) => _pildoraNav(id: it.id, icono: it.icono, titulo: it.titulo))
              .toList(),
        ),
      ),
    );
  }

  Widget _renderizarFacturas(List<Factura> facturas) {
    final facturasOrdenadas = List<Factura>.from(facturas)
      ..sort((a, b) => b.fechaEmision.compareTo(a.fechaEmision));

    Map<String, List<Factura>> grouped = {};
    for (var f in facturasOrdenadas) {
      String dateKey = f.fechaEmision.split('T')[0];
      grouped.putIfAbsent(dateKey, () => []).add(f);
    }

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => ExportService.exportFacturasToPdf(
                    facturasOrdenadas,
                    widget.negocio.nombreComercial,
                    "Del ${_fechaInicio.day}/${_fechaInicio.month} al ${_fechaFin.day}/${_fechaFin.month}",
                  ),
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 18),
                  label: const Text("Exportar PDF", style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () => ExportService.exportFacturasToExcel(facturasOrdenadas),
                  icon: const Icon(Icons.table_chart, color: Colors.green, size: 18),
                  label: const Text("Exportar Excel", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: grouped.keys.length,
              itemBuilder: (context, index) {
                String date = grouped.keys.elementAt(index);
                List<Factura> facturasDia = grouped[date]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12, left: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _formatearFechaSimple(date),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 0.5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Divider(color: Colors.grey.withOpacity(0.2))),
                        ],
                      ),
                    ),
                    ...facturasDia.map((f) {
                      final statusColor = _getColorEstado(f.estadoHacienda);
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.withOpacity(0.1)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 25,
                                backgroundColor: f.condicionVenta == "02" ? Colors.orange.withOpacity(0.1) : AppColors.primary.withOpacity(0.1),
                                child: Icon(
                                  f.condicionVenta == "02" ? Icons.timer_outlined : Icons.receipt_long_outlined,
                                  color: f.condicionVenta == "02" ? Colors.orange : AppColors.primary,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.surface, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Flexible(child: Text(f.receptorNombre, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textStrong))),
                              if (f.anulada) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text("ANULADA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Flexible(child: Text("F-${f.consecutivo} • ${f.condicionVenta == "02" ? 'Crédito' : 'Contado'}", overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              _chipEstadoHacienda(f.estadoHacienda),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatearColones(f.totalFactura), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(f.fechaEmision.contains('T') ? f.fechaEmision.split('T')[1].substring(0, 5) : "", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          onTap: () async {
                            final bool? cambio = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => DetalleFacturaScreen(factura: f)),
                            );
                            if (cambio == true) _recargarDatos();
                          },
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorEstado(String estado) {
    switch (estado) {
      case '3': return Colors.green;
      case '4':
      case '5': return Colors.red;
      case '1':
      case '2': return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _getTextoEstado(String estado) {
    switch (estado) {
      case '3': return "Aceptada";
      case '4': return "Rechazada";
      case '2': return "Procesando";
      case '1': return "Sin enviar";
      case '5': return "Error técnico";
      default: return "Desconocido";
    }
  }

  Widget _chipEstadoHacienda(String estado) {
    final color = _getColorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _getTextoEstado(estado),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  String _formatearFechaSimple(String dateIso) {
    try {
      DateTime dt = DateTime.parse(dateIso);
      DateTime hoy = DateTime.now();
      if (dt.year == hoy.year && dt.month == hoy.month && dt.day == hoy.day) return "HOY";
      DateTime ayer = hoy.subtract(const Duration(days: 1));
      if (dt.year == ayer.year && dt.month == ayer.month && dt.day == ayer.day) return "AYER";
      final meses = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"];
      return "${dt.day} ${meses[dt.month - 1]}, ${dt.year}";
    } catch (e) { return dateIso; }
  }

  Widget _renderizarDashboard(List<Factura> facturas, bool cargando) {
    final tema = Theme.of(context);
    final bool anchoCorto = MediaQuery.of(context).size.width < _anchoBreakpointMovil;

    // 1. Agrupar facturas por cliente para ver quién ha comprado en este periodo
    Map<String, double> comprasPorCliente = {};
    for (var f in facturas) {
      comprasPorCliente.update(f.receptorNombre, (v) => v + f.totalFactura, ifAbsent: () => f.totalFactura);
    }
    var listaVentasCliente = comprasPorCliente.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    double totalBruto = facturas.fold(0.0, (sum, f) => sum + f.totalFactura);
    double totalIva = facturas.fold(0.0, (sum, f) => sum + f.totalIva);
    double totalNeto = totalBruto - totalIva;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBannerBienvenida(),
          const SizedBox(height: 25),
          
          // 📊 RESUMEN FINANCIERO DEL PERIODO
          anchoCorto
              ? Column(
                  children: [
                    _buildStatCard("Total Facturado", totalBruto, Icons.analytics, AppColors.primary),
                    const SizedBox(height: 15),
                    _buildStatCard("Ingreso Neto", totalNeto, Icons.account_balance_wallet, Colors.green),
                    const SizedBox(height: 15),
                    _buildStatCard("Impuestos (IVA)", totalIva, Icons.percent, Colors.orange),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _buildStatCard("Total Facturado", totalBruto, Icons.analytics, AppColors.primary)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildStatCard("Ingreso Neto", totalNeto, Icons.account_balance_wallet, Colors.green)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildStatCard("Impuestos (IVA)", totalIva, Icons.percent, Colors.orange)),
                  ],
                ),
          
          const SizedBox(height: 30),

          // 🧾 DECLARACIÓN DE IVA (BORRADOR DEL PERIODO)
          Text("Declaración de IVA (Borrador del Periodo)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
          const SizedBox(height: 15),
          FutureBuilder<Map<String, dynamic>>(
            future: _declaracionIvaFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
              final d = snapshot.data ?? {};
              if (d.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: const Text("No se pudo cargar la declaración de IVA de este periodo", style: TextStyle(color: Colors.grey)),
                );
              }
              return buildDeclaracionIva(d);
            },
          ),

          const SizedBox(height: 30),

          // 🧾 DECLARACIÓN DE RENTA (BORRADOR ANUAL)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Declaración de Renta (Borrador Anual)",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _anioRenta,
                  items: List.generate(5, (i) => DateTime.now().year - i)
                      .map((a) => DropdownMenuItem(value: a, child: Text("Periodo fiscal $a")))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _cambiarAnioRenta(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          FutureBuilder<Map<String, dynamic>>(
            future: _declaracionRentaFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
              final d = snapshot.data ?? {};
              if (d.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: const Text("No se pudo cargar la declaración de Renta de este periodo", style: TextStyle(color: Colors.grey)),
                );
              }
              return buildDeclaracionRenta(d);
            },
          ),

          const SizedBox(height: 30),

          // ⚠️ ALERTA FACTURAS VENCIDAS
          Text("Facturas Vencidas (Pendientes de Cobro)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
          const SizedBox(height: 15),
          FutureBuilder<List<Factura>>(
            future: _vencidasFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
              final vencidas = snapshot.data ?? [];
              if (vencidas.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                  child: const Text("No hay clientes con facturas vencidas", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                );
              }
              return Column(
                children: vencidas.map((f) {
                  String detalleVencimiento = "Factura F-${f.consecutivo} vencida";
                  try {
                    final emision = DateTime.parse(f.fechaEmision);
                    final vencimiento = emision.add(Duration(days: f.plazoCredito));
                    final diasVencida = DateTime.now().difference(vencimiento).inDays;
                    final vencStr = "${vencimiento.day.toString().padLeft(2, '0')}/${vencimiento.month.toString().padLeft(2, '0')}/${vencimiento.year}";
                    detalleVencimiento = "F-${f.consecutivo} · Venció el $vencStr · hace $diasVencida día${diasVencida == 1 ? '' : 's'}";
                  } catch (_) {}
                  return Card(
                    // Antes: Colors.red[50] fijo -- un rojo clarito que no
                    // cambia con el tema, combinado con texto sin color
                    // explicito (heredaba el color de letra CLARA del tema
                    // oscuro), quedaba ilegible en modo oscuro. Con opacidad
                    // sobre el fondo real de la tarjeta se ve rojizo en los
                    // dos temas, y el texto ahora tiene color explicito.
                    color: Colors.red.withOpacity(0.12),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                      title: Text(f.receptorNombre, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                      subtitle: Text(detalleVencimiento, style: TextStyle(color: AppColors.textMuted)),
                      trailing: Text(formatearColones(f.totalFactura), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      onTap: () async {
                        final bool? cambio = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => DetalleFacturaScreen(factura: f)),
                        );
                        if (cambio == true) _recargarDatos();
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 30),

          Builder(builder: (context) {
            // 👥 CLIENTES CON VENTAS (PERIODO)
            final bloqueVentasCliente = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Ventas por Cliente", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                const SizedBox(height: 15),
                Card(
                  child: Column(
                    children: listaVentasCliente.isEmpty
                        ? [const ListTile(title: Text("Sin ventas registradas"))]
                        : listaVentasCliente.take(5).map((e) => ListTile(
                            dense: true,
                            title: Text(e.key),
                            trailing: Text(formatearColones(e.value, decimales: 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                          )).toList(),
                  ),
                ),
              ],
            );

            // 📦 TOP PRODUCTOS
            final bloqueTopProductos = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Productos Más Vendidos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                const SizedBox(height: 15),
                FutureBuilder<Map<String, dynamic>>(
                  future: _metricasFuture,
                  builder: (context, snapshot) {
                    final metricas = snapshot.data ?? {};
                    final topProd = metricas['top_productos'] as List? ?? [];
                    return Card(
                      child: Column(
                        children: topProd.isEmpty
                            ? [const ListTile(title: Text("Sin datos"))]
                            : topProd.map((e) => ListTile(
                                dense: true,
                                title: Text(e['producto__nombre'] ?? 'Producto'),
                                trailing: Text("${e['total_vendido']} und", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                              )).toList(),
                      ),
                    );
                  },
                ),
              ],
            );

            // 📦 PRODUCTOS CON MÁS STOCK
            final bloqueMayorStock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Productos con Más Stock", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                const SizedBox(height: 15),
                FutureBuilder<Map<String, dynamic>>(
                  future: _metricasFuture,
                  builder: (context, snapshot) {
                    final metricas = snapshot.data ?? {};
                    final mayorStock = metricas['productos_mayor_stock'] as List? ?? [];
                    return Card(
                      child: Column(
                        children: mayorStock.isEmpty
                            ? [const ListTile(title: Text("Sin datos"))]
                            : mayorStock.map((e) => ListTile(
                                dense: true,
                                title: Text(e['nombre'] ?? 'Producto'),
                                trailing: Text("${e['stock']} und", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                              )).toList(),
                      ),
                    );
                  },
                ),
              ],
            );

            if (anchoCorto) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bloqueVentasCliente,
                  const SizedBox(height: 20),
                  bloqueTopProductos,
                  const SizedBox(height: 20),
                  bloqueMayorStock,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: bloqueVentasCliente),
                const SizedBox(width: 20),
                Expanded(child: bloqueTopProductos),
                const SizedBox(width: 20),
                Expanded(child: bloqueMayorStock),
              ],
            );
          }),

          const SizedBox(height: 30),
          
          // 🧱 ACCESO RÁPIDO
          Text("Accesos Rápidos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildQuickCard("Emitir Factura", Icons.post_add, AppColors.primary, () async {
                bool? g = await Navigator.push(context, MaterialPageRoute(builder: (c) => FormularioFactura(negocio: widget.negocio)));
                if (g == true) _recargarDatos();
              }),
              _buildQuickCard("Ver Pendientes", Icons.payments, Colors.green, () => _cambiarSeccion(6)),
              _buildQuickCard("Exportar Resumen", Icons.picture_as_pdf, Colors.redAccent, () async {
                final metricas = await _metricasFuture;
                final saldos = await _saldosCxCFuture;
                await ExportService.exportResumenDashboardPdf(
                  negocioNombre: widget.negocio.nombreComercial,
                  periodo: "Del ${_fechaInicio.day}/${_fechaInicio.month} al ${_fechaFin.day}/${_fechaFin.month}",
                  facturas: facturas,
                  topProductos: metricas['top_productos'] ?? [],
                  saldosCxC: saldos,
                );
              }),
              _buildQuickCard("Exportar Declaración IVA", Icons.request_quote_outlined, Colors.teal, () async {
                final declaracion = await _declaracionIvaFuture;
                if (declaracion.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("No se pudo cargar la declaración de IVA de este periodo")),
                    );
                  }
                  return;
                }
                await ExportService.exportDeclaracionIvaPdf(
                  negocioNombre: widget.negocio.nombreComercial,
                  negocioCedula: widget.negocio.cedula,
                  periodo: "Del ${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} al ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}",
                  declaracion: declaracion,
                );
              }),
              _buildQuickCard("Exportar Declaración Renta", Icons.summarize_outlined, Colors.deepPurple, () async {
                final declaracion = await _declaracionRentaFuture;
                if (declaracion.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("No se pudo cargar la declaración de Renta de este periodo")),
                    );
                  }
                  return;
                }
                await ExportService.exportDeclaracionRentaPdf(
                  negocioNombre: widget.negocio.nombreComercial,
                  negocioCedula: widget.negocio.cedula,
                  declaracion: declaracion,
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String titulo, double valor, IconData icono, Color color, {bool isCurrency = true, String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(titulo, style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              Icon(icono, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isCurrency ? formatearColones(valor) : formatearNumero(valor, decimales: 0),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textStrong),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]
        ],
      ),
    );
  }

  Widget _buildQuickCard(String titulo, IconData icono, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 160,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2))
          ),
          child: Column(
            children: [
              Icon(icono, color: color, size: 32),
              const SizedBox(height: 8),
              Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerBienvenida() {
    final tieneLogo = widget.negocio.logoUrl != null && widget.negocio.logoUrl!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: tieneLogo
                ? Image.network(
                    widget.negocio.logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(Icons.business_center, color: AppColors.primary, size: 26),
                  )
                : Icon(Icons.business_center, color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("¡Hola, $_nombreUsuario!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                const SizedBox(height: 4),
                Text("Gestionando: ${widget.negocio.nombreComercial}", style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _etiquetaTipoCedula(String tipo) {
    switch (tipo) {
      case '01': return 'Física';
      case '02': return 'Jurídica';
      case '03': return 'DIMEX';
      case '04': return 'NITE';
      default: return tipo;
    }
  }

  Future<void> _editarCliente(Cliente cliente) async {
    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => CrearClienteScreen(negocio: widget.negocio, clienteExistente: cliente)),
    );
    if (actualizado == true) _recargarDatos(facturas: false, clientes: true);
  }

  Future<void> _eliminarCliente(Cliente cliente) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar cliente?"),
        content: Text("Se eliminará a \"${cliente.nombre}\" permanentemente."),
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
      final response = await ApiService.delete('/clientes/${cliente.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _recargarDatos(facturas: false, clientes: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Cliente \"${cliente.nombre}\" eliminado."), backgroundColor: Colors.green),
          );
        }
      } else {
        final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? utf8.decode(response.bodyBytes);
        throw Exception(detalle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo borrar: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildListaClientes() {
    return Container(
      color: AppColors.surfaceSubtle,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _busquedaClientesCtrl,
              decoration: InputDecoration(
                hintText: "Buscar por nombre, cédula o correo...",
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _busquedaClientes.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _busquedaClientesCtrl.clear()),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Cliente>>(
              future: _clientesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final todos = snapshot.data ?? [];
                final clientes = _busquedaClientes.isEmpty
                    ? todos
                    : todos.where((c) =>
                        c.nombre.toLowerCase().contains(_busquedaClientes) ||
                        c.cedula.toLowerCase().contains(_busquedaClientes) ||
                        c.correo.toLowerCase().contains(_busquedaClientes)).toList();

                if (clientes.isEmpty) {
                  return Center(
                    child: Text(
                      todos.isEmpty ? "Todavía no hay clientes registrados." : "No se encontraron clientes con ese criterio.",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: clientes.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final cliente = clientes[i];
                    return Container(
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(cliente.nombre[0].toUpperCase(), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(cliente.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          [
                            if (cliente.cedula.isNotEmpty) "${_etiquetaTipoCedula(cliente.tipoCedula)}: ${cliente.cedula}",
                            if (cliente.correo.isNotEmpty) cliente.correo,
                            if (cliente.telefono.isNotEmpty) cliente.telefono,
                          ].join(" · "),
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.sell_outlined, color: Colors.teal, size: 20),
                              tooltip: "Historial de precios",
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => HistorialPreciosClienteScreen(cliente: cliente)),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                              tooltip: "Editar",
                              onPressed: () => _editarCliente(cliente),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              tooltip: "Borrar",
                              onPressed: () => _eliminarCliente(cliente),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
