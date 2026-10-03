import 'package:flutter/material.dart';

import '../plan.dart';
import '../theme/app_theme.dart';

String _colones(double v) {
  final entero = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buf.write('.');
    buf.write(entero[i]);
  }
  return "₡$buf";
}

/// Tarjeta de un plan de negocio: precio, para quién es, límites (documentos,
/// usuarios, consultas de IA) y lo que incluye. `pie` es la acción (botón de
/// cambiar, radio de selección...); `seleccionada` resalta el borde.
class TarjetaPlanNegocio extends StatelessWidget {
  final Plan plan;
  final Widget? pie;
  final bool seleccionada;
  final bool actual;
  final VoidCallback? onTap;
  final bool compacta;

  const TarjetaPlanNegocio({
    super.key,
    required this.plan,
    this.pie,
    this.seleccionada = false,
    this.actual = false,
    this.onTap,
    this.compacta = false,
  });

  @override
  Widget build(BuildContext context) {
    final resaltar = seleccionada || plan.destacado;
    final colorBorde = seleccionada ? AppColors.primary : (plan.destacado ? AppColors.primary.withOpacity(0.45) : AppColors.border);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorBorde, width: resaltar ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(plan.nombre, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                ),
                if (actual) _chip("Tu plan", Colors.green.shade700)
                else if (plan.destacado) _chip("★ Más popular", AppColors.primary),
                if (seleccionada) ...[const SizedBox(width: 6), Icon(Icons.check_circle, color: AppColors.primary, size: 22)],
              ]),
              if (plan.paraQuien.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(plan.paraQuien, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ],
              const SizedBox(height: 10),
              if (plan.precioMensual != null)
                Text.rich(TextSpan(children: [
                  TextSpan(
                    text: _colones(plan.precioMensual!),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textStrong),
                  ),
                  TextSpan(text: " / ${plan.unidadPeriodo}", style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ])),
              const SizedBox(height: 10),
              _limite(Icons.receipt_long_outlined, plan.textoDocumentos),
              _limite(Icons.group_outlined, plan.textoUsuarios),
              _limite(Icons.auto_awesome_outlined, plan.textoConsultasIa),
              if (plan.precioDocumentoExtra != null)
                _nota("${_colones(plan.precioDocumentoExtra!)} por cada documento extra; nunca se te bloquea la facturación."),
              if (plan.recargaDocumentos != null && plan.recargaPrecio != null)
                _nota("Recargas de ${plan.recargaDocumentos} documentos a ${_colones(plan.recargaPrecio!)}."),
              if (!compacta && plan.incluye.isNotEmpty) ...[
                const SizedBox(height: 8),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 8),
                for (final linea in plan.incluye)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Expanded(child: Text(linea, style: TextStyle(fontSize: 13, color: AppColors.textStrong))),
                    ]),
                  ),
              ],
              if (pie != null) ...[const SizedBox(height: 12), pie!],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _limite(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icono, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textStrong))),
        ]),
      );

  Widget _nota(String texto) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(texto, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
}

/// Barras de uso del plan del negocio (ver uso_plan en NegocioSerializer).
class UsoPlanNegocio extends StatelessWidget {
  final Map<String, dynamic> uso;
  /// Si viene, muestra un botón por cada recarga que vende el plan.
  final void Function(Map<String, dynamic> paquete)? onComprarRecarga;

  const UsoPlanNegocio({super.key, required this.uso, this.onComprarRecarga});

  @override
  Widget build(BuildContext context) {
    final anual = uso['periodicidad'] == 'anual';
    final extras = (uso['documentos_extra'] as num?)?.toInt() ?? 0;
    final paquetes = ((uso['paquetes_recarga'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Tu uso ${anual ? 'este año del plan' : 'este mes'}", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          const SizedBox(height: 12),
          _barra("Documentos", (uso['documentos_usados'] as num?)?.toInt() ?? 0, (uso['documentos_limite'] as num?)?.toInt()),
          if (extras > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                "$extras documento${extras == 1 ? '' : 's'} extra este mes (${_colones((uso['monto_documentos_extra'] as num).toDouble())})",
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ),
          _saldo((uso['saldo_documentos_recarga'] as num?)?.toInt() ?? 0, "documentos"),
          _barra("Usuarios", (uso['usuarios'] as num?)?.toInt() ?? 0, (uso['usuarios_limite'] as num?)?.toInt()),
          _barra("Consultas de IA este mes", (uso['consultas_ia'] as num?)?.toInt() ?? 0, (uso['consultas_ia_limite'] as num?)?.toInt()),
          _saldo((uso['saldo_consultas_ia_recarga'] as num?)?.toInt() ?? 0, "consultas de IA"),
          if (onComprarRecarga != null && paquetes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text("¿Necesitás más? Se suma a lo que te queda y no vence:", style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in paquetes)
                OutlinedButton.icon(
                  onPressed: () => onComprarRecarga!(p),
                  icon: Icon(p['tipo'] == 'ia' ? Icons.auto_awesome_outlined : Icons.receipt_long_outlined, size: 18),
                  label: Text("+${p['cantidad']} ${p['tipo'] == 'ia' ? 'consultas IA' : 'documentos'} · "
                      "${_colones((p['precio'] as num).toDouble())}"),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _saldo(int saldo, String que) {
    if (saldo <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(Icons.add_circle, size: 14, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Text("+$saldo $que de recargas", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
      ]),
    );
  }

  Widget _barra(String etiqueta, int usado, int? limite) {
    final proporcion = limite == null || limite == 0 ? 0.0 : (usado / limite).clamp(0.0, 1.0);
    final color = proporcion >= 0.9 ? Colors.red.shade700 : (proporcion >= 0.7 ? Colors.amber.shade800 : AppColors.primary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(etiqueta, style: TextStyle(fontSize: 13, color: AppColors.textMuted))),
          Text(limite == null ? "$usado · ilimitado" : "$usado de $limite",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
        ]),
        if (limite != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: proporcion, minHeight: 6, color: color, backgroundColor: AppColors.border),
          ),
        ],
      ]),
    );
  }
}
