import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'avatar_logo.dart';
import 'despacho.dart';
import 'negocios_screen.dart';
import 'planes_screen.dart';
import 'login.dart';
import 'widgets/bloqueo_salida_raiz.dart';
import 'widgets/soporte_chat.dart';

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

  @override
  void initState() {
    super.initState();
    _cargarDespachos();
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
        title: const Text("Despachos"),
        actions: [
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
                        subtitle: Text(d.cedulaJuridica?.isNotEmpty == true ? "Cédula: ${d.cedulaJuridica}" : "Sin cédula registrada"),
                        trailing: IconButton(
                          icon: Icon(Icons.payments_outlined, color: _colorEstadoSuscripcion(d.suscripcionEstado)),
                          tooltip: "Cuota del despacho: ${_estadosSuscripcion[d.suscripcionEstado] ?? 'Sin registrar'}",
                          onPressed: () => _gestionarSuscripcion(d),
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
