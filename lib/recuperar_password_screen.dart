import 'package:flutter/material.dart';
import 'dart:convert';
import 'api_service.dart';
import 'theme/app_theme.dart';

/// Flujo de "olvidé mi contraseña" sin sesión iniciada: pide el usuario,
/// el backend manda un código de 6 dígitos al correo asociado (si existe),
/// y aquí mismo se confirma el código junto con la nueva contraseña.
class RecuperarPasswordScreen extends StatefulWidget {
  const RecuperarPasswordScreen({super.key});

  @override
  State<RecuperarPasswordScreen> createState() => _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  final _usernameController = TextEditingController();
  final _codigoController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _codigoSolicitado = false;
  bool _cargando = false;
  bool _ocultarClave = true;

  InputDecoration _decoracion(String hint, IconData icono) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icono, size: 20),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Future<void> _solicitarCodigo() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingrese su usuario")),
      );
      return;
    }
    setState(() => _cargando = true);
    try {
      final response = await ApiService.post('/recuperar-password/solicitar/', {'username': username});
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _codigoSolicitado = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Si el usuario tiene un correo registrado, le llegará un código en unos minutos."),
            duration: Duration(seconds: 6),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo procesar la solicitud. Intente de nuevo."), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error de conexión: $e")),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmarNuevaPassword() async {
    final codigo = _codigoController.text.trim();
    final nueva = _nuevaController.text;
    final confirmar = _confirmarController.text;

    if (codigo.isEmpty || nueva.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingrese el código y la nueva contraseña")),
      );
      return;
    }
    if (nueva.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La nueva contraseña debe tener al menos 6 caracteres")),
      );
      return;
    }
    if (nueva != confirmar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La nueva contraseña y su confirmación no coinciden")),
      );
      return;
    }

    setState(() => _cargando = true);
    try {
      final response = await ApiService.post('/recuperar-password/confirmar/', {
        'username': _usernameController.text.trim(),
        'codigo': codigo,
        'nueva_password': nueva,
      });
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Contraseña actualizada. Ya puede iniciar sesión."), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      } else {
        final data = json.decode(utf8.decode(response.bodyBytes));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? "Código inválido o vencido."), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error de conexión: $e")),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(title: const Text("Recuperar contraseña")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _codigoSolicitado ? "Ingrese el código" : "¿Olvidó su contraseña?",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                ),
                const SizedBox(height: 6),
                Text(
                  _codigoSolicitado
                      ? "Revise su correo: le enviamos un código de 6 dígitos válido por 15 minutos."
                      : "Ingrese su usuario y le enviaremos un código al correo asociado a su cuenta.",
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _usernameController,
                  enabled: !_codigoSolicitado,
                  decoration: _decoracion("Usuario", Icons.person_outline),
                ),
                if (_codigoSolicitado) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codigoController,
                    keyboardType: TextInputType.number,
                    decoration: _decoracion("Código de 6 dígitos", Icons.pin_outlined),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nuevaController,
                    obscureText: _ocultarClave,
                    decoration: _decoracion("Nueva contraseña", Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_ocultarClave ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                        onPressed: () => setState(() => _ocultarClave = !_ocultarClave),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmarController,
                    obscureText: _ocultarClave,
                    onSubmitted: (_) => _cargando ? null : _confirmarNuevaPassword(),
                    decoration: _decoracion("Confirmar nueva contraseña", Icons.lock_outline),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _cargando ? null : (_codigoSolicitado ? _confirmarNuevaPassword : _solicitarCodigo),
                    child: _cargando
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_codigoSolicitado ? "Actualizar contraseña" : "Enviar código"),
                  ),
                ),
                if (_codigoSolicitado) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _cargando ? null : () => setState(() => _codigoSolicitado = false),
                      child: const Text("Usar otro usuario / reenviar código"),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
