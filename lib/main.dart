import 'package:flutter/material.dart';
import 'login.dart'; // <--- Mantenemos tu importación del Login
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'solicitud_publica_screen.dart';

void main() {
  runApp(const MyApp());
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
