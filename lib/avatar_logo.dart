import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

/// Paleta fija para los avatares de iniciales: el color se deriva del
/// nombre (siempre el mismo color para la misma persona/negocio) en vez de
/// ser aleatorio, para que se pueda reconocer a alguien de un vistazo.
const List<Color> _paletaAvatares = [
  Color(0xFF4F46E5),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

Color _colorDesdeNombre(String nombre) {
  final normalizado = nombre.trim().toLowerCase();
  final hash = normalizado.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return _paletaAvatares[hash % _paletaAvatares.length];
}

String _inicialesDesdeNombre(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) {
    return partes.first.substring(0, partes.first.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (partes[0][0] + partes[1][0]).toUpperCase();
}

/// Avatar de iniciales (tipo Slack/Gmail): color fijo derivado del nombre,
/// para cuando todavía no se ha subido un logo real.
Widget avatarIniciales(String nombre, {double radius = 24}) {
  return Container(
    width: radius * 2,
    height: radius * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: _colorDesdeNombre(nombre),
      border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
    ),
    alignment: Alignment.center,
    child: Text(
      _inicialesDesdeNombre(nombre),
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: radius * 0.7),
    ),
  );
}

/// Avatar circular reutilizable para despachos, contadores y negocios: si
/// hay un logo subido lo muestra; si no, y se pasó un [nombre], cae en un
/// avatar de iniciales (para que cada quien se distinga aunque no haya
/// subido su logo todavía); si tampoco hay nombre, cae en un ícono genérico.
Widget avatarConLogo({
  String? logoUrl,
  String? nombre,
  required IconData icono,
  double radius = 24,
  Color? color,
  Color? fondo,
}) {
  color ??= AppColors.primary;
  fondo ??= color.withOpacity(0.1);
  final tieneNombre = nombre != null && nombre.trim().isNotEmpty;
  final Widget fallback = tieneNombre
      ? avatarIniciales(nombre, radius: radius)
      : CircleAvatar(
          radius: radius,
          backgroundColor: fondo,
          child: Icon(icono, color: color, size: radius * 0.85),
        );

  if (logoUrl == null || logoUrl.isEmpty) return fallback;

  return ClipOval(
    child: Image.network(
      logoUrl,
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: fallback,
        );
      },
    ),
  );
}
