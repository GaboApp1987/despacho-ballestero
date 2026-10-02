import 'package:flutter/material.dart';

/// Perfil con el que se inició sesión (ver login.dart
/// _resolverPerfilYNavegar). Sirve para mostrar en la barra superior con
/// qué perfil se está trabajando: no es lo mismo el dueño viendo su negocio
/// que el contador o el despacho entrando a ese mismo negocio.
class PerfilSesion {
  static String? rol;
  static String? rolEmpleado;

  static void fijar(String? nuevoRol, {String? empleado}) {
    rol = nuevoRol;
    rolEmpleado = empleado;
  }

  static void limpiar() => fijar(null);

  /// (etiqueta, ícono) del perfil activo, o null si no se sabe.
  static (String, IconData)? get descripcion {
    switch (rol) {
      case 'negocio':
        return ('Negocio', Icons.storefront_rounded);
      case 'empleado':
        return (rolEmpleado == 'cajero' ? 'Negocio · Cajero' : 'Negocio · Colaborador', Icons.badge_outlined);
      case 'socio':
        return ('Contador', Icons.calculate_rounded);
      case 'despacho':
        return ('Despacho', Icons.apartment_rounded);
      case 'superuser':
        return ('Administrador', Icons.admin_panel_settings_rounded);
      default:
        return null;
    }
  }
}

/// Etiqueta chica "Perfil: Contador" para la barra superior.
class ChipPerfil extends StatelessWidget {
  /// Color del texto/ícono; por defecto el primario del tema.
  final Color? color;
  const ChipPerfil({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final d = PerfilSesion.descripcion;
    if (d == null) return const SizedBox.shrink();
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: "Estás trabajando con el perfil de ${d.$1.toLowerCase()}",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(d.$2, size: 12, color: c),
            const SizedBox(width: 4),
            Text(
              d.$1.toUpperCase(),
              maxLines: 1,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c),
            ),
          ],
        ),
      ),
    );
  }
}
