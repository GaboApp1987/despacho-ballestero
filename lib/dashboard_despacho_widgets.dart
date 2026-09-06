import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'formato.dart';
import 'widgets/staggered_entrance.dart';

/// Widgets compartidos del dashboard que consume /socios/dashboard-despacho/:
/// el endpoint ya viene filtrado por permisos (un contador solo ve su propia
/// cartera, el dueño del despacho ve la de todos sus contadores), así que la
/// misma UI sirve para ambos — sólo cambia si se muestra o no la tarjeta de
/// "Contadores" (no tiene sentido para un contador viendo su propio perfil).

/// Botón de acción moderno para AppBars con fondo de color (círculo
/// translúcido tipo "vidrio esmerilado" en vez del IconButton plano).
Widget accionAppBar({
  required IconData icono,
  required String tooltip,
  required VoidCallback onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icono, color: Colors.white, size: 20),
          ),
        ),
      ),
    ),
  );
}

Widget buildDashboardHeader(
  Map<String, dynamic> d, {
  required Future<void> Function(int negocioId) onAbrirNegocio,
  bool mostrarContadores = true,
}) {
  final cantContadores = (d['cantidad_contadores'] as num?)?.toInt() ?? 0;
  final cantNegocios = (d['cantidad_negocios'] as num?)?.toInt() ?? 0;
  final facturasMes = (d['facturas_mes_actual'] as num?)?.toInt() ?? 0;
  final porEstado = (d['negocios_por_estado_suscripcion'] as Map?) ?? {};
  final activos = (porEstado['activo'] as num?)?.toInt() ?? 0;
  final suspendidos = (porEstado['suspendido'] as num?)?.toInt() ?? 0;
  final morosos = (porEstado['moroso'] as num?)?.toInt() ?? 0;

  return Container(
    width: double.infinity,
    color: AppColors.surface,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (mostrarContadores) ...[
              Expanded(
                child: StaggeredEntrance(
                  index: 0,
                  child: _statCardDespacho("Contadores", "$cantContadores", Icons.badge_outlined, AppColors.primary),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: StaggeredEntrance(
                index: mostrarContadores ? 1 : 0,
                child: _statCardDespacho("Clientes", "$cantNegocios", Icons.business_center_outlined, Colors.teal),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StaggeredEntrance(
                index: mostrarContadores ? 2 : 1,
                child: _statCardDespacho("Facturas este mes", "$facturasMes", Icons.receipt_long_outlined, Colors.deepPurple),
              ),
            ),
          ],
        ),
        if (suspendidos > 0 || morosos > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badgeEstado("$activos activo(s)", Colors.green),
              if (suspendidos > 0) _badgeEstado("$suspendidos suspendido(s)", Colors.red),
              if (morosos > 0) _badgeEstado("$morosos moroso(s)", Colors.amber.shade800),
            ],
          ),
        ],
        ..._buildSeccionAlertas((d['alertas_suscripcion'] as List?) ?? [], onAbrirNegocio),
        if (mostrarContadores) ..._buildSeccionCarga((d['carga_por_contador'] as List?) ?? []),
        ..._buildSeccionActividad(
          (d['facturas_recientes'] as List?) ?? [],
          (d['clientes_recientes'] as List?) ?? [],
          mostrarContador: mostrarContadores,
        ),
      ],
    ),
  );
}

List<Widget> _buildSeccionAlertas(List alertas, Future<void> Function(int) onAbrirNegocio) {
  if (alertas.isEmpty) return [];
  return [
    const SizedBox(height: 18),
    const Divider(),
    const SizedBox(height: 6),
    Text("Alertas de Suscripción", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
    const SizedBox(height: 8),
    ...alertas.map((a) {
      final estado = a['estado'] as String;
      final esCritico = estado == 'suspendido' || estado == 'moroso';
      final color = esCritico ? Colors.red : Colors.amber.shade800;
      final etiquetaEstado = estado == 'suspendido' ? 'Suspendido' : (estado == 'moroso' ? 'Moroso' : 'Por vencer');
      final fecha = a['fecha_proximo_cobro'];
      return InkWell(
        onTap: () => onAbrirNegocio(a['negocio_id']),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Icon(esCritico ? Icons.error_outline : Icons.schedule, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a['negocio_nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(
                      "${a['contador_nombre'] ?? 'Sin contador'}${fecha != null ? ' · Próximo cobro: $fecha' : ''}",
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(etiquetaEstado, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        ),
      );
    }),
  ];
}

List<Widget> _buildSeccionCarga(List carga) {
  if (carga.length < 2) return []; // con un solo contador no hay nada que comparar
  final maxNegocios = carga.fold<int>(
    1,
    (m, c) => (c['cantidad_negocios'] as num).toInt() > m ? (c['cantidad_negocios'] as num).toInt() : m,
  );
  return [
    const SizedBox(height: 18),
    const Divider(),
    const SizedBox(height: 6),
    Text("Carga de Trabajo por Contador", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
    const SizedBox(height: 10),
    ...carga.map((c) {
      final cantidad = (c['cantidad_negocios'] as num).toInt();
      final facturasMes = (c['facturas_mes'] as num).toInt();
      final proporcion = cantidad / maxNegocios;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c['nombre'] ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "$cantidad cliente(s) · $facturasMes factura(s) este mes",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: proporcion.clamp(0.02, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ),
      );
    }),
  ];
}

List<Widget> _buildSeccionActividad(List facturas, List clientes, {bool mostrarContador = true}) {
  if (facturas.isEmpty && clientes.isEmpty) return [];
  return [
    const SizedBox(height: 18),
    const Divider(),
    const SizedBox(height: 6),
    Text("Actividad Reciente", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
    const SizedBox(height: 8),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Últimas facturas", style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (facturas.isEmpty)
                Text("Sin facturas recientes", style: TextStyle(fontSize: 12, color: Colors.grey[400]))
              else
                ...facturas.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "${f['negocio_nombre']} · ${f['cliente']}",
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            formatearColones(double.tryParse(f['total'].toString()) ?? 0, decimales: 0),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Clientes nuevos", style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (clientes.isEmpty)
                Text("Sin clientes nuevos", style: TextStyle(fontSize: 12, color: Colors.grey[400]))
              else
                ...clientes.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        mostrarContador ? "${c['negocio_nombre']} · ${c['contador_nombre'] ?? 'Sin contador'}" : "${c['negocio_nombre']}",
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
            ],
          ),
        ),
      ],
    ),
  ];
}

Widget _statCardDespacho(String titulo, String valor, IconData icono, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titulo, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            Icon(icono, color: color, size: 16),
          ],
        ),
        const SizedBox(height: 6),
        Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    ),
  );
}

Widget _badgeEstado(String texto, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
    child: Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}
