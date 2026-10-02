import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Los dos botones de "Exportar a PDF / Excel" de los reportes: tarjetas
/// lado a lado debajo del resumen (antes eran dos enlaces chicos en la
/// esquina derecha), con los colores del tema; solo el ícono lleva el
/// color de cada formato.
class BotonesExportar extends StatelessWidget {
  final VoidCallback? onPdf;
  final VoidCallback? onExcel;
  // Colores de la pantalla (el panel del contador usa su propio tema claro).
  final Color? fondo;
  final Color? borde;
  final Color? texto;
  final Color? tenue;

  const BotonesExportar({super.key, required this.onPdf, required this.onExcel, this.fondo, this.borde, this.texto, this.tenue});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Row(
        children: [
          Expanded(child: _boton(Icons.picture_as_pdf_rounded, "PDF", "Imprimir o enviar", const Color(0xFFE11D48), onPdf)),
          const SizedBox(width: 10),
          Expanded(child: _boton(Icons.grid_on_rounded, "Excel", "Editar y analizar", const Color(0xFF16A34A), onExcel)),
        ],
      ),
    );
  }

  Widget _boton(IconData icono, String titulo, String detalle, Color color, VoidCallback? onTap) {
    final activo = onTap != null;
    return Opacity(
      opacity: activo ? 1 : 0.45,
      child: Material(
        color: fondo ?? AppColors.surfaceSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borde ?? AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: color.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icono, size: 19, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: texto ?? AppColors.textStrong)),
                      Text(detalle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: tenue ?? AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
