import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'avatar_logo.dart';
import 'despacho.dart';
import 'socio.dart';
import 'negocio.dart';
import 'negocios_screen.dart';
import 'detalle_contador_screen.dart';
import 'resumen_fiscal_screen.dart';
import 'perfil_usuario_screen.dart';
import 'dashboard_despacho_widgets.dart';
import 'login.dart';
import 'widgets/bloqueo_salida_raiz.dart';
import 'widgets/soporte_chat.dart';

class ContadoresScreen extends StatefulWidget {
  const ContadoresScreen({super.key});

  @override
  State<ContadoresScreen> createState() => _ContadoresScreenState();
}

class _ContadoresScreenState extends State<ContadoresScreen> {
  bool _isLoading = true;
  List<Socio> _socios = [];
  Despacho? _miDespacho;
  late Future<Map<String, dynamic>> _dashboardFuture;
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _filtro = "";

  @override
  void initState() {
    super.initState();
    _cargarSocios();
    _cargarMiDespacho();
    _dashboardFuture = _cargarDashboard();
    _busquedaCtrl.addListener(() {
      setState(() => _filtro = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  List<Socio> get _sociosFiltrados {
    if (_filtro.isEmpty) return _socios;
    return _socios.where((s) {
      return s.nombre.toLowerCase().contains(_filtro) || s.email.toLowerCase().contains(_filtro);
    }).toList();
  }

  Future<void> _cargarMiDespacho() async {
    try {
      final response = await ApiService.get('/despachos/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted && data.isNotEmpty) {
          setState(() => _miDespacho = Despacho.fromJson(data.first));
        }
      }
    } catch (_) {
      // Si falla, el encabezado simplemente no muestra el logo/nombre del despacho.
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
    _cargarSocios();
    setState(() => _dashboardFuture = _cargarDashboard());
  }

  Future<void> _abrirNegocioPorId(int negocioId) async {
    try {
      final response = await ApiService.get('/negocios/$negocioId/');
      if (response.statusCode == 200 && mounted) {
        final negocio = Negocio.fromJson(
          json.decode(utf8.decode(response.bodyBytes)),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResumenFiscalNegocioScreen(negocio: negocio),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo abrir el negocio: $e")),
        );
      }
    }
  }

  Future<void> _abrirMiPerfil() async {
    try {
      int? despachoId = _miDespacho?.id;
      String? logoUrl = _miDespacho?.logoUrl;
      if (despachoId == null) {
        final perfilResponse = await ApiService.get('/mi-perfil/');
        if (perfilResponse.statusCode != 200)
          throw Exception("No se pudo obtener el perfil");
        final perfil = json.decode(utf8.decode(perfilResponse.bodyBytes));
        despachoId = perfil['despacho_id'];
        if (despachoId == null)
          throw Exception("No hay un despacho asociado a esta cuenta");
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PerfilUsuarioScreen(
            nombre: _miDespacho?.nombre ?? "Mi Despacho",
            subtitulo: "Dueño del Despacho",
            logoEndpoint: '/despachos/$despachoId/',
            logoUrlInicial: logoUrl,
          ),
        ),
      );
      _cargarMiDespacho();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _cargarSocios() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/socios/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _socios = data.map((j) => Socio.fromJson(j)).toList();
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
          SnackBar(content: Text("Error al cargar contadores: $e")),
        );
      }
    }
  }

  void _mostrarFormularioCrear() {
    final nombreCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Nuevo Contador"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: "Nombre *",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Correo *",
                    border: OutlineInputBorder(),
                  ),
                ),
                const Divider(height: 30),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Acceso a la app",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Usuario *",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Contraseña *",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.pop(ctx),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty ||
                          emailCtrl.text.trim().isEmpty ||
                          usernameCtrl.text.trim().isEmpty ||
                          passwordCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text("Complete todos los campos"),
                          ),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.post('/socios/', {
                          'nombre': nombreCtrl.text.trim(),
                          'email': emailCtrl.text.trim(),
                          'username': usernameCtrl.text.trim(),
                          'password': passwordCtrl.text,
                        });
                        if (response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarSocios();
                        } else {
                          throw Exception(utf8.decode(response.bodyBytes));
                        }
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(
                            ctx,
                          ).showSnackBar(SnackBar(content: Text("Error: $e")));
                        }
                      }
                    },
              child: guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text("Crear"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BloqueoSalidaRaiz(
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Mis Contadores",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          accionAppBar(
            icono: Icons.business_center_rounded,
            tooltip: "Ver todos los negocios",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NegociosScreen(
                  puedeCrear: false,
                  puedeGestionarPlanes: true,
                ),
              ),
            ),
          ),
          accionAppBar(
            icono: Icons.refresh_rounded,
            tooltip: "Recargar",
            onPressed: _recargarTodo,
          ),
          accionAppBar(
            icono: Icons.account_circle_rounded,
            tooltip: "Mi Perfil",
            onPressed: _abrirMiPerfil,
          ),
          accionAppBar(
            icono: Icons.support_agent,
            tooltip: "Soporte",
            onPressed: () => mostrarSoporteChat(context, contexto: 'usuario'),
          ),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _recargarTodo(),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (_miDespacho != null)
                    Container(
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
                            logoUrl: _miDespacho!.logoUrl,
                            icono: Icons.account_balance,
                            radius: 26,
                            color: Colors.white,
                            fondo: Colors.white24,
                            nombre: _miDespacho!.nombre,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _miDespacho!.nombre,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                if (_miDespacho!.cedulaJuridica?.isNotEmpty == true)
                                  Text(
                                    "Cédula: ${_miDespacho!.cedulaJuridica}",
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _dashboardFuture,
                    builder: (context, snapshot) {
                      final d = snapshot.data ?? {};
                      if (snapshot.connectionState == ConnectionState.waiting ||
                          d.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return buildDashboardHeader(d, onAbrirNegocio: _abrirNegocioPorId);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      "Mis Contadores (${_socios.length})",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ),
                  if (_socios.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        controller: _busquedaCtrl,
                        decoration: InputDecoration(
                          hintText: "Buscar contador por nombre o correo...",
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
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ),
                  if (_socios.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          "Todavía no has creado ningún contador.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else if (_sociosFiltrados.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          "Ningún contador coincide con \"${_busquedaCtrl.text}\"",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        children: _sociosFiltrados.map((s) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: avatarConLogo(logoUrl: s.logoUrl, icono: Icons.badge_outlined, nombre: s.nombre),
                              title: Text(
                                s.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                "${s.email} · ${s.cantidadNegocios} negocio(s)",
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        DetalleContadorScreen(socio: s),
                                  ),
                                );
                                _recargarTodo();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarFormularioCrear,
        icon: const Icon(Icons.add),
        label: const Text("NUEVO CONTADOR"),
      ),
    ),
    );
  }

}
