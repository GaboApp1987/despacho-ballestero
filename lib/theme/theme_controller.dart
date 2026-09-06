import 'package:flutter/material.dart';

/// Notifica a MyApp (main.dart) cuando el usuario alterna claro/oscuro desde
/// el botón del dashboard, para que reconstruya MaterialApp con el ThemeData
/// que corresponda -- ver AppTheme.light/dark, que a su vez actualizan los
/// valores mutables de AppColors que leen todas las pantallas.
class ThemeController extends ValueNotifier<bool> {
  ThemeController() : super(true); // arranca en oscuro

  bool get esOscuro => value;

  void alternar() => value = !value;
}

final themeController = ThemeController();
