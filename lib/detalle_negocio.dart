import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

import 'api_service.dart';
import 'cambiar_plan_screen.dart';
import 'cliente.dart';
import 'configuracion_screen.dart';
import 'cotizacion.dart';
import 'crear_cliente.dart';
import 'detalle_factura_screen.dart';
import 'factura.dart';
import 'compras_screen.dart';
import 'correos_compra_screen.dart';
import 'ingresos_screen.dart';
import 'gastos_screen.dart';
import 'declaracion_fiscal_widgets.dart';
import 'formulario_factura.dart';
import 'historial_precios_cliente_screen.dart';
import 'inventario_screen.dart';
import 'negocio.dart';
import 'cuentas_por_cobrar_screen.dart';
import 'recibos_pago_screen.dart';
import 'cuentas_por_pagar_screen.dart';
import 'empleados_screen.dart';
import 'notas_credito_debito_screen.dart';
import 'export_service.dart';
import 'impuestos_screen.dart';
import 'reportes_screen.dart';
import 'tarjeta_lealtad_screen.dart';
import 'addons_screen.dart';
import 'login.dart';
import 'formato.dart';
import 'chat_detalle_screen.dart';
import 'perfil_usuario_screen.dart';
import 'widgets/bloqueo_salida_raiz.dart';
import 'widgets/soporte_chat.dart';
import 'widgets/primeros_pasos_card.dart';
import 'widgets/asistente_ia_bar.dart';
import 'perfil_sesion.dart';
import 'widgets/asistente_flotante.dart';
import 'widgets/selector_periodo.dart';
import 'nota_credito.dart';
import 'widgets/pagos_en_linea.dart';

/// Envuelve a un hijo y le avisa a [builder] si el cursor está encima
/// (hover) -- solo tiene efecto real con mouse (escritorio/web), en touch no
/// pasa nada porque nunca dispara onEnter/onExit. Se usa en las pildoras de
/// categoría y en las opciones del menú desplegable para resaltarlas al
/// pasar el cursor, sin tener que convertir toda la pantalla en Stateful
/// solo para eso.
class _Resaltable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hover) builder;
  const _Resaltable({required this.builder});

  @override
  State<_Resaltable> createState() => _ResaltableState();
}

class _ResaltableState extends State<_Resaltable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.builder(context, _hover),
    );
  }
}

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

  // Controla el scroll horizontal de la barra de pildoras de escritorio: con
  // tantas secciones no entran todas en pantalla y antes no había ninguna
  // señal de que se podía desplazar para ver el resto -- flechas a los
  // lados que aparecen/desaparecen según cuánto falte por recorrer.
  final ScrollController _pillTabsScrollController = ScrollController();
  bool _pillTabsPuedeIzquierda = false;
  bool _pillTabsPuedeDerecha = false;

  void _actualizarFlechasPillTabs() {
    if (!_pillTabsScrollController.hasClients) return;
    final pos = _pillTabsScrollController.position;
    final puedeIzquierda = pos.pixels > 4;
    final puedeDerecha = pos.pixels < pos.maxScrollExtent - 4;
    if (puedeIzquierda != _pillTabsPuedeIzquierda || puedeDerecha != _pillTabsPuedeDerecha) {
      setState(() {
        _pillTabsPuedeIzquierda = puedeIzquierda;
        _pillTabsPuedeDerecha = puedeDerecha;
      });
    }
  }

  void _desplazarPillTabs(double delta) {
    if (!_pillTabsScrollController.hasClients) return;
    final destino = (_pillTabsScrollController.offset + delta).clamp(
      0.0,
      _pillTabsScrollController.position.maxScrollExtent,
    );
    _pillTabsScrollController.animateTo(destino, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // Menu desplegable de cada categoria (ver _pildoraCategoria) armado a
  // mano con un OverlayEntry propio en vez de PopupMenuButton -- con
  // PopupMenuButton, si ya había un menú abierto (ej. Finanzas) y se tocaba
  // OTRA pildora (ej. Compras), el primer click solo cerraba el barrier
  // modal de Finanzas y hacía falta un segundo click para recién abrir
  // Compras. Con un overlay propio, tocar otra categoría cierra la actual
  // y abre la nueva en el mismo click -- ver _alternarMenuCategoria.
  final Map<String, LayerLink> _linksCategoria = {
    for (final c in _categorias) c.categoria: LayerLink(),
  };
  OverlayEntry? _overlayCategoria;
  String? _categoriaMenuAbierta;

  void _cerrarMenuCategoria() {
    _overlayCategoria?.remove();
    _overlayCategoria = null;
    if (mounted && _categoriaMenuAbierta != null) setState(() => _categoriaMenuAbierta = null);
  }

  void _alternarMenuCategoria(String categoria, List<({int id, IconData icono, String titulo})> items) {
    if (_categoriaMenuAbierta == categoria) {
      _cerrarMenuCategoria();
      return;
    }
    // Si ya había otro menú de categoría abierto, se reemplaza directo acá
    // mismo (mismo gesto) en vez de depender de que su propio barrier lo
    // cierre primero.
    _overlayCategoria?.remove();
    final link = _linksCategoria[categoria]!;
    final entry = OverlayEntry(builder: (context) => _buildOverlayMenuCategoria(items, link));
    Overlay.of(context).insert(entry);
    _overlayCategoria = entry;
    setState(() => _categoriaMenuAbierta = categoria);
  }

  Widget _buildOverlayMenuCategoria(List<({int id, IconData icono, String titulo})> items, LayerLink link) {
    return Stack(
      children: [
        // Cierra al tocar afuera -- arranca DEBAJO del AppBar + la barra de
        // pildoras (nunca las cubre) para que tocar OTRA pildora la reciba
        // directo en vez de que este barrier se la trague primero.
        Positioned(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 56,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cerrarMenuCategoria,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: const Offset(0, 46),
          child: Material(
            color: AppColors.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minWidth: 210),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((it) {
                  final bool seleccionado = _seccionActiva == it.id;
                  return _Resaltable(
                    builder: (context, hover) => InkWell(
                      onTap: () {
                        _cambiarSeccion(it.id);
                        _cerrarMenuCategoria();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        color: hover ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(it.icono, size: 18, color: seleccionado || hover ? AppColors.primary : AppColors.textMuted),
                            const SizedBox(width: 10),
                            Text(
                              it.titulo,
                              style: TextStyle(
                                color: seleccionado || hover ? AppColors.primary : AppColors.textStrong,
                                fontWeight: seleccionado ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Por debajo de este ancho la navegacion pasa a un Drawer deslizable (con
  // la lista vertical de siempre) en vez de la barra de pildoras horizontal
  // de escritorio, que en un telefono no entra.
  static const double _anchoBreakpointMovil = 700;

  // Cada seccion de la app, compartida entre la barra de pildoras de
  // escritorio (_buildPillTabsBar) y la lista vertical del Drawer movil
  // (_itemsMenu) -- un solo lugar para agregar/quitar secciones.
  // Orden agrupado por función y frecuencia de uso: Dashboard primero,
  // Clientes e Inventario antes de Facturas (se necesitan para armar una
  // factura), el resto del ciclo de Ventas, Compras, Contabilidad/Reportes,
  // y por último Administración (lo que se toca con menos frecuencia).
  static const List<({int id, IconData icono, String titulo})> _menuItems = [
    (id: 1, icono: Icons.pie_chart_outline, titulo: "Dashboard"),
    (id: 2, icono: Icons.people_outline, titulo: "Clientes"),
    (id: 3, icono: Icons.inventory_2_outlined, titulo: "Inventario"),
    // -- Ventas --
    (id: 0, icono: Icons.receipt_long_outlined, titulo: "Facturas"),
    // -- Compras (a la par de Facturas, a pedido del contador) --
    (id: 8, icono: Icons.shopping_cart_outlined, titulo: "Compras"),
    (id: 18, icono: Icons.trending_up, titulo: "Ingresos"),
    (id: 4, icono: Icons.request_quote_outlined, titulo: "Cotizaciones"),
    (id: 6, icono: Icons.monetization_on_outlined, titulo: "Cuentas por Cobrar"),
    (id: 19, icono: Icons.payments_outlined, titulo: "Pagos en línea"),
    (id: 16, icono: Icons.receipt_outlined, titulo: "Recibos de Pago"),
    (id: 15, icono: Icons.assignment_return_outlined, titulo: "Notas de Crédito/Débito"),
    (id: 11, icono: Icons.loyalty_outlined, titulo: "Tarjeta de Lealtad"),
    (id: 17, icono: Icons.mark_email_read_outlined, titulo: "Correos de Compra"),
    (id: 13, icono: Icons.local_shipping_outlined, titulo: "Cuentas por Pagar"),
    (id: 9, icono: Icons.receipt_long_outlined, titulo: "Gastos"),
    // -- Contabilidad --
    (id: 10, icono: Icons.bar_chart_outlined, titulo: "Reportes"),
    (id: 7, icono: Icons.percent, titulo: "Impuestos"),
    // -- Administración --
    (id: 14, icono: Icons.badge_outlined, titulo: "Colaboradores"),
    (id: 12, icono: Icons.extension_outlined, titulo: "Add-ons"),
    (id: 5, icono: Icons.settings_outlined, titulo: "Ajustes"),
  ];

  // Agrupación de las secciones de arriba en categorías -- con 19 secciones
  // la barra de pildoras horizontal ya no entraba en pantalla (obligaba a
  // desplazarse para encontrar cualquier cosa). Ahora la barra muestra solo
  // estas 5 categorías como pildoras, y cada una despliega un menú con sus
  // secciones (ver _pildoraCategoria); el Drawer móvil usa el mismo mapeo
  // como ExpansionTile por categoría (ver _buildDrawerMovil).
  static const List<({String categoria, IconData icono})> _categorias = [
    (categoria: "Principal", icono: Icons.home_outlined),
    (categoria: "Ventas", icono: Icons.point_of_sale_outlined),
    (categoria: "Compras", icono: Icons.shopping_cart_outlined),
    (categoria: "Finanzas", icono: Icons.account_balance_outlined),
    (categoria: "Administración", icono: Icons.admin_panel_settings_outlined),
  ];

  static const Map<String, List<int>> _idsPorCategoria = {
    "Principal": [1, 2, 3],
    "Ventas": [0, 4, 15, 11, 16, 6, 19],
    "Compras": [8, 17, 13, 9],
    "Finanzas": [18, 10, 7],
    "Administración": [14, 12, 5],
  };

  // Secciones ocultas para un empleado con rol 'cajero' -- el backend ya
  // bloquea la escritura/lectura correspondiente de todas formas (ver
  // BloqueaCajeroMixin y los chequeos de es_cajero en views.py), esto es
  // solo para no mostrar botones que van a fallar. 'completo' ve todo esto.
  static const Set<int> _idsOcultosParaCajero = {6, 8, 13, 9, 7, 10, 11, 12, 5, 15, 16, 17, 18, 19};

  List<({int id, IconData icono, String titulo})> get _menuItemsVisibles {
    // "Colaboradores" (id 14) es exclusivo del dueño real -- ni 'cajero' ni
    // 'completo' pueden gestionar otros colaboradores (ver
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

  // Botón flotante del asistente en todas las pantallas de este negocio
  // (también cuando entra el contador a un cliente).
  late final ConfigAsistente _asistenteFlotante = ConfigAsistente(
    negocioId: widget.negocio.id,
    secciones: {for (final e in _seccionesAsistente.entries) e.key: e.value.$2},
    onNavegar: _irDesdeAsistente,
    abrirPantallaCompleta: _abrirAsistenteNegocio,
  );

  void _abrirAsistenteNegocio() {
    abrirAsistentePantalla(
      context,
      negocioId: widget.negocio.id,
      saludo: "Hola, ${widget.negocio.nombreComercial}",
      secciones: {for (final e in _seccionesAsistente.entries) e.key: e.value.$2},
      onNavegar: _irDesdeAsistente,
      sugerencias: const [
        (Icons.receipt_long_outlined, "Hacer una factura"),
        (Icons.trending_up, "¿Cuánto vendí este mes?"),
        (Icons.monetization_on_outlined, "¿Quién me debe?"),
        (Icons.insert_chart_outlined, "Mandame el reporte del mes"),
        (Icons.percent, "¿Cuánto IVA voy a pagar?"),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    AsistenteFlotante.registrar(_asistenteFlotante);
    DateTime ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month + 1, 0);
    _anioRenta = ahora.year;
    _cargarNombreUsuario();
    _cargarTipoCambio();
    _cargarNegocioActualizado();
    _cargarChat();
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

    _pillTabsScrollController.addListener(_actualizarFlechasPillTabs);
    // Tras el primer frame la barra ya tiene su ancho real: si el contenido
    // no entra completo, muestra la flecha derecha desde el arranque (antes
    // había que adivinar que se podía desplazar).
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarFlechasPillTabs());
  }

  @override
  void dispose() {
    AsistenteFlotante.quitar(_asistenteFlotante);
    _busquedaClientesCtrl.dispose();
    _pillTabsScrollController.dispose();
    _overlayCategoria?.remove();
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

  // Chat con el contador -- null hasta que alguno de los dos lados inicia la
  // conversación (ver ConversacionChatViewSet.create: el negocio puede
  // iniciarla con su propio contador, o el contador con cualquier negocio de
  // su cartera), 0 o más no-leídos una vez que existe.
  int? _conversacionChatId;
  int _noLeidosChat = 0;
  String? _socioLogo;

  Future<void> _cargarChat() async {
    try {
      final r = await ApiService.get('/chat/conversaciones/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) {
          setState(() {
            _conversacionChatId = data.isNotEmpty ? data.first['id'] : null;
            _noLeidosChat = data.isNotEmpty ? (data.first['no_leidos'] ?? 0) : 0;
            _socioLogo = data.isNotEmpty ? data.first['socio_logo'] : null;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _abrirChat() async {
    if (_conversacionChatId == null) {
      // Todavia no existe la conversacion -- el negocio tambien puede
      // iniciarla con su propio contador (POST sin body: el backend deriva
      // el negocio del usuario logueado), no hace falta esperar a que el
      // contador escriba primero.
      try {
        final r = await ApiService.post('/chat/conversaciones/', {});
        if (r.statusCode == 201) {
          final data = json.decode(utf8.decode(r.bodyBytes));
          if (mounted) {
            setState(() {
              _conversacionChatId = data['id'];
              _socioLogo = data['socio_logo'];
            });
          }
        } else {
          throw Exception('status ${r.statusCode}');
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo iniciar el chat con tu contador. Probá de nuevo.")),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetalleScreen(
          conversacionId: _conversacionChatId!,
          nombreOtraParte: widget.negocio.nombreSocio ?? 'Mi contador',
          otraParteLogo: _socioLogo,
        ),
      ),
    );
    _cargarChat();
  }

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

  /// Secciones que la barra de IA puede proponer abrir (ver AsistenteIABar).
  static const Map<String, (int, String)> _seccionesAsistente = {
    'facturas': (0, 'Facturas: ver, reenviar o anular facturas emitidas'),
    'nueva_factura': (-1, 'Nueva factura: abrir el formulario para emitir una factura o tiquete'),
    'clientes': (2, 'Clientes: agregar o editar clientes'),
    'inventario': (3, 'Inventario: productos, existencias, categorías y carga masiva con IA'),
    'cotizaciones': (4, 'Cotizaciones: crear cotizaciones, también desde una foto de un pedido'),
    'cuentas_cobrar': (6, 'Cuentas por cobrar: quién te debe y registrar abonos'),
    'pagos_en_linea': (19, 'Pagos en línea: pagos que reportaron los clientes desde el enlace de su factura y datos de SINPE/IBAN'),
    'recibos_pago': (16, 'Recibos de pago: recibos electrónicos de pago (REP)'),
    'notas_credito': (15, 'Notas de crédito/débito: anular o corregir facturas'),
    'compras': (8, 'Compras: registrar facturas de proveedores (XML, PDF o foto) y aceptarlas'),
    'correos_compra': (17, 'Correos de compra: facturas de proveedores que llegaron por correo'),
    'cuentas_pagar': (13, 'Cuentas por pagar: lo que le debés a proveedores'),
    'gastos': (9, 'Gastos: registrar gastos del negocio'),
    'ingresos': (18, 'Ingresos: otros ingresos y carga masiva de ventas'),
    'reportes': (10, 'Reportes: reportes de facturación, compras e ingresos en PDF/Excel'),
    'impuestos': (7, 'Impuestos: declaración de IVA y de Renta'),
    'tarjeta_lealtad': (11, 'Tarjeta de lealtad: programa de puntos para clientes'),
    'colaboradores': (14, 'Colaboradores: usuarios del negocio (cajeros, etc.)'),
    'ajustes': (5, 'Ajustes: datos del negocio, llave criptográfica de Hacienda, logo, numeración'),
  };

  void _irDesdeAsistente(String clave) {
    final destino = _seccionesAsistente[clave];
    if (destino == null) return;
    if (destino.$1 == -1) {
      Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => FormularioFactura(negocio: widget.negocio)))
          .then((guardado) {
        if (guardado == true) _recargarDatos();
      });
      return;
    }
    _cambiarSeccion(destino.$1);
  }

  void _cambiarSeccion(int id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _seccionActiva = id);
    });
  }

  // Notas de crédito del periodo: se restan de las ventas del dashboard y
  // de los reportes exportados desde la lista de facturas.
  List<NotaCredito> _notasPeriodo = [];

  Future<void> _cargarNotasPeriodo(String inicioStr, String finStr) async {
    try {
      final r = await ApiService.get('/notas-credito/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        _notasPeriodo = data
            .map((j) => NotaCredito.fromJson(j))
            .where((n) => n.estadoHacienda != '4' && n.estadoHacienda != '5')
            .toList();
      }
    } catch (_) {
      _notasPeriodo = [];
    }
  }

  Future<List<Factura>> obtenerFacturas() async {
    String inicioStr = "${_fechaInicio.year}-${_fechaInicio.month.toString().padLeft(2, '0')}-${_fechaInicio.day.toString().padLeft(2, '0')}";
    String finStr = "${_fechaFin.year}-${_fechaFin.month.toString().padLeft(2, '0')}-${_fechaFin.day.toString().padLeft(2, '0')}";

    final notas = _cargarNotasPeriodo(inicioStr, finStr);
    final response = await ApiService.get(
      '/facturas/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr',
    );
    await notas;

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
      case 16:
        return "Recibos de Pago";
      case 19:
        return "Pagos en línea";
      case 3:
        return "Inventario";
      case 4:
        return "Cotizaciones";
      case 7:
        return "Impuestos";
      case 8:
        return "Compras";
      case 17:
        return "Correos de Compra";
      case 18:
        return "Ingresos";
      case 13:
        return "Cuentas por Pagar";
      case 14:
        return "Colaboradores";
      case 15:
        return "Notas de Crédito/Débito";
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

  /// Un segmento dentro de la cápsula de "datos del período" del AppBar
  /// (ver _grupoDatosAppBar) -- sin fondo propio porque ya vive adentro de
  /// esa cápsula, con resaltado al pasar el cursor igual que el resto de
  /// los controles interactivos del AppBar.
  Widget _segmentoDatosAppBar({
    required IconData icono,
    required String texto,
    required String tooltip,
    Color? colorTexto,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: _Resaltable(
        builder: (context, hover) {
          final bool destacar = hover && onTap != null;
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: destacar ? AppColors.primary.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, size: 16, color: colorTexto ?? (destacar ? AppColors.primary : AppColors.textStrong)),
                  const SizedBox(width: 6),
                  Text(
                    texto,
                    style: TextStyle(
                      color: colorTexto ?? (destacar ? AppColors.primary : AppColors.textStrong),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Agrupa Período, Tipo de cambio y Cuota de facturas en una sola cápsula
  /// con separadores -- antes eran 3 elementos sueltos flotando en el
  /// AppBar (un botón y dos pastillas con su propio fondo cada una), lo que
  /// se sentía desordenado; ahora se leen como un solo bloque de "datos del
  /// período actual".
  Widget _grupoDatosAppBar() {
    final segmentos = <Widget>[
      _segmentoDatosAppBar(
        icono: Icons.calendar_month_outlined,
        texto: "Período",
        tooltip: "Cambiar período (actual: ${_fechaInicio.day}/${_fechaInicio.month} al ${_fechaFin.day}/${_fechaFin.month})",
        onTap: () async {
          final DateTimeRange? rango = await elegirPeriodo(context, inicial: DateTimeRange(start: _fechaInicio, end: _fechaFin));
          if (rango != null) {
            setState(() {
              _fechaInicio = rango.start;
              _fechaFin = rango.end;
            });
            _recargarDatos();
          }
        },
      ),
    ];

    if (_tipoCambio != null && _tipoCambio!['disponible'] == true) {
      final venta = (_tipoCambio!['venta'] as num?)?.toDouble() ?? 0;
      final compra = (_tipoCambio!['compra'] as num?)?.toDouble() ?? 0;
      segmentos.add(_segmentoDatosAppBar(
        icono: Icons.attach_money,
        texto: "₡${formatearNumero(venta)}",
        tooltip: "Tipo de cambio USD (BCCR) — Compra: ₡${formatearNumero(compra)} · Venta: ₡${formatearNumero(venta)}",
      ));
    }

    if (_negocioConCuota.planNombre != null && _negocioConCuota.planNombre!.isNotEmpty) {
      final uso = _negocioConCuota.usoPlan;
      final ilimitado = uso != null && uso['documentos_limite'] == null;
      final disponibles = _negocioConCuota.facturasDisponibles ?? 0;
      final limite = _negocioConCuota.limiteFacturasMensual ?? 0;
      final extraPermitido = uso?['precio_documento_extra'] != null;
      final unidad = uso?['periodicidad'] == 'anual' ? 'año' : 'mes';
      Color? color;
      if (limite > 0 && !ilimitado && !extraPermitido) {
        final proporcion = disponibles / limite;
        if (proporcion <= 0.1) {
          color = Colors.redAccent;
        } else if (proporcion <= 0.3) {
          color = Colors.amber.shade800;
        }
      }
      segmentos.add(_segmentoDatosAppBar(
        icono: Icons.receipt_long_outlined,
        // Solo el numero disponible -- "$disponibles/$limite" confundia
        // cuando disponibles supera el limite del plan (ej. despues de
        // comprar mas facturas antes de que se acabaran, algo valido y
        // esperado, no un error).
        texto: ilimitado ? (_negocioConCuota.planNombre ?? '') : "$disponibles disp.",
        tooltip: ilimitado
            ? "Plan ${_negocioConCuota.planNombre}: documentos ilimitados "
                "(${uso['documentos_usados']} este mes) -- tocá para ver tu plan"
            : "Plan ${_negocioConCuota.planNombre} ($limite documentos/$unidad): $disponibles disponibles"
                "${extraPermitido ? ' (después se cobran como extra)' : ''} -- tocá para ver o cambiar tu plan",
        colorTexto: color,
        onTap: () async {
          final actualizo = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => CambiarPlanScreen(negocio: _negocioConCuota)),
          );
          if (actualizo == true) _recargarDatos();
        },
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < segmentos.length; i++) ...[
              if (i > 0) Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 2), color: AppColors.border),
              segmentos[i],
            ],
          ],
        ),
      ),
    );
  }

  /// Menú de comunicación (Soporte + Chat con mi contador) -- antes eran
  /// dos IconButton sueltos; agruparlos bajo un solo ícono con desplegable
  /// sigue el mismo patrón que el menú de cuenta, y el aviso de no-leídos
  /// se muestra como Badge en el propio ícono disparador.
  Widget _menuComunicacionAppBar() {
    return PopupMenuButton<String>(
      tooltip: "Comunicación",
      offset: const Offset(0, 46),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.border)),
      onSelected: (opcion) {
        if (opcion == 'soporte') {
          mostrarSoporteChat(context, contexto: 'usuario', negocioId: widget.negocio.id);
        } else if (opcion == 'chat') {
          _abrirChat();
        }
      },
      itemBuilder: (context) => [
        _itemMenuCuenta(value: 'soporte', icono: Icons.support_agent, titulo: "Soporte"),
        _itemMenuCuenta(
          value: 'chat',
          icono: Icons.chat_bubble_outline,
          titulo: _noLeidosChat > 0
              ? "Chat con mi contador (${_noLeidosChat > 99 ? '99+' : _noLeidosChat})"
              : "Chat con mi contador",
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Badge(
          label: Text(_noLeidosChat > 99 ? '99+' : '$_noLeidosChat', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red,
          isLabelVisible: _noLeidosChat > 0,
          offset: const Offset(2, -2),
          child: Icon(Icons.forum_outlined, color: AppColors.textMuted),
        ),
      ),
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
      case 16:
        return RecibosPagoScreen(negocio: widget.negocio);
      case 19:
        return PagosEnLineaVista(negocioId: widget.negocio.id);
      case 7:
        return const ImpuestosScreen();
      case 8:
        return ComprasScreen(negocio: widget.negocio);
      case 17:
        return CorreosCompraScreen(negocio: widget.negocio);
      case 18:
        return IngresosScreen(negocio: widget.negocio);
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
      case 15:
        return NotasCreditoDebitoScreen(negocio: widget.negocio);
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
        // Antes el AppBar quedaba pegado al contenido sin ninguna
        // separación visual (misma superficie plana) -- una sombra sutil
        // más un color de superficie explícito (surfaceTintColor:
        // transparent evita que Material 3 le encima un tinte automático al
        // dar elevación) le da la jerarquía visual de un panel "flotando"
        // sobre el contenido, más parecido a un dashboard profesional.
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.12),
        surfaceTintColor: Colors.transparent,
        // En escritorio la navegacion ya esta siempre visible como pildoras
        // (ver bottom: mas abajo), asi que no hace falta un boton de menu
        // ahi -- solo en movil, para abrir el Drawer con la lista vertical.
        leadingWidth: (ModalRoute.of(context)?.canPop ?? false) ? 96 : null,
        leading: (ModalRoute.of(context)?.canPop ?? false)
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
        // Antes el título repetía "PANEL DEL NEGOCIO" en genérico en las 19
        // secciones -- ahora el logo+nombre del negocio (su identidad real)
        // es lo prominente, con la sección activa como subtítulo chico, más
        // parecido a como un dashboard profesional encabeza cada pantalla.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatarNegocio(diametro: 34, iconoSize: 16),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.negocio.nombreComercial,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Con qué perfil se entró: el dueño, un colaborador, o
                      // el contador / despacho trabajando en este negocio.
                      ChipPerfil(color: AppColors.primary),
                    ],
                  ),
                  // El saludo vive acá (antes era una tarjeta aparte en Inicio
                  // que repetía logo y nombre y ocupaba espacio).
                  Text(
                    _nombreUsuario == "Usuario"
                        ? _tituloSeccionActiva()
                        : "¡Hola, ${_nombreUsuario.split(' ').first}!  ·  ${_tituloSeccionActiva()}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: esMovil ? null : PreferredSize(preferredSize: const Size.fromHeight(56), child: _buildPillTabsBar()),
        actions: [
          // Antes esto eran hasta 7 elementos sueltos (refresh, tema, 2
          // pastillas condicionales, periodo, soporte, chat) mas la cuenta
          // -- en un telefono angosto se salia del ancho del AppBar (ver
          // scroll horizontal). Ahora se agrupan en 3 bloques (datos del
          // periodo, comunicacion, cuenta) mas refresh/tema, bastante mas
          // compacto y ordenado; el scroll horizontal se deja igual como
          // red de seguridad para pantallas muy angostas.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualizar",
            onPressed: () => _recargarDatos(clientes: true),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: themeController,
                  builder: (context, esOscuro, _) => IconButton(
                    icon: Icon(esOscuro ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                    tooltip: esOscuro ? "Cambiar a modo claro" : "Cambiar a modo oscuro",
                    onPressed: themeController.alternar,
                  ),
                ),
                _grupoDatosAppBar(),
                _menuComunicacionAppBar(),
                _menuCuentaAppBar(),
              ],
            ),
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
        // 14 (Colaboradores), 15 (Notas de Credito/Debito) y 18 (Ingresos)
        // tienen su propio boton de "crear" adentro de la pantalla -- sin
        // ocultar el de "Emitir Factura" de aca, en Colaboradores el unico
        // "+" visible llevaba a hacer una factura en vez de agregar un
        // colaborador (y en los otros dos quedaban los dos FAB
        // superpuestos en la misma esquina).
        if ([3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 18].contains(_seccionActiva)) return null;
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
            const SizedBox(height: 6),
            for (final c in _categorias) ..._buildGrupoCategoriaDrawer(c.categoria, c.icono),
          ],
        ),
      ),
    );
  }

  /// Una categoría como ExpansionTile en el Drawer móvil, con sus secciones
  /// visibles adentro -- ya expandida si la sección activa pertenece a ella.
  /// Devuelve una lista vacía si el rol del usuario no ve ninguna sección de
  /// esta categoría (ej. "Administración" para un cajero).
  List<Widget> _buildGrupoCategoriaDrawer(String categoria, IconData icono) {
    final ids = _idsPorCategoria[categoria]!;
    final items = _menuItemsVisibles.where((m) => ids.contains(m.id)).toList();
    if (items.isEmpty) return const [];
    final bool categoriaActiva = ids.contains(_seccionActiva);
    return [
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: categoriaActiva,
          leading: Icon(icono, size: 20, color: AppColors.textMuted),
          title: Text(
            categoria,
            style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 4),
          children: items
              .map((it) => _buildItemMenu(id: it.id, icono: it.icono, titulo: it.titulo, cerrarAlSeleccionar: true))
              .toList(),
        ),
      ),
    ];
  }

  /// Logo circular del negocio (o un icono genérico si no tiene uno
  /// cargado) -- se reutiliza en el header del Drawer móvil, en el título
  /// del AppBar de escritorio y como disparador del menú de cuenta, para que
  /// la identidad del negocio se vea consistente en toda la pantalla.
  Widget _avatarNegocio({double diametro = 40, double iconoSize = 19}) {
    final tieneLogo = widget.negocio.logoUrl != null && widget.negocio.logoUrl!.isNotEmpty;
    return Container(
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
                  Icon(Icons.business_center_rounded, color: AppColors.textStrong, size: iconoSize),
            )
          : Icon(Icons.business_center_rounded, color: AppColors.textStrong, size: iconoSize),
    );
  }

  Widget _buildSidebarHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
      child: Row(
        children: [
          _avatarNegocio(),
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

  /// Menú de cuenta (avatar del negocio como disparador) con "Mi Perfil" y
  /// "Cerrar sesión" -- antes eran dos IconButton sueltos en el AppBar junto
  /// a otros 7 controles, lo que se sentía saturado; agruparlos bajo un solo
  /// avatar con desplegable es el patrón estándar de apps profesionales
  /// (Slack, Gmail, etc.) y deja el AppBar mucho más limpio.
  Widget _menuCuentaAppBar() {
    return PopupMenuButton<String>(
      tooltip: "Mi cuenta",
      offset: const Offset(0, 46),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.border)),
      onSelected: (opcion) async {
        if (opcion == 'perfil') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PerfilUsuarioScreen(
                nombre: _negocioConCuota.nombreComercial,
                subtitulo: "Negocio",
                logoEndpoint: '/negocios/${widget.negocio.id}/',
                logoUrlInicial: _negocioConCuota.logoUrl,
              ),
            ),
          );
          _cargarNegocioActualizado();
        } else if (opcion == 'logout') {
          await ApiService.logout();
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text(
              widget.negocio.nombreComercial,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        _itemMenuCuenta(value: 'perfil', icono: Icons.account_circle_rounded, titulo: "Mi Perfil"),
        _itemMenuCuenta(value: 'logout', icono: Icons.logout, titulo: "Cerrar sesión"),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: _avatarNegocio(diametro: 34, iconoSize: 16),
      ),
    );
  }

  PopupMenuItem<String> _itemMenuCuenta({required String value, required IconData icono, required String titulo}) {
    return PopupMenuItem<String>(
      value: value,
      padding: EdgeInsets.zero,
      child: _Resaltable(
        builder: (context, hover) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: hover ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
          child: Row(
            children: [
              Icon(icono, size: 18, color: hover ? AppColors.primary : AppColors.textMuted),
              const SizedBox(width: 10),
              Text(titulo, style: TextStyle(color: hover ? AppColors.primary : AppColors.textStrong)),
            ],
          ),
        ),
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

  /// Cada categoría como pastilla horizontal en la barra de navegación
  /// superior -- al tocarla despliega un menú con las secciones visibles de
  /// esa categoría (ver _idsPorCategoria). Antes cada una de las 19
  /// secciones era su propia pildora y no entraban todas en pantalla; ahora
  /// solo hay una pildora por categoría (5 en total).
  Widget _pildoraCategoria({required String categoria, required IconData icono}) {
    final ids = _idsPorCategoria[categoria]!;
    final itemsCategoria = _menuItemsVisibles.where((m) => ids.contains(m.id)).toList();
    if (itemsCategoria.isEmpty) return const SizedBox.shrink();
    final bool categoriaActiva = ids.contains(_seccionActiva);
    final bool menuAbierto = _categoriaMenuAbierta == categoria;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CompositedTransformTarget(
        link: _linksCategoria[categoria]!,
        child: Tooltip(
          message: categoria,
          child: _Resaltable(
            builder: (context, hover) => InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _alternarMenuCategoria(categoria, itemsCategoria),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: categoriaActiva
                      ? AppColors.primary
                      : ((hover || menuAbierto) ? AppColors.primary.withOpacity(0.14) : Colors.transparent),
                  borderRadius: BorderRadius.circular(20),
                  border: categoriaActiva ? null : Border.all(color: (hover || menuAbierto) ? AppColors.primary : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icono, size: 16, color: categoriaActiva ? Colors.black : ((hover || menuAbierto) ? AppColors.primary : AppColors.textMuted)),
                    const SizedBox(width: 6),
                    Text(
                      categoria,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: categoriaActiva ? Colors.black : ((hover || menuAbierto) ? AppColors.primary : AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      menuAbierto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 18,
                      color: categoriaActiva ? Colors.black : ((hover || menuAbierto) ? AppColors.primary : AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flechaPillTabs({required IconData icono, required VoidCallback onPressed}) {
    return Container(
      height: 56,
      color: AppColors.surface,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 28,
            child: Icon(icono, size: 18, color: AppColors.textMuted),
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
      child: Row(
        children: [
          if (_pillTabsPuedeIzquierda)
            _flechaPillTabs(icono: Icons.chevron_left, onPressed: () => _desplazarPillTabs(-220)),
          Expanded(
            child: SingleChildScrollView(
              controller: _pillTabsScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: _categorias
                    .map((c) => _pildoraCategoria(categoria: c.categoria, icono: c.icono))
                    .toList(),
              ),
            ),
          ),
          if (_pillTabsPuedeDerecha)
            _flechaPillTabs(icono: Icons.chevron_right, onPressed: () => _desplazarPillTabs(220)),
        ],
      ),
    );
  }

  Widget _renderizarFacturas(List<Factura> facturas) {
    final facturasOrdenadas = List<Factura>.from(facturas)
      ..sort((a, b) => b.fechaEmision.compareTo(a.fechaEmision));

    Map<String, List<Factura>> grouped = {};
    for (var f in facturasOrdenadas) {
      final cr = aFechaCostaRica(f.fechaEmision);
      String dateKey = "${cr.year.toString().padLeft(4, '0')}-${cr.month.toString().padLeft(2, '0')}-${cr.day.toString().padLeft(2, '0')}";
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
                    notasCredito: _notasPeriodo,
                  ),
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 18),
                  label: const Text("Exportar PDF", style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () => ExportService.exportFacturasToExcel(facturasOrdenadas, notasCredito: _notasPeriodo),
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
                              if (f.esInterno) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.20),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text("INTERNO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                                ),
                              ] else if (f.esTiquete) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text("TIQUETE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                ),
                              ],
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
                              Flexible(child: Text(
                                "${f.esInterno ? '' : (f.esTiquete ? 'T-' : 'F-')}${f.consecutivo} • ${f.condicionVenta == "02" ? 'Crédito' : 'Contado'}",
                                overflow: TextOverflow.ellipsis,
                              )),
                              const SizedBox(width: 8),
                              _chipEstadoHacienda(f.estadoHacienda),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(f.enSuMoneda(f.totalFactura), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              if (f.esEnDolares)
                                Text(
                                  "≈ ${formatearColones(f.totalFactura)}",
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              Text(horaCostaRica(f.fechaEmision), style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
      case '6': return Colors.amber;
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
      case '6': return "Interno";
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

  String _formatearFechaSimple(String dateKey) {
    // dateKey es "yyyy-MM-dd" ya calculado en hora de Costa Rica (ver
    // _renderizarFacturas) -- se parsea con hora fija de mediodía para que
    // nunca se corra de día por redondeos de zona horaria al comparar.
    try {
      final partes = dateKey.split('-');
      final dt = DateTime(int.parse(partes[0]), int.parse(partes[1]), int.parse(partes[2]), 12);
      final hoyCr = aFechaCostaRica(DateTime.now().toUtc().toIso8601String());
      final hoy = DateTime(hoyCr.year, hoyCr.month, hoyCr.day, 12);
      if (dt.year == hoy.year && dt.month == hoy.month && dt.day == hoy.day) return "HOY";
      final ayer = hoy.subtract(const Duration(days: 1));
      if (dt.year == ayer.year && dt.month == ayer.month && dt.day == ayer.day) return "AYER";
      final meses = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"];
      return "${dt.day} ${meses[dt.month - 1]}, ${dt.year}";
    } catch (e) { return dateKey; }
  }

  Widget _renderizarDashboard(List<Factura> todasLasFacturas, bool cargando) {
    // Ventas reales: sin rechazadas ni con error ante Hacienda, y menos las
    // notas de crédito del periodo.
    final facturas = todasLasFacturas.where((f) => f.estadoHacienda != '4' && f.estadoHacienda != '5').toList();
    final notasTotal = _notasPeriodo.fold(0.0, (s, n) => s + n.total);
    final notasIva = _notasPeriodo.fold(0.0, (s, n) => s + n.montoIva);
    final tema = Theme.of(context);
    final bool anchoCorto = MediaQuery.of(context).size.width < _anchoBreakpointMovil;

    // 1. Agrupar facturas por cliente para ver quién ha comprado en este periodo
    Map<String, double> comprasPorCliente = {};
    for (var f in facturas) {
      comprasPorCliente.update(f.receptorNombre, (v) => v + f.totalFactura, ifAbsent: () => f.totalFactura);
    }
    var listaVentasCliente = comprasPorCliente.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    double totalBruto = facturas.fold(0.0, (sum, f) => sum + f.totalFactura) - notasTotal;
    double totalIva = facturas.fold(0.0, (sum, f) => sum + f.totalIva) - notasIva;
    double totalNeto = totalBruto - totalIva;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lo primero del panel: preguntarle a la IA qué hacer.
          AsistenteIABar(
            negocioId: widget.negocio.id,
            saludo: "Hola, ${widget.negocio.nombreComercial}",
            secciones: {for (final e in _seccionesAsistente.entries) e.key: e.value.$2},
            onNavegar: _irDesdeAsistente,
            ejemplos: const [
              "¿Cuánto vendí este mes?",
              "Hacé una factura de 2 productos para Juan Pérez",
              "¿Quién me debe plata?",
              "Agregá un producto: martillo a ₡6.500",
              "Te mando la foto de una factura de compra para registrarla",
            ],
            sugerencias: const [
              (Icons.receipt_long_outlined, "Hacer una factura"),
              (Icons.trending_up, "¿Cuánto vendí este mes?"),
              (Icons.monetization_on_outlined, "¿Quién me debe?"),
              (Icons.insert_chart_outlined, "Mandame el reporte del mes"),
              (Icons.percent, "¿Cuánto IVA voy a pagar?"),
            ],
          ),
          const SizedBox(height: 12),
          // Clientes que pagaron desde el enlace de su factura (ver pagos_en_linea.dart).
          AvisoPagosPorConfirmar(negocioId: widget.negocio.id),
          // Guía para cuentas nuevas -- se oculta sola al completarla (y
          // nunca la ve el contador ni un colaborador, ver backend).
          PrimerosPasosCard(
            negocioId: widget.negocio.id,
            onIrASeccion: _cambiarSeccion,
            onNuevaFactura: () async {
              final guardado = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => FormularioFactura(negocio: widget.negocio)));
              if (guardado == true) _recargarDatos();
            },
          ),
          
          // 📊 RESUMEN FINANCIERO DEL PERIODO
          anchoCorto
              ? Column(
                  children: [
                    _buildStatCard("Ventas netas", totalBruto, Icons.analytics, AppColors.primary),
                    const SizedBox(height: 15),
                    _buildStatCard("Ingreso Neto", totalNeto, Icons.account_balance_wallet, Colors.green),
                    const SizedBox(height: 15),
                    _buildStatCard("Impuestos (IVA)", totalIva, Icons.percent, Colors.orange),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _buildStatCard("Ventas netas", totalBruto, Icons.analytics, AppColors.primary)),
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
                      trailing: Text(f.enSuMoneda(f.totalFactura), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
