import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'api_service.dart'; // <--- Importamos la capa central de API
import 'detalle_negocio.dart';
import 'negocio.dart';
import 'negocios_screen.dart';
import 'contadores_screen.dart';
import 'despachos_screen.dart';
import 'widgets/staggered_entrance.dart';
import 'widgets/animated_logo.dart';
import 'widgets/soporte_chat.dart';
import 'recuperar_password_screen.dart';
import 'registro_publico_screen.dart';
import 'suscripcion_suspendida_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _ocultarClave = true;
  // Mientras se revisa si ya hay una sesión guardada (ver initState/
  // _restaurarSesion) se muestra un loader en vez del formulario, para no
  // parpadear el login y luego saltar a la pantalla real.
  bool _verificandoSesion = true;

  @override
  void initState() {
    super.initState();
    _restaurarSesion();
  }

  /// Si el navegador ya tiene un token guardado (sesión previa), intenta
  /// entrar directo sin pedir usuario/clave de nuevo -- antes esta pantalla
  /// SIEMPRE mostraba el formulario vacío al montarse, sin importar si el
  /// token seguía siendo válido, así que cualquier cosa que la trajera de
  /// vuelta (recargar la página, o el botón "atrás" del navegador llegando
  /// hasta acá) se sentía como "me sacó del sistema" aunque la sesión
  /// siguiera activa. ApiService.get ya renueva el token solo si venció.
  Future<void> _restaurarSesion() async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _verificandoSesion = false);
      return;
    }
    try {
      await _resolverPerfilYNavegar();
    } catch (_) {
      // Sin conexión u otro error inesperado: se queda en el login normal,
      // no tiene sentido bloquear al usuario con un error acá.
    }
    if (mounted) setState(() => _verificandoSesion = false);
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);

    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor ingrese usuario y contraseña")),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Petición del Token JWT a Django REST
      final url = Uri.parse('${ApiService.baseUrl}/token/');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Guardamos el access token y el refresh token localmente
        // (el refresh permite renovar la sesión sola sin volver a pedir login).
        await ApiService.saveTokens(access: data['access'], refresh: data['refresh']);
        await _resolverPerfilYNavegar();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Usuario o contraseña incorrectos"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error de conexión: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Consulta el rol del usuario ya autenticado (token válido, recién
  /// obtenido por login o restaurado de una sesión previa) para saber a qué
  /// pantalla enrutarlo, y navega ahí reemplazando el login (pushReplacement)
  /// para que no quede en el historial:
  ///   dueño de negocio -> directo a su negocio
  ///   contador -> lista de sus negocios (puede crear más)
  ///   dueño de despacho -> lista de sus contadores
  Future<void> _resolverPerfilYNavegar() async {
    String rol = 'ninguno';
    String? rolEmpleado;
    try {
      final perfilResponse = await ApiService.get('/mi-perfil/');
      if (perfilResponse.statusCode == 200) {
        final data = json.decode(utf8.decode(perfilResponse.bodyBytes));
        rol = data['rol'] ?? 'ninguno';
        rolEmpleado = data['rol_empleado'];
      } else if (perfilResponse.statusCode == 402) {
        // Suscripción suspendida por falta de pago: se mantiene la sesión
        // (para poder llamar a iniciar/confirmar-cobro-automatico como
        // dueño de la suscripción) y se ofrece reactivar pagando de nuevo,
        // en vez de simplemente cerrar la sesión y avisar por un SnackBar.
        final data = json.decode(utf8.decode(perfilResponse.bodyBytes));
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => SuscripcionSuspendidaScreen(
                tipo: data['rol'] ?? 'negocio',
                suscripcionId: data['suscripcion_id'],
                nombre: data['nombre'] ?? '',
                motivo: data['motivo'] ?? "Esta cuenta está suspendida por falta de pago.",
              ),
            ),
            (route) => false,
          );
        }
        return;
      } else if (perfilResponse.statusCode == 403) {
        // Acceso de empleado desactivado por el dueño del negocio.
        final data = json.decode(utf8.decode(perfilResponse.bodyBytes));
        await ApiService.logout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['motivo'] ?? "Esta cuenta está suspendida."),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return;
      } else {
        // Ej. 401: el token venció y el refresh también es inválido
        // (ApiService.get ya intentó renovarlo antes de llegar acá). No hay
        // sesión válida -- se limpia y se deja el formulario de login.
        await ApiService.logout();
        return;
      }
    } catch (e) {
      debugPrint("Nota: no se pudo determinar el rol del usuario: $e");
    }

    Widget pantallaDestino;
    switch (rol) {
      case 'negocio':
      case 'empleado':
        // Un 'empleado' (cajero/acceso completo) entra al mismo negocio
        // que su dueño ve, pero con la seccion/acciones restringidas
        // segun rolEmpleado (ver DetalleNegocio._menuItemsVisibles).
        // Sin esto no hay negocio válido que mostrar: antes se seguía
        // adelante con un Negocio(id: 0) de mentira si esta llamada
        // fallaba (ej. un hipo de red en celular), y todo lo que se
        // intentara crear después (productos, facturas...) fallaba con
        // "invalid pk 0" sin que quedara claro por qué. Ahora se
        // reintenta un par de veces y, si de verdad no hay forma de
        // cargar el negocio, se avisa y no se avanza.
        Negocio? negocioFinal;
        Object? ultimoError;
        for (var intento = 0; intento < 3 && negocioFinal == null; intento++) {
          try {
            final negResponse = await ApiService.get('/negocios/mi-empresa/');
            if (negResponse.statusCode == 200) {
              negocioFinal = Negocio.fromJson(json.decode(utf8.decode(negResponse.bodyBytes)));
            } else {
              ultimoError = utf8.decode(negResponse.bodyBytes);
            }
          } catch (e) {
            ultimoError = e;
          }
          if (negocioFinal == null && intento < 2) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        if (negocioFinal == null) {
          await ApiService.logout();
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("No se pudo cargar tu negocio (revisa tu conexión e intenta de nuevo): $ultimoError"),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          return;
        }
        pantallaDestino = DetalleNegocio(negocio: negocioFinal, rolEmpleado: rol == 'empleado' ? rolEmpleado : null);
        break;
      case 'socio':
        pantallaDestino = const NegociosScreen(puedeCrear: true);
        break;
      case 'despacho':
        pantallaDestino = const ContadoresScreen();
        break;
      case 'superuser':
        // Dueño de la plataforma: administra los despachos (nivel más alto).
        pantallaDestino = const DespachosScreen();
        break;
      default:
        // Cuentas autenticadas sin ningún perfil asignado todavía.
        pantallaDestino = const NegociosScreen(puedeCrear: false);
    }

    // 🚀 Navegación hacia la pantalla principal
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => pantallaDestino),
      );
    }
  }

  Widget _blobDecorativo({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _bulletFeature(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Colors.white, size: 13),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.25)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoSesion) {
      // Evita el parpadeo de mostrar el formulario vacío un instante antes
      // de saltar a la pantalla real cuando ya había una sesión guardada.
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final Size size = MediaQuery.of(context).size;
    final bool esAngosto = size.width <= 800;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // 🌌 LADO IZQUIERDO: Identidad de marca "Equilibra"
          if (!esAngosto)
            Expanded(
              flex: 5,
              child: Container(
                height: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0B1120), Color(0xFF0B2530), AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -80,
                      right: -60,
                      child: Opacity(opacity: 0.10, child: _blobDecorativo(size: 260, color: Colors.white)),
                    ),
                    Positioned(
                      bottom: -100,
                      left: -60,
                      child: Opacity(opacity: 0.08, child: _blobDecorativo(size: 300, color: Colors.white)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(50, 50, 50, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Este panel siempre tiene fondo oscuro (gradiente fijo, no
                          // cambia con el tema claro/oscuro de la app), por eso usa el
                          // logo "oscuro" (trazos blancos) sin problema. Ya trae su
                          // propia animación de entrada (dibujo + rebote + destello),
                          // por eso no se envuelve en StaggeredEntrance.
                          const AnimatedLogoEquilibra(height: 56),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StaggeredEntrance(
                                index: 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                                  ),
                                  child: const Text(
                                    "THE HYBRID APP FOR ACCOUNTING FIRMS",
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              StaggeredEntrance(
                                index: 2,
                                child: const Text(
                                  "Facturación, IVA y Renta\nen equilibrio perfecto.",
                                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, height: 1.2),
                                ),
                              ),
                              const SizedBox(height: 12),
                              StaggeredEntrance(
                                index: 3,
                                child: Text(
                                  "100% en la nube: tus datos siempre disponibles, desde cualquier dispositivo.",
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.4),
                                ),
                              ),
                              const SizedBox(height: 22),
                              StaggeredEntrance(index: 4, child: _bulletFeature("Facturación electrónica ante Hacienda")),
                              StaggeredEntrance(index: 5, child: _bulletFeature("Declaraciones de IVA y Renta listas para presentar")),
                              StaggeredEntrance(index: 6, child: _bulletFeature("Gestión de clientes e inventario")),
                              StaggeredEntrance(index: 7, child: _bulletFeature("Todo en la nube: sin instalaciones ni respaldos manuales")),
                              StaggeredEntrance(index: 8, child: _bulletFeature("Hecho para firmas contables, contadores y negocios")),
                            ],
                          ),
                          StaggeredEntrance(
                            index: 9,
                            child: Text(
                              "© 2026 Equilibra. Todos los derechos reservados.",
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 📝 LADO DERECHO: Formulario de Login
          Expanded(
            flex: 4,
            child: Container(
              height: double.infinity,
              color: AppColors.background,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(48.0),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: child),
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.all(36),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (esAngosto) ...[
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                decoration: BoxDecoration(
                                  // Fondo oscuro fijo (no depende del tema claro/oscuro
                                  // de la app) para que el logo -- trazos blancos --
                                  // siempre se vea bien, también en el celular en
                                  // posición vertical (esta tarjeta sí cambia de color
                                  // según el tema).
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0B1120), Color(0xFF0B2530)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const AnimatedLogoEquilibra(height: 38),
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],
                          Text(
                            "¡Bienvenido de nuevo!",
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Ingresa tus credenciales para acceder a tu cuenta.",
                            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                          ),
                          const SizedBox(height: 32),

                          Text("Usuario", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textMuted)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              hintText: "Ingrese su usuario",
                              prefixIcon: const Icon(Icons.person_outline, size: 20),
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
                            ),
                          ),
                          const SizedBox(height: 20),

                          Text("Contraseña", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textMuted)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passwordController,
                            obscureText: _ocultarClave,
                            onSubmitted: (_) => _isLoading ? null : _login(),
                            decoration: InputDecoration(
                              hintText: "••••••••",
                              prefixIcon: const Icon(Icons.lock_outline, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(_ocultarClave ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                                onPressed: () => setState(() => _ocultarClave = !_ocultarClave),
                              ),
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
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RecuperarPasswordScreen()),
                              ),
                              child: Text("¿Olvidó su contraseña?", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 12),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              onPressed: _isLoading ? null : _login,
                              child: _isLoading
                                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                  : const Text("INGRESAR AL SISTEMA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RegistroPublicoScreen()),
                              ),
                              child: Text.rich(
                                TextSpan(
                                  text: "¿No tenés cuenta? ",
                                  style: TextStyle(color: AppColors.textMuted),
                                  children: [
                                    TextSpan(
                                      text: "Registrate",
                                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton.icon(
                              onPressed: () => mostrarSoporteChat(context, contexto: 'visitante'),
                              icon: Icon(Icons.support_agent, size: 18, color: AppColors.textMuted),
                              label: Text("¿Necesitás ayuda?", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}