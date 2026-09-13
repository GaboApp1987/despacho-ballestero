import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'avatar_logo.dart';
import 'login.dart';
import 'logo_screen.dart';

/// Pantalla de "Mi Perfil" reutilizable para el usuario que tiene la sesión
/// abierta (despacho, contador o negocio): logo, cambio de contraseña y
/// cerrar sesión, todo en un solo lugar en vez de íconos sueltos en el AppBar.
class PerfilUsuarioScreen extends StatefulWidget {
  final String nombre;
  final String? subtitulo;
  final String logoEndpoint; // ej: '/despachos/1/', '/socios/3/', '/negocios/5/'
  final String? logoUrlInicial;
  final bool esContador;

  const PerfilUsuarioScreen({
    super.key,
    required this.nombre,
    this.subtitulo,
    required this.logoEndpoint,
    this.logoUrlInicial,
    this.esContador = false,
  });

  @override
  State<PerfilUsuarioScreen> createState() => _PerfilUsuarioScreenState();
}

class _PerfilUsuarioScreenState extends State<PerfilUsuarioScreen> {
  String? _logoUrl;
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _ocultarActual = true;
  bool _ocultarNueva = true;
  bool _cambiandoPassword = false;
  bool _whatsappCargando = false;
  Map<String, dynamic>? _whatsappResultado;

  Color get _colorFondo => widget.esContador ? TemaContador.fondo : AppColors.background;
  Color get _colorSuperficie => widget.esContador ? TemaContador.superficie : AppColors.surface;
  Color get _colorBorde => widget.esContador ? TemaContador.borde : AppColors.border;
  Color get _colorFuerte => widget.esContador ? TemaContador.textoFuerte : AppColors.textStrong;
  Color get _colorAcento => widget.esContador ? TemaContador.acento : AppColors.primary;

  InputDecoration _decoracionCampo(String label, {Widget? suffixIcon}) {
    if (!widget.esContador) {
      return InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: suffixIcon);
    }
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: TemaContador.textoTenue),
      filled: true,
      fillColor: TemaContador.superficie,
      border: const OutlineInputBorder(borderSide: BorderSide(color: TemaContador.borde)),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: TemaContador.borde)),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: TemaContador.acento, width: 1.5)),
      suffixIcon: suffixIcon,
    );
  }

  @override
  void initState() {
    super.initState();
    _logoUrl = widget.logoUrlInicial;
  }

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirCambiarLogo() async {
    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LogoScreen(
          titulo: "Mi Logo",
          endpoint: widget.logoEndpoint,
          logoUrlInicial: _logoUrl,
        ),
      ),
    );
    if (actualizado == true) {
      try {
        final response = await ApiService.get(widget.logoEndpoint);
        if (response.statusCode == 200 && mounted) {
          setState(() => _logoUrl = json.decode(utf8.decode(response.bodyBytes))['logo']);
        }
      } catch (_) {
        // si falla, se queda con el logo anterior en pantalla
      }
    }
  }

  Future<void> _cambiarPassword() async {
    if (_actualCtrl.text.isEmpty || _nuevaCtrl.text.isEmpty || _confirmarCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complete los tres campos")),
      );
      return;
    }
    if (_nuevaCtrl.text != _confirmarCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La nueva contraseña y su confirmación no coinciden")),
      );
      return;
    }
    if (_nuevaCtrl.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La nueva contraseña debe tener al menos 8 caracteres")),
      );
      return;
    }

    setState(() => _cambiandoPassword = true);
    try {
      final response = await ApiService.post('/mi-perfil/', {
        'password_actual': _actualCtrl.text,
        'password_nueva': _nuevaCtrl.text,
      });
      if (response.statusCode == 200) {
        _actualCtrl.clear();
        _nuevaCtrl.clear();
        _confirmarCtrl.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Contraseña actualizada"), backgroundColor: Colors.green),
          );
        }
      } else {
        final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'Error desconocido';
        throw Exception(detalle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
      }
    } finally {
      if (mounted) setState(() => _cambiandoPassword = false);
    }
  }

  Future<void> _vincularWhatsApp() async {
    setState(() => _whatsappCargando = true);
    try {
      final response = await ApiService.post('/whatsapp/generar-codigo/', {});
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200) {
        setState(() => _whatsappResultado = data);
      } else {
        throw Exception(data['detail'] ?? 'No se pudo generar el código de vinculación');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
      }
    } finally {
      if (mounted) setState(() => _whatsappCargando = false);
    }
  }

  Future<void> _abrirCodigoEnWhatsApp() async {
    final uri = Uri.parse(_whatsappResultado!['wa_link']);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo abrir WhatsApp.")),
      );
    }
  }

  Future<void> _confirmarCerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Cerrar sesión?"),
        content: const Text("Tendrá que volver a ingresar su usuario y contraseña."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Cerrar sesión")),
        ],
      ),
    );
    if (confirmar != true) return;
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: "Volver",
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Mi Perfil", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: _colorSuperficie,
        foregroundColor: _colorFuerte,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  InkWell(
                    onTap: _abrirCambiarLogo,
                    borderRadius: BorderRadius.circular(50),
                    child: Stack(
                      children: [
                        avatarConLogo(logoUrl: _logoUrl, icono: Icons.account_circle, radius: 50, nombre: widget.nombre),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: _colorSuperficie, shape: BoxShape.circle),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(widget.nombre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.esContador ? _colorFuerte : null)),
                  if (widget.subtitulo != null)
                    Text(widget.subtitulo!, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _abrirCambiarLogo,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text("Cambiar logo"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _colorSuperficie,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _colorBorde),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Cambiar Contraseña", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.esContador ? _colorFuerte : null)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _actualCtrl,
                    obscureText: _ocultarActual,
                    style: widget.esContador ? const TextStyle(color: TemaContador.textoFuerte) : null,
                    decoration: _decoracionCampo(
                      "Contraseña actual",
                      suffixIcon: IconButton(
                        icon: Icon(
                          _ocultarActual ? Icons.visibility_off : Icons.visibility,
                          color: widget.esContador ? TemaContador.textoTenue : null,
                        ),
                        onPressed: () => setState(() => _ocultarActual = !_ocultarActual),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nuevaCtrl,
                    obscureText: _ocultarNueva,
                    style: widget.esContador ? const TextStyle(color: TemaContador.textoFuerte) : null,
                    decoration: _decoracionCampo(
                      "Nueva contraseña",
                      suffixIcon: IconButton(
                        icon: Icon(
                          _ocultarNueva ? Icons.visibility_off : Icons.visibility,
                          color: widget.esContador ? TemaContador.textoTenue : null,
                        ),
                        onPressed: () => setState(() => _ocultarNueva = !_ocultarNueva),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmarCtrl,
                    obscureText: _ocultarNueva,
                    style: widget.esContador ? const TextStyle(color: TemaContador.textoFuerte) : null,
                    decoration: _decoracionCampo("Confirmar nueva contraseña"),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _cambiandoPassword ? null : _cambiarPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _colorAcento,
                        foregroundColor: widget.esContador ? Colors.white : Colors.black,
                      ),
                      child: _cambiandoPassword
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: widget.esContador ? Colors.white : Colors.black),
                            )
                          : Text(
                              "Actualizar Contraseña",
                              style: TextStyle(color: widget.esContador ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _colorSuperficie,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _colorBorde),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_outlined, size: 20, color: widget.esContador ? _colorFuerte : null),
                      const SizedBox(width: 8),
                      Text("WhatsApp", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.esContador ? _colorFuerte : null)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_whatsappResultado == null) ...[
                    const Text(
                      "Vinculá tu WhatsApp para recibir avisos y consultarle cosas al asistente directamente desde ahí.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _whatsappCargando ? null : _vincularWhatsApp,
                        icon: _whatsappCargando
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.link),
                        label: const Text("Vincular WhatsApp"),
                      ),
                    ),
                  ] else if (_whatsappResultado!['telefono'] != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Ya vinculado: ${_whatsappResultado!['telefono']}",
                            style: TextStyle(fontSize: 13, color: widget.esContador ? _colorFuerte : null),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      "Enviá este código desde tu WhatsApp al número indicado para completar la vinculación (vence en ${_whatsappResultado!['vence_en_minutos']} minutos):",
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _colorFondo,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _colorBorde),
                      ),
                      child: Text(
                        _whatsappResultado!['codigo'] ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: widget.esContador ? _colorFuerte : null),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _abrirCodigoEnWhatsApp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _colorAcento,
                          foregroundColor: widget.esContador ? Colors.white : Colors.black,
                        ),
                        icon: Icon(Icons.open_in_new, color: widget.esContador ? Colors.white : Colors.black),
                        label: Text(
                          "Abrir WhatsApp y enviar código",
                          style: TextStyle(color: widget.esContador ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _confirmarCerrarSesion,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                icon: const Icon(Icons.logout),
                label: const Text("Cerrar Sesión"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
