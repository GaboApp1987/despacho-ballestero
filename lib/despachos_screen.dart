import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'avatar_logo.dart';
import 'despacho.dart';
import 'negocios_screen.dart';
import 'onvo_cobro_automatico_screen.dart';
import 'planes_screen.dart';
import 'login.dart';
import 'widgets/bloqueo_salida_raiz.dart';
import 'widgets/soporte_chat.dart';
import 'whatsapp_bandeja_screen.dart';
import 'estadisticas_screen.dart';

/// Pantalla de nivel plataforma: solo la ve un superusuario (el dueño del programa).
/// Desde acá se dan de alta los despachos contables (cada uno con su propio dueño/login),
/// que luego crean sus propios contadores.
class DespachosScreen extends StatefulWidget {
  const DespachosScreen({super.key});

  @override
  State<DespachosScreen> createState() => _DespachosScreenState();
}

class _DespachosScreenState extends State<DespachosScreen> {
  bool _isLoading = true;
  List<Despacho> _despachos = [];
  // Conversaciones de WhatsApp sin atender (badge del botón de la bandeja).
  int _whatsappPendientes = 0;

  Future<void> _cargarPendientesWhatsApp() async {
    try {
      final r = await ApiService.get('/whatsapp/conversaciones/pendientes/');
      if (r.statusCode == 200 && mounted) {
        setState(() => _whatsappPendientes = (json.decode(r.body)['pendientes'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {
      // Sin badge si falla -- la bandeja igual se puede abrir.
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarDespachos();
    _cargarPendientesWhatsApp();
  }

  Future<void> _cargarDespachos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/despachos/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _despachos = data.map((j) => Despacho.fromJson(j)).toList();
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
          SnackBar(content: Text("Error al cargar despachos: $e")),
        );
      }
    }
  }

  void _mostrarFormularioCrear() {
    final nombreCtrl = TextEditingController();
    final cedulaCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Nuevo Despacho"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: "Nombre del Despacho *", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cedulaCtrl,
                  decoration: const InputDecoration(labelText: "Cédula Jurídica", border: OutlineInputBorder()),
                ),
                const Divider(height: 30),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Acceso para el dueño del despacho", style: TextStyle(fontWeight: FontWeight.bold)),
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
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Correo del despacho",
                    helperText: "Para mandarle el correo de bienvenida",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty ||
                          usernameCtrl.text.trim().isEmpty ||
                          passwordCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Complete los campos obligatorios (*)")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.post('/despachos/', {
                          'nombre': nombreCtrl.text.trim(),
                          'cedula_juridica': cedulaCtrl.text.trim(),
                          'username': usernameCtrl.text.trim(),
                          'password': passwordCtrl.text,
                          'email': emailCtrl.text.trim(),
                        });
                        if (response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarDespachos();
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

  void _mostrarFormularioEditar(Despacho d) {
    final nombreCtrl = TextEditingController(text: d.nombre);
    final cedulaCtrl = TextEditingController(text: d.cedulaJuridica ?? '');
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: d.emailActual ?? '');
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Editar ${d.nombre}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: "Nombre del Despacho *", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cedulaCtrl,
                  decoration: const InputDecoration(labelText: "Cédula Jurídica", border: OutlineInputBorder()),
                ),
                const Divider(height: 30),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Cambiar acceso (dejar en blanco para no tocarlo)", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(labelText: "Nuevo usuario", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Nueva contraseña", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Correo del despacho", border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("El nombre es obligatorio")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.patch('/despachos/${d.id}/', {
                          'nombre': nombreCtrl.text.trim(),
                          'cedula_juridica': cedulaCtrl.text.trim(),
                          if (usernameCtrl.text.trim().isNotEmpty) 'username': usernameCtrl.text.trim(),
                          if (passwordCtrl.text.isNotEmpty) 'password': passwordCtrl.text,
                          if (emailCtrl.text.trim().isNotEmpty) 'email': emailCtrl.text.trim(),
                        });
                        if (response.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarDespachos();
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

  void _confirmarEliminar(Despacho d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Eliminar despacho?"),
        content: Text(
          "Se va a borrar \"${d.nombre}\" junto con todos sus contadores, negocios y facturas. "
          "Esta acción no se puede deshacer.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final response = await ApiService.delete('/despachos/${d.id}/');
                if (response.statusCode == 204) {
                  _cargarDespachos();
                } else {
                  throw Exception(utf8.decode(response.bodyBytes));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al eliminar: $e")));
                }
              }
            },
            child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
        ],
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

  Future<void> _gestionarSuscripcion(Despacho despacho) async {
    String estado = despacho.suscripcionEstado ?? 'activo';
    final montoCtrl = TextEditingController();
    final medioPagoCtrl = TextEditingController();
    final notasCtrl = TextEditingController();

    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Cuota de ${despacho.nombre}"),
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
            if (despacho.suscripcionId != null)
              TextButton.icon(
                icon: const Icon(Icons.credit_card, size: 18),
                label: const Text("Cobro automático"),
                onPressed: () async {
                  final activado = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OnvoCobroAutomaticoScreen(
                        tipo: 'despacho',
                        suscripcionId: despacho.suscripcionId!,
                        nombreTitular: despacho.nombre,
                        yaTieneCobroAutomatico: despacho.suscripcionCobroAutomatico,
                      ),
                    ),
                  );
                  if (activado == true) {
                    if (ctx.mounted) Navigator.pop(ctx, false);
                    _cargarDespachos();
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
      'despacho': despacho.id.toString(),
      'estado': estado,
      if (montoCtrl.text.trim().isNotEmpty) 'monto_mensual': montoCtrl.text.trim(),
      if (medioPagoCtrl.text.trim().isNotEmpty) 'medio_pago': medioPagoCtrl.text.trim(),
      if (notasCtrl.text.trim().isNotEmpty) 'notas': notasCtrl.text.trim(),
    };
    try {
      final response = despacho.suscripcionId == null
          ? await ApiService.post('/suscripciones-despacho/', body)
          : await ApiService.patch('/suscripciones-despacho/${despacho.suscripcionId}/', body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cargarDespachos();
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "PANEL DE ADMINISTRADOR",
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.primary),
            ),
            const Text("Despachos"),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Bandeja de WhatsApp",
            icon: Badge(
              isLabelVisible: _whatsappPendientes > 0,
              label: Text('$_whatsappPendientes'),
              child: const Icon(Icons.chat_outlined),
            ),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppBandejaScreen()));
              _cargarPendientesWhatsApp();
            },
          ),
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: "Estadísticas del landing",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstadisticasScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.workspace_premium_outlined),
            tooltip: "Planes de suscripción",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlanesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.business_center_outlined),
            tooltip: "Ver todos los negocios",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NegociosScreen(puedeCrear: false, puedeGestionarPlanes: true, esSuperusuario: true),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDespachos),
          IconButton(
            icon: const Icon(Icons.support_agent),
            tooltip: "Soporte",
            onPressed: () => mostrarSoporteChat(context, contexto: 'usuario'),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _despachos.isEmpty
              ? const Center(child: Text("Todavía no hay despachos registrados.", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _despachos.length,
                  itemBuilder: (context, index) {
                    final d = _despachos[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: avatarConLogo(logoUrl: d.logoUrl, icono: Icons.account_balance, nombre: d.nombre),
                        title: Text(d.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "${d.cedulaJuridica?.isNotEmpty == true ? 'Cédula: ${d.cedulaJuridica}' : 'Sin cédula registrada'}"
                          "${d.emailActual?.isNotEmpty == true ? ' · ${d.emailActual}' : ''}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.payments_outlined, color: _colorEstadoSuscripcion(d.suscripcionEstado)),
                              tooltip: "Cuota del despacho: ${_estadosSuscripcion[d.suscripcionEstado] ?? 'Sin registrar'}",
                              onPressed: () => _gestionarSuscripcion(d),
                            ),
                            PopupMenuButton<String>(
                              tooltip: "Más opciones",
                              onSelected: (accion) {
                                if (accion == 'editar') _mostrarFormularioEditar(d);
                                if (accion == 'eliminar') _confirmarEliminar(d);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'editar', child: Text("Editar")),
                                PopupMenuItem(value: 'eliminar', child: Text("Eliminar")),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarFormularioCrear,
        icon: const Icon(Icons.add),
        label: const Text("NUEVO DESPACHO"),
      ),
    ),
    );
  }
}
