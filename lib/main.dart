import 'package:flutter/material.dart';
import 'login.dart'; // <--- Mantenemos tu importación del Login
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
          home: const LoginScreen(), // <--- La App inicia aquí con el diseño completo
        );
      },
    );
  }
}
