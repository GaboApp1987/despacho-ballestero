import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'avatar_logo.dart';
import 'chats_contador_screen.dart';
import 'dashboard_despacho_widgets.dart';
import 'negocio.dart';
import 'onvo_cobro_automatico_screen.dart';
import 'perfil_usuario_screen.dart';
import 'plan.dart';
import 'reportes_contador_screen.dart';
import 'documentos_contador_screen.dart';
import 'asientos_contables_screen.dart';
import 'catalogo_cuentas_util.dart';
import 'bancos_screen.dart';
import 'resumen_fiscal_screen.dart';
import 'socio.dart';
import 'login.dart';
import 'widgets/bloqueo_salida_raiz.dart';
import 'widgets/soporte_chat.dart';
import 'widgets/asistente_ia_bar.dart';
import 'widgets/campo_cedula_hacienda.dart';
import 'perfil_sesion.dart';
import 'widgets/asistente_flotante.dart';

/// Paleta "Blanco & Cobalto" -- solo para cuando esta pantalla la ve un
/// CONTADOR viendo su propia cartera (widget.puedeCrear), a propósito
/// distinta del resto de la app (que usa AppColors, cian sobre azul
/// marino/blanco), para que se note de un vistazo que no es la pantalla de
/// un negocio. No toca AppColors -- el negocio y el resto de pantallas
/// siguen exactamente igual. (Segunda versión: la primera, grafito+esmeralda,
/// no le gustó al usuario -- este es el reemplazo, minimalista y claro.)
class _PaletaContador {
  static const Color fondo = Color(0xFFFFFFFF);
  static const Color superficie = Color(0xFFF8FAFC);
  static const Color acento = Color(0xFF1D4ED8);
  static const Color textoFuerte = Color(0xFF0F172A);
  static const Color textoTenue = Color(0xFF64748B);
  static const Color borde = Color(0xFFE2E8F0);
  // Barra lateral -- navy profundo, no negro puro (diseño "Menú lateral del
  // contador", 2026-10-08).
  static const Color sidebarFondo = Color(0xFF0E1726);
  static const Color sidebarTarjeta = Color(0xFF16223A);
  static const Color sidebarCampo = Color(0xFF121D31);
  static const Color sidebarAvatar = Color(0xFF24324D);
  static const Color sidebarTexto = Color(0xFFC3CBDA);
  static const Color sidebarEtiqueta = Color(0xFF8A98B3);
  static const Color sidebarTextoActivo = Colors.white;
  // Más claro que `acento`: sobre el navy el azul de la app no contrasta.
  static const Color sidebarAcento = Color(0xFF5B8CFF);
  static const Color sidebarAviso = Color(0xFFE11D48);
  static const Color sidebarSalir = Color(0xFFF4A3B4);
}

/// Versión clara de accionAppBar (dashboard_despacho_widgets.dart) -- esa
/// usa ícono blanco sobre círculo translúcido blanco, pensada para el
/// AppBar morado de siempre; sobre el AppBar blanco del contador quedaría
/// invisible, así que acá va una variante con ícono oscuro sin círculo.
Widget _accionAppBarClara({required IconData icono, required String tooltip, required VoidCallback onPressed}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icono, color: _PaletaContador.textoFuerte, size: 20),
          ),
        ),
      ),
    ),
  );
}

class NegociosScreen extends StatefulWidget {
  /// true si el usuario puede dar de alta negocios nuevos (contadores, o admin).
  final bool puedeCrear;
  /// true si el usuario puede asignar/cambiar el plan de suscripción de un negocio
  /// (contadores y despachos; no aplica a un negocio viendo su propia lista).
  final bool puedeGestionarPlanes;
  /// true solo para el administrador de la plataforma (superusuario): habilita
  /// gestionar la renta que cada negocio paga directamente a la plataforma.
  final bool esSuperusuario;
  const NegociosScreen({
    super.key,
    this.puedeCrear = false,
    bool? puedeGestionarPlanes,
    this.esSuperusuario = false,
  }) : puedeGestionarPlanes = puedeGestionarPlanes ?? puedeCrear;

  @override
  State<NegociosScreen> createState() => _NegociosScreenState();
}

class _NegociosScreenState extends State<NegociosScreen> {
  bool _isLoading = true;
  List<Negocio> _negocios = [];
  List<Plan> _planes = [];
  Socio? _miSocio;
  late Future<Map<String, dynamic>> _dashboardFuture;
  final TextEditingController _busquedaCtrl = TextEditingController();
  // Buscador de la barra lateral: escribe en _busquedaCtrl (mismo filtro que
  // el de la lista de clientes) y se mantiene igual a él.
  final TextEditingController _busquedaSidebarCtrl = TextEditingController();
  String _filtro = "";
  // Sidebar fija del contador (pantallas anchas): colapsa a solo íconos en
  // vez de esconderse del todo, así la navegación siempre queda a mano.
  bool _sidebarColapsada = false;
  // Pantallas angostas: la barra queda siempre visible como franja de
  // íconos y al abrirla se superpone al contenido en vez de empujarlo.
  bool _railAbierto = false;
  // Pestaña activa dentro de la sidebar (0 = Inicio/resumen, 1 = Clientes).
  // Solo aplica en pantallas anchas -- en móvil se sigue mostrando todo
  // junto en un solo scroll, como antes.
  int _pestanaContador = 0;
  // Celular: "Inicio" y "Clientes" del menú lateral desplazan la misma
  // pantalla (en escritorio son pestañas de la barra lateral).
  final ScrollController _scrollContador = ScrollController();
  final GlobalKey _claveClientes = GlobalKey();

  static const List<String> _ejemplosAsistenteContador = [
    "¿Cuánto IVA tiene que pagar Soda La Esquina este mes?",
    "¿Qué clientes van a pagar más Renta este año?",
    "Registrale a Soda La Esquina un gasto de luz de ₡18.500",
    "¿Cómo está la última factura de Ferretería El Tornillo?",
    "¿Tengo solicitudes de certificación pendientes?",
  ];
  static const List<(IconData, String)> _sugerenciasAsistenteContador = [
    (Icons.groups_outlined, "¿Cómo van mis clientes este mes?"),
    (Icons.percent, "IVA estimado de mis clientes"),
    (Icons.account_balance_outlined, "Renta estimada de mis clientes"),
    (Icons.badge_outlined, "Solicitudes de certificación pendientes"),
    (Icons.receipt_long_outlined, "Facturarle a un cliente"),
  ];

  void _abrirAsistenteContador() {
    abrirAsistentePantalla(
      context,
      secciones: _seccionesAsistenteContador,
      onNavegar: _irDesdeAsistenteContador,
      sugerencias: _sugerenciasAsistenteContador,
      saludo: _miSocio != null ? "Hola, ${_miSocio!.nombre}" : null,
    );
  }

  Future<void> _cerrarSesion() async {
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  /// Pantalla angosta: "Inicio" y "Clientes" de la barra lateral desplazan
  /// el mismo scroll (en escritorio son pestañas).
  void _desplazarEnPantallaAngosta(int pestana) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pestana == 0) {
        if (_scrollContador.hasClients) {
          _scrollContador.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
        }
      } else {
        final ctx = _claveClientes.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
      }
    });
  }
  // Solicitudes de Certificación pendientes -- se muestra como badge sobre
  // el ícono de "Certificaciones" en la sidebar, igual que en el menú de
  // Certificaciones (ver DocumentosContadorScreen), para que se note desde
  // afuera sin tener que entrar.
  int? _pendientesCertificaciones;
  // No-leídos de TODOS sus chats sumados -- mismo badge, ver item "Chats"
  // en la sidebar.
  int? _noLeidosChat;

  static const Map<String, String> _tiposCedula = {
    '01': 'Física',
    '02': 'Jurídica',
    '03': 'DIMEX',
    '04': 'NITE',
  };

  // Solo quien ve la cartera COMPLETA de otros (despacho o superusuario,
  // nunca un contador viendo sus propios negocios) puede mover un cliente
  // de un contador a otro -- ver reasignar_negocios en el backend
  // (SocioViewSet), que ya exige que el contador destino sea válido para
  // quien hace el pedido (mismo despacho, o cualquiera si es superusuario).
  bool get _puedeReasignar => !widget.puedeCrear && widget.puedeGestionarPlanes;
  List<Map<String, dynamic>> _sociosDisponibles = [];

  // Botón flotante del asistente en todas las pantallas del contador.
  late final ConfigAsistente _asistenteFlotante = ConfigAsistente(
    secciones: _seccionesAsistenteContador,
    onNavegar: _irDesdeAsistenteContador,
    abrirPantallaCompleta: _abrirAsistenteContador,
  );

  @override
  void initState() {
    super.initState();
    _cargarNegocios();
    _cargarPlanes();
    if (widget.puedeCrear) {
      AsistenteFlotante.registrar(_asistenteFlotante);
      _cargarMiSocio();
      _dashboardFuture = _cargarDashboard();
      _cargarPendientesCertificaciones();
      _cargarNoLeidosChat();
    }
    if (_puedeReasignar) {
      _cargarSociosDisponibles();
    }
    _busquedaCtrl.addListener(() {
      if (_busquedaSidebarCtrl.text != _busquedaCtrl.text) _busquedaSidebarCtrl.text = _busquedaCtrl.text;
      setState(() => _filtro = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  Future<void> _cargarPendientesCertificaciones() async {
    try {
      final r = await ApiService.get('/solicitudes-certificacion/?estado=pendiente');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _pendientesCertificaciones = data.length);
      }
    } catch (_) {}
  }

  Future<void> _cargarNoLeidosChat() async {
    try {
      final r = await ApiService.get('/chat/conversaciones/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        final total = data.fold<int>(0, (suma, c) => suma + ((c['no_leidos'] ?? 0) as int));
        if (mounted) setState(() => _noLeidosChat = total);
      }
    } catch (_) {}
  }

  Future<void> _cargarSociosDisponibles() async {
    try {
      final response = await ApiService.get('/socios/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _sociosDisponibles = data
                .map((j) => {'id': j['id'], 'nombre': j['nombre'] ?? '', 'nombre_despacho': j['nombre_despacho']})
                .toList();
          });
        }
      }
    } catch (_) {
      // Si falla, el botón de reasignar simplemente no encuentra candidatos.
    }
  }

  Future<void> _reasignarNegocio(Negocio negocio) async {
    if (negocio.socioId == null) return;
    final candidatos = _sociosDisponibles.where((s) => s['id'] != negocio.socioId).toList();
    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay otro contador disponible para reasignar.")),
      );
      return;
    }

    int? seleccionado;
    final resultado = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Reasignar ${negocio.nombreComercial}"),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Contador actual: ${negocio.nombreSocio ?? 'Sin asignar'}",
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: seleccionado,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Nuevo contador", border: OutlineInputBorder()),
                  items: candidatos
                      .map((s) => DropdownMenuItem<int?>(
                            value: s['id'] as int,
                            child: Text(
                              widget.esSuperusuario && s['nombre_despacho'] != null
                                  ? "${s['nombre']} (${s['nombre_despacho']})"
                                  : s['nombre'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => seleccionado = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              style: widget.puedeCrear
                  ? ElevatedButton.styleFrom(backgroundColor: _PaletaContador.acento, foregroundColor: Colors.white)
                  : null,
              onPressed: seleccionado == null ? null : () => Navigator.pop(ctx, seleccionado),
              child: const Text("Reasignar"),
            ),
          ],
        ),
      ),
    );
    if (resultado == null) return;

    try {
      final response = await ApiService.post('/socios/${negocio.socioId}/reasignar-negocios/', {
        'negocio_ids': [negocio.id],
        'nuevo_socio_id': resultado,
      });
      final datos = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200) {
        _cargarNegocios();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${negocio.nombreComercial} pasó a ${datos['nuevo_socio']}.")),
          );
        }
      } else {
        throw Exception(datos['detail'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo reasignar: $e")));
      }
    }
  }

  @override
  void dispose() {
    AsistenteFlotante.quitar(_asistenteFlotante);
    _busquedaCtrl.dispose();
    _busquedaSidebarCtrl.dispose();
    _scrollContador.dispose();
    super.dispose();
  }

  List<Negocio> get _negociosFiltrados {
    if (_filtro.isEmpty) return _negocios;
    return _negocios.where((n) {
      return n.nombreComercial.toLowerCase().contains(_filtro) || n.cedula.toLowerCase().contains(_filtro);
    }).toList();
  }

  Future<void> _cargarMiSocio() async {
    try {
      final response = await ApiService.get('/socios/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted && data.isNotEmpty) {
          setState(() => _miSocio = Socio.fromJson(data.first));
        }
      }
    } catch (_) {
      // Si falla, el encabezado simplemente no muestra el logo/nombre del contador.
    }
  }

  Future<Map<String, dynamic>> _cargarDashboard() async {
    try {
      final response = await ApiService.get('/socios/dashboard-despacho/');
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {
      // Si falla, el encabezado del dashboard simplemente no se muestra.
    }
    return {};
  }

  void _recargarTodo() {
    _cargarNegocios();
    if (widget.puedeCrear) {
      _cargarMiSocio();
      setState(() => _dashboardFuture = _cargarDashboard());
    }
  }

  Future<void> _abrirNegocioPorId(int negocioId) async {
    try {
      final response = await ApiService.get('/negocios/$negocioId/');
      if (response.statusCode == 200 && mounted) {
        final negocio = Negocio.fromJson(json.decode(utf8.decode(response.bodyBytes)));
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ResumenFiscalNegocioScreen(negocio: negocio)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir el negocio: $e")));
      }
    }
  }

  Future<void> _cargarPlanes() async {
    try {
      final response = await ApiService.get('/planes/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() => _planes = data.map((j) => Plan.fromJson(j)).toList());
        }
      }
    } catch (_) {
      // Si falla, simplemente no se ofrece selector de plan.
    }
  }

  Future<void> _cambiarPlan(Negocio negocio) async {
    int? planSeleccionado = negocio.planId;
    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Plan de ${negocio.nombreComercial}"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 360),
            child: DropdownButtonFormField<int?>(
              value: planSeleccionado,
              decoration: const InputDecoration(labelText: "Plan de suscripción", border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text("Sin plan asignado")),
                ..._planes.map((p) => DropdownMenuItem<int?>(value: p.id, child: Text(p.toString()))),
              ],
              onChanged: (v) => setStateDialog(() => planSeleccionado = v),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: widget.puedeCrear
                  ? ElevatedButton.styleFrom(backgroundColor: _PaletaContador.acento, foregroundColor: Colors.white)
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );

    if (resultado != true) return;
    try {
      final response = await ApiService.patch('/negocios/${negocio.id}/', {
        'plan': planSeleccionado?.toString() ?? '',
      });
      if (response.statusCode == 200) {
        _cargarNegocios();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cambiar el plan: $e")));
      }
    }
  }

  Future<void> _abrirMiPerfil() async {
    try {
      int? socioId = _miSocio?.id;
      String? logoUrl = _miSocio?.logoUrl;
      if (socioId == null) {
        final perfilResponse = await ApiService.get('/mi-perfil/');
        if (perfilResponse.statusCode != 200) throw Exception("No se pudo obtener el perfil");
        final perfil = json.decode(utf8.decode(perfilResponse.bodyBytes));
        socioId = perfil['socio_id'];
        if (socioId == null) throw Exception("No hay un contador asociado a esta cuenta");
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PerfilUsuarioScreen(
            nombre: _miSocio?.nombre ?? "Mi Perfil",
            subtitulo: "Contador",
            logoEndpoint: '/socios/$socioId/',
            logoUrlInicial: logoUrl,
            esContador: widget.puedeCrear,
          ),
        ),
      );
      _cargarMiSocio();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _cargarNegocios() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/negocios/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _negocios = data.map((j) => Negocio.fromJson(j)).toList()
              ..sort((a, b) => a.nombreComercial.toLowerCase().compareTo(b.nombreComercial.toLowerCase()));
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Error del servidor: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al cargar negocios: $e")),
        );
      }
    }
  }

  void _mostrarFormularioCrear() {
    final nombreCtrl = TextEditingController();
    final cedulaCtrl = TextEditingController();
    final correoHaciendaCtrl = TextEditingController();
    final codigoActividadCtrl = TextEditingController();
    final usuarioApiCtrl = TextEditingController();
    final claveApiCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String tipoCedula = '01';
    String entorno = 'STAGING';
    int? planSeleccionado;
    bool guardando = false;
    // Cargados de Hacienda con la cédula (ver CampoCedulaHacienda).
    String nombreLegal = '';
    String actividadAlanube = '';
    // Un negocio que solo lleva su contabilidad con el contador (Ingresos,
    // Compras, Reportes) pero no factura electrónicamente por acá no
    // necesita correo/usuario/clave de Hacienda -- eso trababa la creación
    // de este tipo de cliente pidiendo datos que nunca va a usar.
    bool facturaConEquilibra = true;

    // Para que el negocio no se le olvide su usuario, se precarga con el
    // Correo Hacienda mientras el contador no escriba uno distinto a mano.
    String ultimoCorreoAutocopiado = '';
    correoHaciendaCtrl.addListener(() {
      final correo = correoHaciendaCtrl.text.trim();
      final usernameActual = usernameCtrl.text.trim();
      if (usernameActual.isEmpty || usernameActual == ultimoCorreoAutocopiado) {
        usernameCtrl.text = correo;
        ultimoCorreoAutocopiado = correo;
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Nuevo Negocio"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // La cédula primero: carga de Hacienda el nombre, el tipo
                  // y la actividad económica.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: CampoCedulaHacienda(
                          controller: cedulaCtrl,
                          nombreController: nombreCtrl,
                          labelText: "Cédula *",
                          onEncontrado: (datos) => setStateDialog(() {
                            final tipo = (datos['tipo_cedula'] ?? '').toString();
                            if (_tiposCedula.containsKey(tipo)) tipoCedula = tipo;
                            nombreLegal = (datos['nombre'] ?? '').toString();
                            final principal = datos['actividad_principal'] as Map?;
                            actividadAlanube = (principal?['codigo'] ?? '').toString();
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(tipoCedula),
                          value: tipoCedula,
                          decoration: const InputDecoration(labelText: "Tipo", border: OutlineInputBorder()),
                          items: _tiposCedula.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => setStateDialog(() => tipoCedula = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: "Nombre Comercial *", border: OutlineInputBorder()),
                  ),
                  if (actividadAlanube.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text("Actividad económica de Hacienda: $actividadAlanube (se guarda para facturar)",
                          style: const TextStyle(fontSize: 12, color: Colors.green)),
                    ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: facturaConEquilibra,
                    title: const Text("Factura electrónicamente con Equilibra"),
                    subtitle: const Text("Desactivalo si es solo cliente contable del contador (Ingresos/Compras/Reportes)."),
                    onChanged: (v) => setStateDialog(() => facturaConEquilibra = v),
                  ),
                  if (facturaConEquilibra) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: correoHaciendaCtrl,
                      decoration: const InputDecoration(labelText: "Correo Hacienda *", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codigoActividadCtrl,
                      decoration: const InputDecoration(labelText: "Código Actividad (6 dígitos) *", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usuarioApiCtrl,
                      decoration: const InputDecoration(labelText: "Usuario API Hacienda", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: claveApiCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "Clave API Hacienda", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: entorno,
                      decoration: const InputDecoration(labelText: "Entorno Hacienda", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'STAGING', child: Text("Pruebas / Sandbox")),
                        DropdownMenuItem(value: 'PRODUCTION', child: Text("Producción / Real")),
                      ],
                      onChanged: (v) => setStateDialog(() => entorno = v!),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: planSeleccionado,
                    decoration: const InputDecoration(labelText: "Plan de suscripción", border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text("Sin plan asignado")),
                      ..._planes.map((p) => DropdownMenuItem<int?>(value: p.id, child: Text(p.toString()))),
                    ],
                    onChanged: (v) => setStateDialog(() => planSeleccionado = v),
                  ),
                  const Divider(height: 30),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Acceso a la app para este negocio", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(labelText: "Usuario *", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Contraseña *", border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              style: widget.puedeCrear
                  ? ElevatedButton.styleFrom(backgroundColor: _PaletaContador.acento, foregroundColor: Colors.white)
                  : null,
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty ||
                          cedulaCtrl.text.trim().isEmpty ||
                          usernameCtrl.text.trim().isEmpty ||
                          passwordCtrl.text.trim().isEmpty ||
                          (facturaConEquilibra &&
                              (correoHaciendaCtrl.text.trim().isEmpty ||
                                  codigoActividadCtrl.text.trim().isEmpty))) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Complete todos los campos obligatorios (*)")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.post('/negocios/', {
                          'nombre_comercial': nombreCtrl.text.trim(),
                          'cedula': cedulaCtrl.text.trim(),
                          'tipo_cedula': tipoCedula,
                          if (nombreLegal.isNotEmpty) 'nombre_legal': nombreLegal,
                          if (actividadAlanube.isNotEmpty) 'alanube_economic_activity': actividadAlanube,
                          'correo_hacienda': correoHaciendaCtrl.text.trim(),
                          'codigo_actividad': codigoActividadCtrl.text.trim(),
                          'usuario_api': usuarioApiCtrl.text.trim(),
                          'clave_api': claveApiCtrl.text.trim(),
                          'entorno_hacienda': entorno,
                          'username': usernameCtrl.text.trim(),
                          'password': passwordCtrl.text,
                          if (planSeleccionado != null) 'plan': planSeleccionado.toString(),
                        });
                        if (response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarNegocios();
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
                  : const Text("Crear"),
            ),
          ],
        ),
      ),
    );
  }

  /// El listado de Clientes no tenía ninguna forma de corregir un dato mal
  /// tecleado al crear el negocio (nombre, cédula, correo/actividad de
  /// Hacienda) -- lo único editable estaba escondido varios clics adentro,
  /// en Gestionar > Ajustes. Mismos campos que _mostrarFormularioCrear,
  /// precargados, con PUT en vez de POST.
  void _mostrarFormularioEditar(Negocio n) {
    final nombreCtrl = TextEditingController(text: n.nombreComercial);
    final cedulaCtrl = TextEditingController(text: n.cedula);
    final correoHaciendaCtrl = TextEditingController(text: n.correoHacienda ?? '');
    final codigoActividadCtrl = TextEditingController(text: n.codigoActividad ?? '');
    final usuarioApiCtrl = TextEditingController(text: n.usuarioApi ?? '');
    final claveApiCtrl = TextEditingController();
    String tipoCedula = n.tipoCedula;
    String entorno = n.entornoHacienda ?? 'STAGING';
    bool guardando = false;
    bool facturaConEquilibra = (n.correoHacienda?.isNotEmpty ?? false) || (n.codigoActividad?.isNotEmpty ?? false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Editar ${n.nombreComercial}"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: "Nombre Comercial *", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: cedulaCtrl,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: "Cédula *", border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: tipoCedula,
                          decoration: const InputDecoration(labelText: "Tipo", border: OutlineInputBorder()),
                          items: _tiposCedula.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => setStateDialog(() => tipoCedula = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: facturaConEquilibra,
                    title: const Text("Factura electrónicamente con Equilibra"),
                    subtitle: const Text("Desactivalo si es solo cliente contable del contador (Ingresos/Compras/Reportes)."),
                    onChanged: (v) => setStateDialog(() => facturaConEquilibra = v),
                  ),
                  if (facturaConEquilibra) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: correoHaciendaCtrl,
                      decoration: const InputDecoration(labelText: "Correo Hacienda *", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codigoActividadCtrl,
                      decoration: const InputDecoration(labelText: "Código Actividad (6 dígitos) *", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usuarioApiCtrl,
                      decoration: const InputDecoration(labelText: "Usuario API Hacienda", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: claveApiCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "Clave API Hacienda (dejar vacío para no cambiar)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: entorno,
                      decoration: const InputDecoration(labelText: "Entorno Hacienda", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'STAGING', child: Text("Pruebas / Sandbox")),
                        DropdownMenuItem(value: 'PRODUCTION', child: Text("Producción / Real")),
                      ],
                      onChanged: (v) => setStateDialog(() => entorno = v!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              style: widget.puedeCrear
                  ? ElevatedButton.styleFrom(backgroundColor: _PaletaContador.acento, foregroundColor: Colors.white)
                  : null,
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty ||
                          cedulaCtrl.text.trim().isEmpty ||
                          (facturaConEquilibra &&
                              (correoHaciendaCtrl.text.trim().isEmpty ||
                                  codigoActividadCtrl.text.trim().isEmpty))) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Complete todos los campos obligatorios (*)")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.patch('/negocios/${n.id}/', {
                          'nombre_comercial': nombreCtrl.text.trim(),
                          'cedula': cedulaCtrl.text.trim(),
                          'tipo_cedula': tipoCedula,
                          // Si se desactivó "Factura con Equilibra", se mandan vacíos
                          // a propósito para poder borrar datos de Hacienda que ya
                          // no aplican (partial_update solo ignora los que son null).
                          'correo_hacienda': facturaConEquilibra ? correoHaciendaCtrl.text.trim() : '',
                          'codigo_actividad': facturaConEquilibra ? codigoActividadCtrl.text.trim() : '',
                          'usuario_api': facturaConEquilibra ? usuarioApiCtrl.text.trim() : '',
                          'entorno_hacienda': entorno,
                          if (facturaConEquilibra && claveApiCtrl.text.trim().isNotEmpty) 'clave_api': claveApiCtrl.text.trim(),
                        });
                        if (response.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarNegocios();
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

  static const Map<String, String> _estadosSuscripcion = {
    'activo': 'Activo',
    'suspendido': 'Suspendido',
    'moroso': 'Moroso',
  };

  Color _colorEstadoSuscripcion(String? estado) {
    switch (estado) {
      case 'suspendido':
        return Colors.red;
      case 'moroso':
        return Colors.amber.shade800;
      case 'activo':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> _gestionarSuscripcion(Negocio negocio) async {
    String estado = negocio.suscripcionEstado ?? 'activo';
    final montoCtrl = TextEditingController();
    final medioPagoCtrl = TextEditingController();
    final notasCtrl = TextEditingController();

    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Renta de ${negocio.nombreComercial}"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: estado,
                    decoration: const InputDecoration(labelText: "Estado", border: OutlineInputBorder()),
                    items: _estadosSuscripcion.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => estado = v!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: montoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Monto mensual (₡)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: medioPagoCtrl,
                    decoration: const InputDecoration(labelText: "Medio de pago (ej: SINPE Móvil)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notasCtrl,
                    decoration: const InputDecoration(labelText: "Notas", border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (negocio.suscripcionId != null)
              TextButton.icon(
                icon: const Icon(Icons.credit_card, size: 18),
                label: const Text("Cobro automático"),
                onPressed: () async {
                  final activado = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OnvoCobroAutomaticoScreen(
                        tipo: 'negocio',
                        suscripcionId: negocio.suscripcionId!,
                        nombreTitular: negocio.nombreComercial,
                        yaTieneCobroAutomatico: negocio.suscripcionCobroAutomatico,
                      ),
                    ),
                  );
                  if (activado == true) {
                    if (ctx.mounted) Navigator.pop(ctx, false);
                    _cargarNegocios();
                  }
                },
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: widget.puedeCrear
                  ? ElevatedButton.styleFrom(backgroundColor: _PaletaContador.acento, foregroundColor: Colors.white)
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );

    if (resultado != true) return;
    final body = {
      'negocio': negocio.id.toString(),
      'estado': estado,
      if (montoCtrl.text.trim().isNotEmpty) 'monto_mensual': montoCtrl.text.trim(),
      if (medioPagoCtrl.text.trim().isNotEmpty) 'medio_pago': medioPagoCtrl.text.trim(),
      if (notasCtrl.text.trim().isNotEmpty) 'notas': notasCtrl.text.trim(),
    };
    try {
      final response = negocio.suscripcionId == null
          ? await ApiService.post('/suscripciones-negocio/', body)
          : await ApiService.patch('/suscripciones-negocio/${negocio.suscripcionId}/', body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cargarNegocios();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al actualizar la suscripción: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esContador = widget.puedeCrear;
    final esAncho = esContador && MediaQuery.sizeOf(context).width >= 900;
    return BloqueoSalidaRaiz(
      child: Scaffold(
      backgroundColor: esContador ? _PaletaContador.fondo : AppColors.background,
      appBar: esAncho ? null : AppBar(
        leading: (ModalRoute.of(context)?.canPop ?? false)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: "Volver",
                onPressed: () => Navigator.pop(context),
              )
            : null,
        backgroundColor: esContador ? _PaletaContador.fondo : const Color(0xFF4F46E5),
        foregroundColor: esContador ? _PaletaContador.textoFuerte : Colors.white,
        iconTheme: IconThemeData(color: esContador ? _PaletaContador.textoFuerte : Colors.white),
        elevation: 0,
        title: esContador
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ChipPerfil(color: _PaletaContador.acento),
                  const SizedBox(height: 3),
                  const Text(
                    "Mis Clientes",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _PaletaContador.textoFuerte),
                  ),
                ],
              )
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChipPerfil(color: Colors.white),
                  SizedBox(height: 3),
                  Text("Mis Negocios", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
        actions: esContador
            ? [
                _accionAppBarClara(icono: Icons.auto_awesome, tooltip: "Asistente Equilibra", onPressed: _abrirAsistenteContador),
                _accionAppBarClara(icono: Icons.refresh_rounded, tooltip: "Recargar", onPressed: _recargarTodo),
                const SizedBox(width: 4),
              ]
            : [
          if (esContador)
            _accionAppBarClara(icono: Icons.refresh_rounded, tooltip: "Recargar", onPressed: _recargarTodo)
          else
            accionAppBar(icono: Icons.refresh_rounded, tooltip: "Recargar", onPressed: _recargarTodo),
          if (widget.puedeCrear)
            esContador
                ? _accionAppBarClara(
                    icono: Icons.insert_chart_outlined,
                    tooltip: "Reportes",
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ReportesContadorScreen(esContador: true)),
                    ),
                  )
                : accionAppBar(
                    icono: Icons.insert_chart_outlined,
                    tooltip: "Reportes",
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ReportesContadorScreen()),
                    ),
                  ),
          if (esContador)
            _accionAppBarClara(
              icono: Icons.badge_outlined,
              tooltip: "Certificaciones",
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DocumentosContadorScreen()),
              ),
            ),
          if (esContador)
            _accionAppBarClara(
              icono: Icons.account_tree_outlined,
              tooltip: "Catálogo de cuentas",
              onPressed: () => abrirCatalogoCuentas(context),
            ),
          if (esContador)
            _accionAppBarClara(
              icono: Icons.account_balance_outlined,
              tooltip: "Bancos",
              onPressed: () => abrirBancos(context),
            ),
          if (esContador)
            _accionAppBarClara(
              icono: Icons.menu_book_outlined,
              tooltip: "Asientos Contables",
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AsientosContablesScreen()),
              ),
            ),
          if (widget.puedeCrear)
            esContador
                ? _accionAppBarClara(icono: Icons.account_circle_rounded, tooltip: "Mi Perfil", onPressed: _abrirMiPerfil)
                : accionAppBar(icono: Icons.account_circle_rounded, tooltip: "Mi Perfil", onPressed: _abrirMiPerfil),
          if (esContador)
            _accionAppBarClara(
              icono: Icons.support_agent,
              tooltip: "Soporte",
              onPressed: () => mostrarSoporteChat(context, contexto: 'usuario'),
            )
          else
            accionAppBar(
              icono: Icons.support_agent,
              tooltip: "Soporte",
              onPressed: () => mostrarSoporteChat(context, contexto: 'usuario'),
            ),
          if (!(ModalRoute.of(context)?.canPop ?? false))
            esContador
                ? _accionAppBarClara(
                    icono: Icons.logout,
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
                  )
                : accionAppBar(
                    icono: Icons.logout,
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
          const SizedBox(width: 6),
        ],
      ),
      body: esAncho
          ? Row(
              children: [
                _sidebarContador(context),
                Expanded(child: _contenidoNegocios(context, esContador, esAncho)),
              ],
            )
          : esContador
              ? Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: _anchoRail),
                      child: _contenidoNegocios(context, esContador, esAncho),
                    ),
                    if (_railAbierto)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => setState(() => _railAbierto = false),
                          child: const ColoredBox(color: Colors.black26),
                        ),
                      ),
                    Positioned(top: 0, bottom: 0, left: 0, child: _sidebarContador(context, superpuesta: true)),
                  ],
                )
              : _contenidoNegocios(context, esContador, esAncho),
      // Con la barra abierta encima del contenido (pantalla angosta) el botón
      // tapaba "Cerrar sesión".
      floatingActionButton: widget.puedeCrear && !(esContador && !esAncho && _railAbierto)
          ? FloatingActionButton.extended(
              onPressed: _mostrarFormularioCrear,
              icon: const Icon(Icons.add),
              label: const Text("NUEVO NEGOCIO"),
              backgroundColor: esContador ? _PaletaContador.acento : null,
              foregroundColor: esContador ? Colors.white : null,
            )
          : null,
    ),
    );
  }

  /// Secciones del panel del contador que la barra de IA puede abrir.
  static const Map<String, String> _seccionesAsistenteContador = {
    'clientes': 'Clientes: tu cartera de negocios, entrar a uno, ver su resumen fiscal',
    'nuevo_cliente': 'Nuevo cliente: agregar un negocio a tu cartera',
    'reportes': 'Reportes: ventas, compras e IVA de uno o varios clientes en PDF/Excel',
    'certificaciones': 'Certificaciones: certificaciones de ingresos, atestiguamientos, flujos de caja y solicitudes de clientes',
    'chats': 'Chats: conversaciones con tus clientes',
    'asientos': 'Asientos contables: catálogo de cuentas y asientos automáticos',
    'perfil': 'Mi perfil: datos de CPA, firmantes, membrete y plantilla de certificación',
  };

  Future<void> _irDesdeAsistenteContador(String clave) async {
    switch (clave) {
      case 'clientes':
        setState(() => _pestanaContador = 1);
      case 'nuevo_cliente':
        _mostrarFormularioCrear();
      case 'reportes':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ReportesContadorScreen(esContador: true)));
      case 'certificaciones':
        await Navigator.push(context, MaterialPageRoute(builder: (context) => const DocumentosContadorScreen()));
        _cargarPendientesCertificaciones();
      case 'chats':
        await Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatsContadorScreen()));
        _cargarNoLeidosChat();
      case 'asientos':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AsientosContablesScreen()));
      case 'perfil':
        _abrirMiPerfil();
    }
  }

  Widget _contenidoNegocios(BuildContext context, bool esContador, bool esAncho) {
    return Container(
        color: esContador ? _PaletaContador.fondo : AppColors.surfaceSubtle,
        child: CustomScrollView(
          controller: _scrollContador,
          slivers: [
            if (esAncho)
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: const BoxDecoration(
                    color: _PaletaContador.fondo,
                    border: Border(bottom: BorderSide(color: _PaletaContador.borde)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _pestanaContador == 0 ? "Inicio" : "Clientes",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _PaletaContador.textoFuerte),
                      ),
                      const Spacer(),
                      _accionAppBarClara(icono: Icons.refresh_rounded, tooltip: "Recargar", onPressed: _recargarTodo),
                    ],
                  ),
                ),
              ),
            // Antes el dashboard (tarjeta del contador + buildDashboardHeader)
            // vivía en un Column fijo por fuera del Expanded con la lista de
            // negocios, así que si crecía más que la pantalla (como pasó al
            // agregar las 5 secciones nuevas de alertas) no había forma de
            // hacer scroll para verlo completo -- quedaba "estático". Ahora
            // todo vive en un mismo CustomScrollView, dashboard y lista de
            // clientes incluidos, así que la pantalla entera se desplaza junta.
            if (!esAncho || _pestanaContador == 0) ...[
              // Lo primero del panel: preguntarle a la IA qué hacer.
              if (widget.puedeCrear)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: AsistenteIABar(
                      saludo: _miSocio != null ? "Hola, ${_miSocio!.nombre}" : null,
                      secciones: _seccionesAsistenteContador,
                      onNavegar: _irDesdeAsistenteContador,
                      ejemplos: _ejemplosAsistenteContador,
                      sugerencias: _sugerenciasAsistenteContador,
                    ),
                  ),
                ),
              if (widget.puedeCrear && _miSocio != null)
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    decoration: const BoxDecoration(
                      color: _PaletaContador.superficie,
                      border: Border(bottom: BorderSide(color: _PaletaContador.acento, width: 2)),
                    ),
                    child: Row(
                      children: [
                        avatarConLogo(
                          logoUrl: _miSocio!.logoUrl,
                          icono: Icons.badge_outlined,
                          radius: 28,
                          color: _PaletaContador.acento,
                          fondo: _PaletaContador.acento.withOpacity(0.14),
                          nombre: _miSocio!.nombre,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "CONTADOR INDEPENDIENTE",
                                style: TextStyle(
                                  color: _PaletaContador.acento, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _miSocio!.nombre,
                                style: const TextStyle(color: _PaletaContador.textoFuerte, fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _miSocio!.email,
                                style: const TextStyle(color: _PaletaContador.textoTenue, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.puedeCrear)
                SliverToBoxAdapter(
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _dashboardFuture,
                    builder: (context, snapshot) {
                      final d = snapshot.data ?? {};
                      if (snapshot.connectionState == ConnectionState.waiting || d.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return buildDashboardHeader(d, context: context, onAbrirNegocio: _abrirNegocioPorId, mostrarContadores: false, esContador: esContador);
                    },
                  ),
                ),
            ],
            if (!esAncho || _pestanaContador == 1) ...[
            if (_negocios.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  key: _claveClientes,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, widget.puedeCrear ? 24 : 12, 16, 4),
                      child: Row(
                        children: [
                          if (esContador) ...[
                            Container(width: 4, height: 18, color: _PaletaContador.acento),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              esContador ? "CARTERA DE CLIENTES (${_negocios.length})" : "Mis Clientes (${_negocios.length})",
                              style: esContador
                                  ? const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: _PaletaContador.textoFuerte,
                                    )
                                  : TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _busquedaCtrl,
                        style: esContador ? const TextStyle(color: _PaletaContador.textoFuerte) : null,
                        decoration: InputDecoration(
                          hintText: "Buscar negocio por nombre o cédula...",
                          hintStyle: esContador ? const TextStyle(color: _PaletaContador.textoTenue) : null,
                          prefixIcon: Icon(Icons.search, size: 20, color: esContador ? _PaletaContador.acento : null),
                          suffixIcon: _filtro.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(Icons.close, size: 18, color: esContador ? _PaletaContador.textoTenue : null),
                                  onPressed: () => _busquedaCtrl.clear(),
                                ),
                          isDense: true,
                          filled: true,
                          fillColor: esContador ? _PaletaContador.superficie : Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: esContador ? const BorderSide(color: _PaletaContador.borde) : BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: esContador ? const BorderSide(color: _PaletaContador.borde) : BorderSide.none,
                          ),
                          focusedBorder: esContador
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _PaletaContador.acento, width: 1.5),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isLoading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_negocios.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.business_center_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("Todavía no hay negocios registrados.", style: TextStyle(color: Colors.grey)),
                      if (widget.puedeCrear) ...[
                        const SizedBox(height: 4),
                        const Text(
                          "Usá el botón \"Nuevo Negocio\" para crear el primero.",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else if (_negociosFiltrados.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    "Ningún negocio coincide con \"${_busquedaCtrl.text}\"",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final n = _negociosFiltrados[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: esContador ? _PaletaContador.superficie : null,
                        elevation: esContador ? 0 : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(esContador ? 10 : 12),
                          side: esContador ? const BorderSide(color: _PaletaContador.borde) : BorderSide.none,
                        ),
                        child: ListTile(
                          leading: avatarConLogo(
                            logoUrl: n.logoUrl,
                            icono: Icons.business_center,
                            nombre: n.nombreComercial,
                            color: esContador ? _PaletaContador.acento : null,
                            fondo: esContador ? _PaletaContador.acento.withOpacity(0.14) : null,
                          ),
                          title: Text(
                            n.nombreComercial,
                            style: esContador
                                ? const TextStyle(fontWeight: FontWeight.w700, color: _PaletaContador.textoFuerte)
                                : const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              "Cédula: ${n.cedula}",
                              if (n.nombreSocio != null && n.nombreSocio!.isNotEmpty) "Contador: ${n.nombreSocio}",
                              n.planNombre != null && n.planNombre!.isNotEmpty
                                  ? (n.limiteFacturasMensual == null
                                      ? "Plan: ${n.planNombre} (documentos ilimitados)"
                                      : "Plan: ${n.planNombre} (${n.facturasDisponibles ?? 0}/${n.limiteFacturasMensual} documentos disp.)")
                                  : "Sin plan asignado",
                            ].join(" · "),
                            style: esContador ? const TextStyle(color: _PaletaContador.textoTenue, fontSize: 12.5) : null,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.puedeCrear)
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, color: esContador ? _PaletaContador.textoTenue : null),
                                  tooltip: "Editar",
                                  onPressed: () => _mostrarFormularioEditar(n),
                                ),
                              if (widget.puedeGestionarPlanes)
                                IconButton(
                                  icon: Icon(Icons.workspace_premium_outlined, color: esContador ? _PaletaContador.textoTenue : null),
                                  tooltip: "Cambiar plan",
                                  onPressed: () => _cambiarPlan(n),
                                ),
                              if (_puedeReasignar)
                                IconButton(
                                  icon: Icon(Icons.swap_horiz, color: esContador ? _PaletaContador.textoTenue : null),
                                  tooltip: "Reasignar a otro contador",
                                  onPressed: () => _reasignarNegocio(n),
                                ),
                              if (widget.esSuperusuario)
                                IconButton(
                                  icon: Icon(Icons.payments_outlined, color: _colorEstadoSuscripcion(n.suscripcionEstado)),
                                  tooltip: "Renta de la plataforma: ${_estadosSuscripcion[n.suscripcionEstado] ?? 'Sin registrar'}",
                                  onPressed: () => _gestionarSuscripcion(n),
                                ),
                              Icon(Icons.chevron_right, color: esContador ? _PaletaContador.acento : null),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ResumenFiscalNegocioScreen(negocio: n)),
                          ),
                        ),
                      );
                    },
                    childCount: _negociosFiltrados.length,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
  }

  static const double _anchoRail = 76;
  static const double _anchoSidebar = 264;

  /// Barra lateral del contador (diseño "Menú lateral del contador"):
  /// secciones Principal / Contabilidad / Documentos / Comunicación, tarjeta
  /// del contador y buscador de clientes. Colapsada queda en solo íconos.
  /// [superpuesta]: pantalla angosta -- arranca como franja de íconos y al
  /// expandirse se abre por encima del contenido.
  Widget _sidebarContador(BuildContext context, {bool superpuesta = false}) {
    final colapsada = superpuesta ? !_railAbierto : _sidebarColapsada;
    final ancho = colapsada ? _anchoRail : _anchoSidebar;
    void alternar() => setState(() {
          if (superpuesta) {
            _railAbierto = !_railAbierto;
          } else {
            _sidebarColapsada = !_sidebarColapsada;
          }
        });

    void irAPestana(int pestana) {
      if (superpuesta) {
        _desplazarEnPantallaAngosta(pestana);
      } else {
        setState(() => _pestanaContador = pestana);
      }
    }

    void tocar(VoidCallback accion) {
      if (superpuesta && _railAbierto) setState(() => _railAbierto = false);
      accion();
    }

    Widget globo(int cantidad, {bool chico = false}) => Container(
          constraints: BoxConstraints(minWidth: chico ? 16 : 20),
          height: chico ? 16 : 20,
          padding: EdgeInsets.symmetric(horizontal: chico ? 4 : 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _PaletaContador.sidebarAviso,
            borderRadius: BorderRadius.circular(999),
            border: chico ? Border.all(color: _PaletaContador.sidebarFondo, width: 2) : null,
          ),
          child: Text(
            cantidad > 99 ? '99+' : '$cantidad',
            style: TextStyle(color: Colors.white, fontSize: chico ? 9 : 11, fontWeight: FontWeight.w700, height: 1),
          ),
        );

    Widget item({
      required IconData icono,
      required String etiqueta,
      required VoidCallback onTap,
      bool activo = false,
      int? badge,
      Widget? extra,
      Color? color,
      Color? colorIcono,
    }) {
      if (superpuesta) activo = false; // en pantalla angosta no hay pestañas
      final hayBadge = badge != null && badge > 0;
      final colorTexto = color ?? (activo ? _PaletaContador.sidebarTextoActivo : _PaletaContador.sidebarTexto);
      final iconoW = Icon(icono, size: 19, color: colorIcono ?? (activo ? _PaletaContador.sidebarAcento : colorTexto));
      final contenido = colapsada
          ? Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  iconoW,
                  if (hayBadge) Positioned(top: -8, right: -11, child: globo(badge, chico: true)),
                ],
              ),
            )
          : Row(
              children: [
                iconoW,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    etiqueta,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorTexto, fontSize: 13.5, fontWeight: activo ? FontWeight.w600 : FontWeight.w500),
                  ),
                ),
                if (hayBadge) globo(badge),
                if (extra != null) extra,
              ],
            );
      final boton = Material(
        color: activo ? _PaletaContador.sidebarAcento.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withOpacity(0.05),
          onTap: () => tocar(onTap),
          child: SizedBox(
            height: colapsada ? 44 : 40,
            child: Padding(padding: EdgeInsets.symmetric(horizontal: colapsada ? 0 : 10), child: contenido),
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: colapsada ? 16 : 14, vertical: 1),
        child: colapsada ? Tooltip(message: hayBadge ? '$etiqueta ($badge)' : etiqueta, child: boton) : boton,
      );
    }

    Widget seccion(String titulo, {bool primera = false}) {
      if (colapsada) {
        return primera
            ? const SizedBox(height: 8)
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(child: Container(width: 28, height: 1, color: Colors.white.withOpacity(0.08))),
              );
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(24, primera ? 10 : 18, 24, 6),
        child: Text(
          titulo,
          style: const TextStyle(color: _PaletaContador.sidebarEtiqueta, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9),
        ),
      );
    }

    final logo = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _PaletaContador.sidebarAcento, borderRadius: BorderRadius.circular(9)),
      child: const Text('e', style: TextStyle(color: _PaletaContador.sidebarFondo, fontWeight: FontWeight.w800, fontSize: 19, height: 1)),
    );
    final botonAlternar = Tooltip(
      message: colapsada ? "Expandir menú" : "Colapsar menú",
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: alternar,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              colapsada ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded,
              size: 17,
              color: _PaletaContador.sidebarEtiqueta,
            ),
          ),
        ),
      ),
    );
    final encabezado = colapsada
        ? Column(children: [logo, const SizedBox(height: 8), botonAlternar])
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                logo,
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Equilibra", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5, letterSpacing: -0.2)),
                      SizedBox(height: 1),
                      Text("MODO CONTADOR",
                          style: TextStyle(color: _PaletaContador.sidebarEtiqueta, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.4)),
                    ],
                  ),
                ),
                botonAlternar,
              ],
            ),
          );

    // Cuenta (abajo): una sola fila con el contador; Mi perfil, Soporte y
    // Cerrar sesión van en su menú en vez de ocupar tres filas fijas.
    final avatar = avatarConLogo(
      logoUrl: _miSocio?.logoUrl,
      icono: Icons.badge_outlined,
      radius: 16,
      color: Colors.white,
      fondo: _PaletaContador.sidebarAvatar,
      nombre: _miSocio?.nombre ?? '',
    );
    PopupMenuItem<String> opcionCuenta(String valor, IconData icono, String texto, {Color color = Colors.white}) => PopupMenuItem<String>(
          value: valor,
          height: 42,
          child: Row(
            children: [
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 12),
              Text(texto, style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ],
          ),
        );
    final cuenta = PopupMenuButton<String>(
      tooltip: "Cuenta",
      color: _PaletaContador.sidebarTarjeta,
      elevation: 8,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      onSelected: (opcion) => tocar(() {
        switch (opcion) {
          case 'perfil':
            _abrirMiPerfil();
          case 'soporte':
            mostrarSoporteChat(context, contexto: 'usuario');
          case 'salir':
            _cerrarSesion();
        }
      }),
      itemBuilder: (_) => [
        opcionCuenta('perfil', Icons.account_circle_outlined, "Mi perfil"),
        opcionCuenta('soporte', Icons.support_outlined, "Soporte"),
        const PopupMenuDivider(height: 8),
        opcionCuenta('salir', Icons.logout_rounded, "Cerrar sesión", color: _PaletaContador.sidebarSalir),
      ],
      child: colapsada
          ? SizedBox(height: 52, child: Center(child: avatar))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _miSocio?.nombre ?? 'Contador',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          (_miSocio?.email ?? '').isNotEmpty ? _miSocio!.email : 'Contador',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _PaletaContador.sidebarEtiqueta, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.unfold_more_rounded, size: 18, color: _PaletaContador.sidebarEtiqueta),
                ],
              ),
            ),
    );

    // Buscar cliente: el mismo filtro que la lista de clientes, y lleva ahí.
    final buscador = colapsada
        ? item(icono: Icons.search_rounded, etiqueta: "Buscar cliente", onTap: alternar)
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _busquedaSidebarCtrl,
                onChanged: (texto) {
                  _busquedaCtrl.text = texto;
                  if (texto.isNotEmpty && (superpuesta || _pestanaContador != 1)) irAPestana(1);
                },
                onSubmitted: (_) {
                  if (superpuesta) setState(() => _railAbierto = false);
                },
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                cursorColor: _PaletaContador.sidebarAcento,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _PaletaContador.sidebarCampo,
                  hintText: "Buscar cliente…",
                  hintStyle: const TextStyle(color: _PaletaContador.sidebarEtiqueta, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 17, color: _PaletaContador.sidebarEtiqueta),
                  prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.07)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _PaletaContador.sidebarAcento),
                  ),
                ),
              ),
            ),
          );

    final contenido = SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 14),
          encabezado,
          const SizedBox(height: 14),
          buscador,
          // Con scroll propio: en ventanas bajas las entradas no caben.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              children: [
                seccion("PRINCIPAL", primera: true),
                item(icono: Icons.home_outlined, etiqueta: "Inicio", activo: _pestanaContador == 0, onTap: () => irAPestana(0)),
                item(icono: Icons.groups_outlined, etiqueta: "Clientes", activo: _pestanaContador == 1, onTap: () => irAPestana(1)),
                item(
                  icono: Icons.auto_awesome_outlined,
                  etiqueta: "Asistente Equilibra",
                  colorIcono: colapsada ? _PaletaContador.sidebarAcento : null,
                  onTap: _abrirAsistenteContador,
                  extra: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _PaletaContador.sidebarAcento),
                    ),
                    child: const Text("IA", style: TextStyle(color: _PaletaContador.sidebarAcento, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
                seccion("CONTABILIDAD"),
                item(icono: Icons.account_tree_outlined, etiqueta: "Catálogo de cuentas", onTap: () => abrirCatalogoCuentas(context)),
                item(
                  icono: Icons.menu_book_outlined,
                  etiqueta: "Asientos contables",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AsientosContablesScreen())),
                ),
                item(icono: Icons.account_balance_outlined, etiqueta: "Bancos", onTap: () => abrirBancos(context)),
                seccion("DOCUMENTOS"),
                item(
                  icono: Icons.insert_chart_outlined,
                  etiqueta: "Reportes",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ReportesContadorScreen(esContador: true))),
                ),
                item(
                  icono: Icons.verified_outlined,
                  etiqueta: "Certificaciones",
                  badge: _pendientesCertificaciones,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => const DocumentosContadorScreen()));
                    _cargarPendientesCertificaciones();
                  },
                ),
                seccion("COMUNICACIÓN"),
                item(
                  icono: Icons.chat_bubble_outline_rounded,
                  etiqueta: "Chats con clientes",
                  badge: _noLeidosChat,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatsContadorScreen()));
                    _cargarNoLeidosChat();
                  },
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: EdgeInsets.symmetric(horizontal: colapsada ? 24 : 14),
            color: Colors.white.withOpacity(0.07),
          ),
          cuenta,
          const SizedBox(height: 4),
        ],
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: ancho,
      color: _PaletaContador.sidebarFondo,
      // El contenido se arma al ancho final y se recorta mientras la barra
      // se abre o se cierra, en vez de apretarse (y desbordar) a medio camino.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: ancho,
          maxWidth: ancho,
          child: contenido,
        ),
      ),
    );
  }
}
