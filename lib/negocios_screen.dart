import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'avatar_logo.dart';
import 'dashboard_despacho_widgets.dart';
import 'negocio.dart';
import 'onvo_cobro_automatico_screen.dart';
import 'perfil_usuario_screen.dart';
import 'plan.dart';
import 'reportes_contador_screen.dart';
import 'resumen_fiscal_screen.dart';
import 'socio.dart';
import 'login.dart';
import 'widgets/bloqueo_salida_raiz.dart';
import 'widgets/soporte_chat.dart';

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
  String _filtro = "";

  static const Map<String, String> _tiposCedula = {
    '01': 'Física',
    '02': 'Jurídica',
    '03': 'DIMEX',
    '04': 'NITE',
  };

  @override
  void initState() {
    super.initState();
    _cargarNegocios();
    _cargarPlanes();
    if (widget.puedeCrear) {
      _cargarMiSocio();
      _dashboardFuture = _cargarDashboard();
    }
    _busquedaCtrl.addListener(() {
      setState(() => _filtro = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
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
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
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
            _negocios = data.map((j) => Negocio.fromJson(j)).toList();
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
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty ||
                          cedulaCtrl.text.trim().isEmpty ||
                          correoHaciendaCtrl.text.trim().isEmpty ||
                          codigoActividadCtrl.text.trim().isEmpty ||
                          usernameCtrl.text.trim().isEmpty ||
                          passwordCtrl.text.trim().isEmpty) {
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
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
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
    return BloqueoSalidaRaiz(
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: "Volver",
                onPressed: () => Navigator.pop(context),
              )
            : null,
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Mis Negocios",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          accionAppBar(icono: Icons.refresh_rounded, tooltip: "Recargar", onPressed: _recargarTodo),
          if (widget.puedeCrear)
            accionAppBar(
              icono: Icons.insert_chart_outlined,
              tooltip: "Reportes",
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReportesContadorScreen()),
              ),
            ),
          if (widget.puedeCrear)
            accionAppBar(icono: Icons.account_circle_rounded, tooltip: "Mi Perfil", onPressed: _abrirMiPerfil),
          accionAppBar(
            icono: Icons.support_agent,
            tooltip: "Soporte",
            onPressed: () => mostrarSoporteChat(context, contexto: 'usuario'),
          ),
          if (!Navigator.canPop(context))
            accionAppBar(
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
      body: Container(
        color: AppColors.surfaceSubtle,
        child: CustomScrollView(
          slivers: [
            // Antes el dashboard (tarjeta del contador + buildDashboardHeader)
            // vivía en un Column fijo por fuera del Expanded con la lista de
            // negocios, así que si crecía más que la pantalla (como pasó al
            // agregar las 5 secciones nuevas de alertas) no había forma de
            // hacer scroll para verlo completo -- quedaba "estático". Ahora
            // todo vive en un mismo CustomScrollView, dashboard y lista de
            // clientes incluidos, así que la pantalla entera se desplaza junta.
            if (widget.puedeCrear && _miSocio != null)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF312E81)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      avatarConLogo(
                        logoUrl: _miSocio!.logoUrl,
                        icono: Icons.badge_outlined,
                        radius: 26,
                        color: Colors.white,
                        fondo: Colors.white24,
                        nombre: _miSocio!.nombre,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _miSocio!.nombre,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              "Contador · ${_miSocio!.email}",
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                    return buildDashboardHeader(d, onAbrirNegocio: _abrirNegocioPorId, mostrarContadores: false);
                  },
                ),
              ),
            if (_negocios.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, widget.puedeCrear ? 16 : 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Mis Clientes (${_negocios.length})",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _busquedaCtrl,
                        decoration: InputDecoration(
                          hintText: "Buscar negocio por nombre o cédula...",
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _filtro.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => _busquedaCtrl.clear(),
                                ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
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
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _mostrarFormularioCrear,
                          icon: const Icon(Icons.add),
                          label: const Text("Crear el primer negocio"),
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
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: avatarConLogo(logoUrl: n.logoUrl, icono: Icons.business_center, nombre: n.nombreComercial),
                          title: Text(n.nombreComercial, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            [
                              "Cédula: ${n.cedula}",
                              if (n.nombreSocio != null && n.nombreSocio!.isNotEmpty) "Contador: ${n.nombreSocio}",
                              n.planNombre != null && n.planNombre!.isNotEmpty
                                  ? "Plan: ${n.planNombre} (${n.facturasDisponibles ?? 0}/${n.limiteFacturasMensual ?? 0} facturas disp.)"
                                  : "Sin plan asignado",
                            ].join(" · "),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.puedeGestionarPlanes)
                                IconButton(
                                  icon: const Icon(Icons.workspace_premium_outlined),
                                  tooltip: "Cambiar plan",
                                  onPressed: () => _cambiarPlan(n),
                                ),
                              if (widget.esSuperusuario)
                                IconButton(
                                  icon: Icon(Icons.payments_outlined, color: _colorEstadoSuscripcion(n.suscripcionEstado)),
                                  tooltip: "Renta de la plataforma: ${_estadosSuscripcion[n.suscripcionEstado] ?? 'Sin registrar'}",
                                  onPressed: () => _gestionarSuscripcion(n),
                                ),
                              const Icon(Icons.chevron_right),
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
        ),
      ),
      floatingActionButton: widget.puedeCrear
          ? FloatingActionButton.extended(
              onPressed: _mostrarFormularioCrear,
              icon: const Icon(Icons.add),
              label: const Text("NUEVO NEGOCIO"),
            )
          : null,
    ),
    );
  }
}
