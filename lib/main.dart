import 'dart:async';
import 'package:flutter/material.dart';
import 'login.dart'; // <--- Mantenemos tu importación del Login
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'solicitud_publica_screen.dart';

// AUDITORIA.md hallazgo C4 -- antes, una excepción sin capturar en
// cualquier pantalla no tenía ningún manejador global: en release, Flutter
// solo mostraba una pantalla gris vacía y nadie se enteraba de que pasó,
// salvo que el usuario lo reportara a mano. runZonedGuarded +
// FlutterError.onError + PlatformDispatcher.instance.onError cubren los
// tres orígenes posibles de un error no capturado (síncrono en la zona de
// la app, del framework de Flutter al construir/renderizar un widget, y
// asíncrono fuera de cualquier try/catch). Por ahora solo se registra en
// consola (visible con `flutter logs`/Railway no aplica acá, es
// dispositivo del cliente) -- conectar un servicio remoto tipo Sentry
// (ya usado del lado del backend, ver config/settings.py) es un paso
// aparte que necesita una cuenta/DSN propios para Flutter.
void _registrarError(Object error, StackTrace stack, {String origen = ''}) {
  debugPrint('❌ Error no capturado${origen.isNotEmpty ? ' ($origen)' : ''}: $error');
  debugPrint('$stack');
}

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    _registrarError(details.exception, details.stack ?? StackTrace.current, origen: 'framework');
    FlutterError.presentError(details);
  };
  // ErrorWidget.builder reemplaza la pantalla roja/gris por defecto de un
  // widget que falló al construirse -- sigue sin "arreglar" el error, pero
  // no deja a la persona mirando una pantalla en blanco sin ninguna pista.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Ocurrió un error inesperado en esta pantalla.\nProbá volver atrás o reabrir la app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      ),
    );
  };

  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) => _registrarError(error, stack, origen: 'async'),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Link público de Solicitudes de Certificación (sin login): si la URL
    // trae ?solicitud=<codigo> (ej. equilibracr.com/app/?solicitud=ABC1234),
    // arrancamos directo en el formulario público en vez de en el login --
    // Uri.base refleja la URL real del navegador en Flutter Web sin
    // necesitar ningún paquete de ruteo.
    final codigoSolicitud = Uri.base.queryParameters['solicitud'];

    // ValueListenableBuilder reconstruye MaterialApp (y por lo tanto TODA
    // la app debajo) cada vez que se toca el botón de tema -- ver
    // theme/theme_controller.dart. AppTheme.light/dark ya se encargan de
    // dejar los valores mutables de AppColors en el modo correcto antes de
    // que el resto de las pantallas se reconstruya y los vuelva a leer.
    return ValueListenableBuilder<bool>(
      valueListenable: themeController,
      builder: (context, esOscuro, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Equilibra',
          theme: esOscuro ? AppTheme.dark : AppTheme.light,
          home: (codigoSolicitud != null && codigoSolicitud.trim().isNotEmpty)
              ? SolicitudPublicaScreen(codigoInicial: codigoSolicitud)
              : const LoginScreen(), // <--- La App inicia aquí con el diseño completo
        );
      },
    );
  }
}
