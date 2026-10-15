import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Motivo del rechazo (o del error) que mandó Hacienda. Antes el texto iba
/// en negro sobre un rojo casi transparente: en el tema oscuro no se leía.
/// Acá los colores cambian con el tema y el texto usa el color fuerte.
class MotivoHacienda extends StatelessWidget {
  final String motivo;
  final bool esError;
  final bool compacto;
  const MotivoHacienda({super.key, required this.motivo, this.esError = false, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final oscuro = AppColors.isDark;
    final fondo = oscuro ? const Color(0xFF3A1419) : const Color(0xFFFEF2F2);
    final borde = oscuro ? const Color(0xFF8B2C35) : const Color(0xFFFCA5A5);
    final titulo = oscuro ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
    final texto = oscuro ? const Color(0xFFFDE8EA) : const Color(0xFF450A0A);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compacto ? 10 : 14),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borde),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error_outline, color: titulo, size: compacto ? 16 : 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              esError ? "Motivo del error" : "Motivo del rechazo de Hacienda",
              style: TextStyle(color: titulo, fontWeight: FontWeight.w800, fontSize: compacto ? 12.5 : 13.5),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: motivo));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Motivo copiado")));
            },
            style: TextButton.styleFrom(
              foregroundColor: titulo,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text("Copiar"),
          ),
        ]),
        const SizedBox(height: 6),
        SelectableText(motivo, style: TextStyle(fontSize: compacto ? 13 : 14, height: 1.35, color: texto)),
      ]),
    );
  }
}

/// El buzón de facturas de compra del negocio, bien visible y con botón
/// para copiarlo (tocar la dirección también la copia).
class TarjetaCorreoCompras extends StatelessWidget {
  final String cedula;
  const TarjetaCorreoCompras({super.key, required this.cedula});

  String get correo => "$cedula@facturas.equilibracr.com";

  void _copiar(BuildContext context) {
    Clipboard.setData(ClipboardData(text: correo));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copiado: $correo")));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text("Correo para facturas de compra",
                style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => _copiar(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              correo,
              style: TextStyle(color: AppColors.textStrong, fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: () => _copiar(context),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text("Copiar correo"),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          "Dale esta dirección a tus proveedores para que te manden ahí la factura electrónica de tus compras. "
          "Equilibra la recibe sola y la deja lista para revisar en Compras.",
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      ]),
    );
  }
}
