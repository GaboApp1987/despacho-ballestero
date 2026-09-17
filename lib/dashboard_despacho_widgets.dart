import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'formato.dart';
import 'widgets/staggered_entrance.dart';

/// Widgets compartidos del dashboard que consume /socios/dashboard-despacho/:
/// el endpoint ya viene filtrado por permisos (un contador solo ve su propia
/// cartera, el dueño del despacho ve la de todos sus contadores), así que la
/// misma UI sirve para ambos — sólo cambia si se muestra o no la tarjeta de
/// "Contadores" (no tiene sentido para un contador viendo su propio perfil).
///
/// Este bloque sigue el tema global (AppColors, oscuro por defecto) porque
/// así lo necesita la pantalla del despacho. La pantalla del contador tiene
/// su propia paleta clara y este bloque se veía "importado" de otro tema
/// (caja oscura sobre fondo blanco) -- buildDashboardHeader(esContador: true)
/// pisa esos dos colores acá antes de construir las secciones, sin tocar
/// AppColors ni afectar al despacho.
class _TemaDashboard {
  static Color fondo = AppColors.surface;
  static Color texto = AppColors.textStrong;
  // Acento cian de AppColors.primary es el mismo en claro y oscuro (pensado
  // para resaltar sobre fondo oscuro) -- en la paleta clara del contador se
  // ve pálido/verdoso y ajeno al azul (TemaContador.acento) que ya usan sus
  // otras pantallas (perfil, reportes), así que acá se pisa igual que fondo/texto.
  static Color acento = AppColors.primary;
}

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
  required BuildContext context,
  required Future<void> Function(int negocioId) onAbrirNegocio,
  bool mostrarContadores = true,
  bool esContador = false,
}) {
  _TemaDashboard.fondo = esContador ? const Color(0xFFF8FAFC) : AppColors.surface;
  _TemaDashboard.texto = esContador ? const Color(0xFF0F172A) : AppColors.textStrong;
  _TemaDashboard.acento = esContador ? TemaContador.acento : AppColors.primary;

  final cantContadores = (d['cantidad_contadores'] as num?)?.toInt() ?? 0;
  final cantNegocios = (d['cantidad_negocios'] as num?)?.toInt() ?? 0;
  final facturasMes = (d['facturas_mes_actual'] as num?)?.toInt() ?? 0;
  final porEstado = (d['negocios_por_estado_suscripcion'] as Map?) ?? {};
  final activos = (porEstado['activo'] as num?)?.toInt() ?? 0;
  final suspendidos = (porEstado['suspendido'] as num?)?.toInt() ?? 0;
  final morosos = (porEstado['moroso'] as num?)?.toInt() ?? 0;

  return Container(
    width: double.infinity,
    color: _TemaDashboard.fondo,
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
        ..._buildRecordatorioFiscal(d['recordatorio_fiscal'] as Map?),
        ..._buildSeccionConVerTodas(
          context: context,
          titulo: "Alertas de Suscripción",
          items: (d['alertas_suscripcion'] as List?) ?? [],
          constructor: (lista) => _buildSeccionAlertas(lista, onAbrirNegocio),
        ),
        ..._buildSeccionConVerTodas(
          context: context,
          titulo: "Pendientes en Hacienda",
          items: (d['alertas_hacienda'] as List?) ?? [],
          constructor: (lista) => _buildSeccionAlertasHacienda(lista, onAbrirNegocio),
        ),
        ..._buildSeccionConVerTodas(
          context: context,
          titulo: "Cuentas por Cobrar Vencidas",
          items: (d['cuentas_por_cobrar_vencidas'] as List?) ?? [],
          constructor: (lista) => _buildSeccionCuentasVencidas(
            lista, (d['total_cuentas_por_cobrar_vencidas'] as num?) ?? 0, onAbrirNegocio,
          ),
        ),
        ..._buildSeccionConVerTodas(
          context: context,
          titulo: "Certificados por Vencer",
          items: (d['certificados_por_vencer'] as List?) ?? [],
          constructor: (lista) => _buildSeccionCertificados(lista, onAbrirNegocio),
        ),
        ..._buildSeccionConVerTodas(
          context: context,
          titulo: "Clientes sin Actividad Reciente",
          items: (d['clientes_inactivos'] as List?) ?? [],
          constructor: (lista) => _buildSeccionClientesInactivos(lista, onAbrirNegocio),
        ),
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
    Text("Alertas de Suscripción", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _TemaDashboard.texto)),
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
                    Text(a['negocio_nombre'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _TemaDashboard.texto)),
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

List<Widget> _buildRecordatorioFiscal(Map? r) {
  if (r == null) return [];
  final diasIva = (r['dias_para_iva'] as num?)?.toInt();
  final diasRenta = (r['dias_para_renta'] as num?)?.toInt();
  if (diasIva == null || diasRenta == null) return [];
  Color colorPara(int dias) => dias <= 5 ? Colors.red : (dias <= 10 ? Colors.amber.shade800 : _TemaDashboard.acento);
  return [
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: _tarjetaFiscal(
            "IVA (D-104)", r['proxima_iva']?.toString() ?? '', diasIva, colorPara(diasIva),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tarjetaFiscal(
            "Renta (D-101)", r['proxima_renta']?.toString() ?? '', diasRenta, colorPara(diasRenta),
          ),
        ),
      ],
    ),
  ];
}

Widget _tarjetaFiscal(String titulo, String fecha, int dias, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.15)),
    ),
    child: Row(
      children: [
        Icon(Icons.event_note_outlined, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold)),
              Text(
                dias == 0 ? "Vence hoy ($fecha)" : (dias < 0 ? "Venció ($fecha)" : "Vence en $dias día(s) ($fecha)"),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

List<Widget> _buildSeccionAlertasHacienda(List alertas, Future<void> Function(int) onAbrirNegocio) {
  if (alertas.isEmpty) return [];
  return [
    const SizedBox(height: 18),
    const Divider(),
    const SizedBox(height: 6),
    Text("Pendientes en Hacienda", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _TemaDashboard.texto)),
    const SizedBox(height: 8),
    ...alertas.map((a) {
      final estado = a['estado'] as String?;
      final esRechazo = estado == '4' || estado == '5';
      final color = esRechazo ? Colors.red : Colors.amber.shade800;
      return InkWell(
        onTap: () => onAbrirNegocio(a['negocio_id']),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Icon(esRechazo ? Icons.error_outline : Icons.hourglass_top_outlined, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${a['negocio_nombre'] ?? ''} · ${a['tipo'] ?? ''} ${a['consecutivo'] ?? ''}",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _TemaDashboard.texto),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(a['estado_texto'] ?? '', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
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

List<Widget> _buildSeccionCuentasVencidas(List cuentas, num total, Future<void> Function(int) onAbrirNegocio) {
  if (cuentas.isEmpty) return [];
  return [
    const SizedBox(height: 18),
    const Divider(),
    const SizedBox(height: 6),
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("Cuentas por Cobrar Vencidas", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _TemaDashboard.texto)),
        Text(formatearColones(total, decimales: 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
      ],
    ),
    const SizedBox(height: 8),
    ...cuentas.map((c) {
      final dias = (c['dias_vencida'] as num?)?.toInt() ?? 0;
      return InkWell(
        onTap: () => onAbrirNegocio(c['negocio_id']),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.money_off_outlined, color: Colors.red, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${c['negocio_nombre'] ?? ''} · ${c['cliente'] ?? ''}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _TemaDashboard.texto), overflow: TextOverflow.ellipsis),
                    Text("Vencida hace $dias día(s)", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ),
              Text(
                formatearColones(double.tryParse(c['total'].toString()) ?? 0, decimales: 0),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
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

List<Widget> _buildSeccionCertificados(List certs, Future<void> Function(int) onAbrirNegocio) {
  if (certs.isEmpty) return [];
  return [
    const SizedBox(height: 18),
    const Divider(),
    const SizedBox(height: 6),
    Text("Certificados por Vencer", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _TemaDashboard.texto)),
    const SizedBox(height: 8),
    ...certs.map((c) {
      final dias = (c['dias_restantes'] as num?)?.toInt() ?? 0;
      final color = dias <= 15 ? Colors.red : Colors.amber.shade800;
      return InkWell(
        onTap: () => onAbrirNegocio(c['negocio_id']),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Icon(Icons.badge_outlined, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(c['negocio_nombre'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _TemaDashboard.texto), overflow: TextOverflow.ellipsis),
              ),
              Text(
                dias < 0 ? "Vencido" : "Vence en $dias día(s)",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
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

List<Widget> _buildSeccionClientesInactivos(List clientes, Future<void> Function(int) onAbrirNegocio) {
  if (clientes.isEmpty) return [];
  return [
    const SizedBox(height: 18),
    const Divider(),
    const SizedBox(height: 6),
    Text("Clientes sin Actividad Reciente", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _TemaDashboard.texto)),
    const SizedBox(height: 8),
    ...clientes.map((c) {
      final dias = c['dias_sin_facturar'] as num?;
      return InkWell(
        onTap: () => onAbrirNegocio(c['negocio_id']),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Icon(Icons.pause_circle_outline, color: Colors.grey[600], size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(c['negocio_nombre'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _TemaDashboard.texto), overflow: TextOverflow.ellipsis),
              ),
              Text(
                dias == null ? "Sin facturas" : "Sin facturar hace ${dias.toInt()} día(s)",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
    Text("Carga de Trabajo por Contador", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _TemaDashboard.texto)),
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _TemaDashboard.texto),
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
    Text("Actividad Reciente", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _TemaDashboard.texto)),
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
                              style: TextStyle(fontSize: 12, color: _TemaDashboard.texto),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            formatearColones(double.tryParse(f['total'].toString()) ?? 0, decimales: 0),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _TemaDashboard.texto),
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
                        style: TextStyle(fontSize: 12, color: _TemaDashboard.texto),
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

/// Recorta una sección a los primeros [previewCount] ítems (el dashboard
/// venía mostrando TODO de una, hasta 20-100 filas -- una sola sección como
/// "Pendientes en Hacienda" tapaba el resto de la pantalla) y agrega un
/// "Ver todas (N)" que lleva a SeccionDashboardScreen con la lista completa,
/// cuando hay más de las que se muestran acá.
List<Widget> _buildSeccionConVerTodas({
  required BuildContext context,
  required String titulo,
  required List items,
  required List<Widget> Function(List) constructor,
  int previewCount = 3,
}) {
  if (items.isEmpty) return [];
  final widgets = constructor(items.take(previewCount).toList());
  if (items.length > previewCount) {
    widgets.add(
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: _TemaDashboard.acento),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SeccionDashboardScreen(titulo: titulo, contenido: constructor(items)),
            ),
          ),
          child: Text("Ver todas (${items.length})", style: const TextStyle(fontSize: 12.5)),
        ),
      ),
    );
  }
  return widgets;
}

/// Pantalla genérica para mostrar una sección del dashboard completa (sin
/// recortar) -- la usan tanto los botones "Ver todas" como el
/// DashboardDrawer, ambos le pasan el mismo tipo de contenido que ya arman
/// las funciones _buildSeccionX de arriba.
class SeccionDashboardScreen extends StatelessWidget {
  final String titulo;
  final List<Widget> contenido;
  const SeccionDashboardScreen({super.key, required this.titulo, required this.contenido});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: contenido),
        ),
      ),
    );
  }
}

/// Menú lateral del dashboard (despacho y contador): cada sección del
/// dashboard es una entrada acá, con la cantidad de pendientes como badge,
/// para no depender de bajar toda la pantalla o de tocar "Ver todas" en
/// cada una -- a medida que se agreguen más funciones al dashboard, entran
/// acá en vez de seguir apilando secciones en la pantalla principal.
class DashboardDrawer extends StatelessWidget {
  final Future<Map<String, dynamic>> dashboardFuture;
  final Future<void> Function(int negocioId) onAbrirNegocio;
  final bool mostrarContadores;
  final bool esContador;
  const DashboardDrawer({
    super.key,
    required this.dashboardFuture,
    required this.onAbrirNegocio,
    this.mostrarContadores = true,
    this.esContador = false,
  });

  Widget _item(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required List items,
    required List<Widget> Function(List) constructor,
  }) {
    // Mismo motivo que _TemaDashboard.acento en buildDashboardHeader: el
    // cian de AppColors.primary es el del tema oscuro, no el azul que usa
    // la paleta clara del contador (TemaContador.acento).
    final acento = esContador ? TemaContador.acento : AppColors.primary;
    return ListTile(
      leading: Icon(icono, color: AppColors.textMuted),
      title: Text(titulo, style: const TextStyle(fontSize: 14)),
      trailing: items.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: acento.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text("${items.length}", style: TextStyle(color: acento, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
      enabled: items.isNotEmpty,
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SeccionDashboardScreen(titulo: titulo, contenido: constructor(items))),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: dashboardFuture,
          builder: (context, snapshot) {
            final d = snapshot.data ?? {};
            if (snapshot.connectionState == ConnectionState.waiting || d.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final alertasSuscripcion = (d['alertas_suscripcion'] as List?) ?? [];
            final alertasHacienda = (d['alertas_hacienda'] as List?) ?? [];
            final cuentasVencidas = (d['cuentas_por_cobrar_vencidas'] as List?) ?? [];
            final certificados = (d['certificados_por_vencer'] as List?) ?? [];
            final clientesInactivos = (d['clientes_inactivos'] as List?) ?? [];
            final cargaContador = (d['carga_por_contador'] as List?) ?? [];
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(color: Color(0xFF4F46E5)),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      "Secciones del panel",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                _item(
                  context,
                  icono: Icons.error_outline,
                  titulo: "Alertas de Suscripción",
                  items: alertasSuscripcion,
                  constructor: (lista) => _buildSeccionAlertas(lista, onAbrirNegocio),
                ),
                _item(
                  context,
                  icono: Icons.receipt_long_outlined,
                  titulo: "Pendientes en Hacienda",
                  items: alertasHacienda,
                  constructor: (lista) => _buildSeccionAlertasHacienda(lista, onAbrirNegocio),
                ),
                _item(
                  context,
                  icono: Icons.money_off_outlined,
                  titulo: "Cuentas por Cobrar Vencidas",
                  items: cuentasVencidas,
                  constructor: (lista) => _buildSeccionCuentasVencidas(
                    lista, (d['total_cuentas_por_cobrar_vencidas'] as num?) ?? 0, onAbrirNegocio,
                  ),
                ),
                _item(
                  context,
                  icono: Icons.badge_outlined,
                  titulo: "Certificados por Vencer",
                  items: certificados,
                  constructor: (lista) => _buildSeccionCertificados(lista, onAbrirNegocio),
                ),
                _item(
                  context,
                  icono: Icons.pause_circle_outline,
                  titulo: "Clientes sin Actividad",
                  items: clientesInactivos,
                  constructor: (lista) => _buildSeccionClientesInactivos(lista, onAbrirNegocio),
                ),
                if (mostrarContadores)
                  _item(
                    context,
                    icono: Icons.bar_chart_outlined,
                    titulo: "Carga por Contador",
                    items: cargaContador,
                    constructor: (lista) => _buildSeccionCarga(lista),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
