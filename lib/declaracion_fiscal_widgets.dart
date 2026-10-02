import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'formato.dart';

/// Widgets compartidos para pintar las Declaraciones de IVA y Renta a
/// partir de la respuesta cruda de /facturas/declaracion-iva/ y
/// /facturas/declaracion-renta/. Los usan tanto el Dashboard del negocio
/// (detalle_negocio.dart) como el resumen fiscal que ve el contador al
/// entrar a un cliente (resumen_fiscal_screen.dart), para que ambas vistas
/// muestren siempre exactamente los mismos números y el mismo detalle.

double numDeDeclaracion(Map<String, dynamic> d, String llave) => double.tryParse(d[llave]?.toString() ?? '') ?? 0.0;

const Map<String, String> categoriasGastoLabel = {
  'planilla': 'Planilla y CCSS',
  'alquiler': 'Alquiler',
  'servicios': 'Servicios públicos',
  'honorarios': 'Honorarios profesionales',
  'mantenimiento': 'Mantenimiento y reparaciones',
  'publicidad': 'Publicidad y mercadeo',
  'transporte': 'Transporte y viáticos',
  'seguros': 'Seguros',
  'depreciacion': 'Depreciación de activos',
  'financieros': 'Gastos financieros e intereses',
  'impuestos_municipales': 'Impuestos y patentes municipales',
  'otros': 'Otros gastos',
};

// Colores de las series: se leen bien en el tema claro y en el oscuro.
const Color _cVentas = Color(0xFF3B82F6);
const Color _cCompras = Color(0xFF14B8A6);
const Color _cCostos = Color(0xFFF59E0B);
const Color _cGastos = Color(0xFF8B5CF6);
const Color _cRenta = Color(0xFF10B981);
const Color _cPagar = Color(0xFFEF4444);

const _mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _mesesLargos = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String _fechaCorta(DateTime f) => "${f.day} ${_mesesCortos[f.month - 1]} ${f.year}";

Widget filaDeclaracion(String etiqueta, double valor, {bool resaltado = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(etiqueta, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Text(
          formatearColones(valor),
          style: TextStyle(
            fontSize: resaltado ? 16 : 14,
            fontWeight: resaltado ? FontWeight.bold : FontWeight.w500,
            color: AppColors.textStrong,
          ),
        ),
      ],
    ),
  );
}

Widget buildDeclaracionIva(Map<String, dynamic> d) => _DeclaracionIvaCard(d: d);

Widget buildDeclaracionRenta(Map<String, dynamic> d) => _DeclaracionRentaCard(d: d);

// ============================================================ piezas comunes

BoxDecoration _decoracionTarjeta() => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 6))],
    );

/// Monto que "cuenta" desde 0 hasta [valor] al aparecer.
class _MontoAnimado extends StatelessWidget {
  final double valor;
  final TextStyle estilo;
  final int decimales;
  const _MontoAnimado(this.valor, {required this.estilo, this.decimales = 2});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: valor),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(formatearColones(v, decimales: decimales), style: estilo),
      );
}

/// Barra horizontal que crece hasta [fraccion] (0..1) al aparecer.
class _BarraAnimada extends StatelessWidget {
  final double fraccion;
  final Color color;
  final double alto;
  const _BarraAnimada({required this.fraccion, required this.color, this.alto = 10});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(alto),
        child: Container(
          height: alto,
          color: AppColors.surfaceSubtle,
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraccion.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) => FractionallySizedBox(
              widthFactor: f,
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(alto))),
            ),
          ),
        ),
      );
}

/// Chip con ícono: plazos, comparaciones, conteos.
Widget _chip(IconData icono, String texto, Color color, {bool relleno = true}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: relleno ? color.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(relleno ? 0.0 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(child: Text(texto, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );

/// Plazo de presentación: color según cuánto falta.
Widget _chipPlazo(DateTime vence, {required DateTime finPeriodo, required String enCurso}) {
  final hoy = DateUtils.dateOnly(DateTime.now());
  if (hoy.isBefore(DateUtils.dateOnly(finPeriodo).add(const Duration(days: 1)))) {
    return _chip(Icons.hourglass_top_rounded, enCurso, AppColors.textMuted, relleno: false);
  }
  final dias = DateUtils.dateOnly(vence).difference(hoy).inDays;
  if (dias < 0) return _chip(Icons.event_available_rounded, "Plazo: ${_fechaCorta(vence)}", AppColors.textMuted, relleno: false);
  final color = dias <= 5 ? _cPagar : (dias <= 15 ? _cCostos : _cRenta);
  final falta = dias == 0 ? "vence hoy" : "faltan $dias día${dias == 1 ? '' : 's'}";
  final fecha = vence.year == hoy.year ? "${vence.day} ${_mesesCortos[vence.month - 1]}" : _fechaCorta(vence);
  return _chip(Icons.event_rounded, "Vence $fecha · $falta", color);
}

/// Sección que se abre y cierra (detalle por tarifa, por categoría...).
class _Desplegable extends StatefulWidget {
  final String titulo;
  final IconData icono;
  final Widget child;
  const _Desplegable({required this.titulo, required this.icono, required this.child});

  @override
  State<_Desplegable> createState() => _DesplegableState();
}

class _DesplegableState extends State<_Desplegable> {
  bool _abierto = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _abierto = !_abierto),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Icon(widget.icono, size: 17, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.titulo, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textStrong))),
                  AnimatedRotation(
                    turns: _abierto ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _abierto ? Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: widget.child) : const SizedBox(width: double.infinity),
          ),
        ],
      );
}

/// Fila "etiqueta ······ monto" con barra proporcional abajo.
Widget _filaConBarra(String etiqueta, double valor, double maximo, Color color, {String? extra}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: Text(etiqueta, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text.rich(TextSpan(children: [
                    if (extra != null) TextSpan(text: "$extra   ", style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    TextSpan(text: formatearColones(valor, decimales: 0), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                  ])),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _BarraAnimada(fraccion: maximo > 0 ? valor / maximo : 0, color: color, alto: 6),
        ],
      ),
    );

Widget _nota(String texto) => Text(
      texto,
      style: TextStyle(color: AppColors.textMuted.withOpacity(0.8), fontSize: 10.5, fontStyle: FontStyle.italic),
    );

Widget _aviso(String texto) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _cCostos.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: _cCostos),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(color: AppColors.textStrong, fontSize: 11.5))),
        ],
      ),
    );

// ============================================================ IVA (D-104)

class _DeclaracionIvaCard extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DeclaracionIvaCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final ventasGravadas = numDeDeclaracion(d, 'ventas_gravadas');
    final debitoFiscal = numDeDeclaracion(d, 'debito_fiscal');
    final comprasTotales = numDeDeclaracion(d, 'compras_totales');
    final creditoFiscal = numDeDeclaracion(d, 'credito_fiscal');
    final saldoIva = numDeDeclaracion(d, 'saldo_iva');
    final aPagar = d['a_pagar'] == true;
    final lineasSinImpuesto = (d['lineas_compra_sin_impuesto'] as num?)?.toInt() ?? 0;
    final cantFacturas = (d['cantidad_facturas'] as num?)?.toInt() ?? 0;
    final cantNotas = (d['cantidad_notas_credito'] as num?)?.toInt() ?? 0;
    final cantCompras = (d['cantidad_compras'] as num?)?.toInt() ?? 0;
    final debitoPorTarifa = (d['debito_por_tarifa'] as List?) ?? [];
    final creditoPorTarifa = (d['credito_por_tarifa'] as List?) ?? [];

    final sinSaldo = saldoIva.abs() < 0.01;
    final colorSaldo = sinSaldo ? AppColors.textMuted : (aPagar ? _cPagar : _cRenta);
    final etiquetaSaldo = sinSaldo ? "Sin saldo de IVA" : (aPagar ? "IVA a pagar" : "IVA a favor");

    // Periodo y plazo: el D-104 del mes se presenta hasta el 15 del mes
    // siguiente (solo cuando el periodo es un mes calendario).
    final periodo = d['periodo'] is Map ? d['periodo'] as Map : const {};
    final inicio = DateTime.tryParse('${periodo['fecha_inicio'] ?? ''}');
    final fin = DateTime.tryParse('${periodo['fecha_fin'] ?? ''}');
    final esUnMes = inicio != null && fin != null && inicio.year == fin.year && inicio.month == fin.month;

    final maximo = math.max(debitoFiscal, creditoFiscal);
    final cobertura = debitoFiscal > 0 ? (creditoFiscal / debitoFiscal * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _decoracionTarjeta(),
      child: LayoutBuilder(builder: (context, c) {
        final angosto = c.maxWidth < 560;

        final heroe = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorSaldo.withOpacity(0.16), colorSaldo.withOpacity(0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorSaldo.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(sinSaldo ? Icons.check_circle_outline : (aPagar ? Icons.north_east_rounded : Icons.south_west_rounded), size: 18, color: colorSaldo),
                  const SizedBox(width: 6),
                  Text(etiquetaSaldo.toUpperCase(), style: TextStyle(color: colorSaldo, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 0.6)),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _MontoAnimado(saldoIva.abs(), estilo: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w800, fontSize: 30)),
              ),
              const SizedBox(height: 6),
              Text(
                sinSaldo
                    ? "El IVA cobrado y el pagado en compras se compensan."
                    : (aPagar
                        ? "Cobraste ${formatearColones(debitoFiscal, decimales: 0)} de IVA y tus compras te dan ${formatearColones(creditoFiscal, decimales: 0)} de crédito."
                        : "Pagaste más IVA en compras del que cobraste: el saldo se acumula para el próximo periodo."),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        );

        final comparacion = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filaConBarra("IVA cobrado (ventas)", debitoFiscal, maximo, _cVentas),
            _filaConBarra("IVA pagado (compras)", creditoFiscal, maximo, _cCompras),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(child: _miniDato("Ventas gravadas", ventasGravadas)),
                const SizedBox(width: 10),
                Expanded(child: _miniDato("Compras netas", comprasTotales)),
              ],
            ),
            if (debitoFiscal > 0) ...[
              const SizedBox(height: 10),
              Text(
                "Tus compras cubren el ${cobertura.toStringAsFixed(0)}% del IVA que cobraste.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ],
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (esUnMes)
                  _chip(Icons.calendar_month_rounded, "${_mesesLargos[inicio.month - 1][0].toUpperCase()}${_mesesLargos[inicio.month - 1].substring(1)} ${inicio.year}", AppColors.primary)
                else if (inicio != null && fin != null)
                  _chip(Icons.date_range_rounded, "${_fechaCorta(inicio)} – ${_fechaCorta(fin)}", AppColors.primary),
                if (esUnMes)
                  _chipPlazo(
                    DateTime(fin.year, fin.month + 1, 15),
                    finPeriodo: fin,
                    enCurso: "Mes en curso · se declara del 1 al 15 ${_mesesCortos[fin.month % 12]}",
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (angosto) ...[
              heroe,
              const SizedBox(height: 18),
              comparacion,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: heroe),
                  const SizedBox(width: 22),
                  Expanded(flex: 6, child: comparacion),
                ],
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(Icons.receipt_long_outlined, "$cantFacturas factura${cantFacturas == 1 ? '' : 's'}", AppColors.textMuted, relleno: false),
                _chip(Icons.undo_rounded, "$cantNotas nota${cantNotas == 1 ? '' : 's'} de crédito", AppColors.textMuted, relleno: false),
                _chip(Icons.shopping_bag_outlined, "$cantCompras compra${cantCompras == 1 ? '' : 's'}", AppColors.textMuted, relleno: false),
              ],
            ),
            if (lineasSinImpuesto > 0) ...[
              const SizedBox(height: 12),
              _aviso("$lineasSinImpuesto línea(s) de compra son de productos sin impuesto asignado: no se incluyeron en el crédito fiscal. Asignales una tarifa en Productos para un cálculo más exacto."),
            ],
            if (debitoPorTarifa.isNotEmpty || creditoPorTarifa.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(color: AppColors.border, height: 1),
              _Desplegable(
                titulo: "Detalle por tarifa de IVA",
                icono: Icons.percent_rounded,
                child: angosto
                    ? Column(children: [
                        _tablaPorTarifa("Ventas (débito)", debitoPorTarifa, _cVentas),
                        const SizedBox(height: 16),
                        _tablaPorTarifa("Compras (crédito)", creditoPorTarifa, _cCompras),
                      ])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _tablaPorTarifa("Ventas (débito)", debitoPorTarifa, _cVentas)),
                          const SizedBox(width: 24),
                          Expanded(child: _tablaPorTarifa("Compras (crédito)", creditoPorTarifa, _cCompras)),
                        ],
                      ),
              ),
            ],
            const SizedBox(height: 6),
            _nota("Cálculo de referencia para armar la declaración; verificalo antes de presentarlo ante Hacienda."),
          ],
        );
      }),
    );
  }
}

Widget _miniDato(String etiqueta, double valor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatearColones(valor, decimales: 0), style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ],
      ),
    );

Widget _tablaPorTarifa(String titulo, List tarifas, Color color) {
  final estiloTitulo = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textStrong);
  if (tarifas.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: estiloTitulo),
        const SizedBox(height: 6),
        Text("Sin líneas en el periodo", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }
  final filas = tarifas
      .map((t) => (
            tarifa: t['tarifa'].toString(),
            base: double.tryParse(t['base'].toString()) ?? 0.0,
            iva: double.tryParse(t['iva'].toString()) ?? 0.0,
          ))
      .toList();
  final totalBase = filas.fold(0.0, (s, f) => s + f.base);
  final totalIva = filas.fold(0.0, (s, f) => s + f.iva);
  final maxIva = filas.fold(0.0, (m, f) => math.max(m, f.iva));

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titulo, style: estiloTitulo),
      const SizedBox(height: 10),
      ...filas.map((f) => _filaConBarra(
            "Tarifa ${f.tarifa.replaceAll(RegExp(r'\.0+$'), '')}% · base ${formatearColones(f.base, decimales: 0)}",
            f.iva,
            maxIva,
            color,
          )),
      Row(
        children: [
          Text("Total", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                "base ${formatearColones(totalBase, decimales: 0)} · IVA ${formatearColones(totalIva, decimales: 0)}",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textStrong),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

// ============================================================ Renta (D-101)

class _DeclaracionRentaCard extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DeclaracionRentaCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final configurado = d['parametros_configurados'] == true;
    final ingresosBrutos = numDeDeclaracion(d, 'ingresos_brutos');
    final costoVentas = numDeDeclaracion(d, 'costo_ventas');
    final gastosDeducibles = numDeDeclaracion(d, 'gastos_deducibles');
    final gastosNoDeducibles = numDeDeclaracion(d, 'gastos_no_deducibles');
    final rentaLiquida = numDeDeclaracion(d, 'renta_liquida_gravable');
    final impuestoEstimado = numDeDeclaracion(d, 'impuesto_estimado');
    final tipoContribuyente = d['tipo_contribuyente'] == 'juridica' ? 'Persona jurídica' : 'Persona física con actividad lucrativa';
    final tarifaUnica = d['tarifa_unica_aplicada'] as String?;
    final gastosPorCategoria = (d['gastos_por_categoria'] as List?) ?? [];
    final desgloseTramos = (d['desglose_tramos'] as List?) ?? [];
    final mensual = (d['mensual'] as List?) ?? [];
    final anterior = d['anio_anterior'] is Map ? Map<String, dynamic>.from(d['anio_anterior'] as Map) : null;
    final periodoFiscal = (d['periodo_fiscal'] as num?)?.toInt() ?? DateTime.now().year;

    final utilidad = ingresosBrutos - costoVentas - gastosDeducibles;
    final hayPerdida = utilidad < 0;
    final tasaEfectiva = rentaLiquida > 0 ? impuestoEstimado / rentaLiquida * 100 : 0.0;
    final margen = ingresosBrutos > 0 ? utilidad / ingresosBrutos * 100 : 0.0;

    // Variación contra el año anterior (solo si hubo algo que comparar).
    Widget? chipVariacion(String que, double actual, double previo) {
      if (previo <= 0) return null;
      final pct = (actual - previo) / previo * 100;
      final sube = pct >= 0;
      return _chip(
        sube ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        "$que ${sube ? '+' : ''}${pct.toStringAsFixed(0)}% vs ${anterior?['periodo_fiscal'] ?? periodoFiscal - 1}",
        sube ? _cRenta : _cPagar,
      );
    }

    final varIngresos = anterior == null ? null : chipVariacion("Ingresos", ingresosBrutos, numDeDeclaracion(anterior, 'ingresos_brutos'));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _decoracionTarjeta(),
      child: LayoutBuilder(builder: (context, c) {
        final angosto = c.maxWidth < 560;

        final heroe = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_cGastos.withOpacity(0.16), _cGastos.withOpacity(0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cGastos.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_rounded, size: 18, color: _cGastos),
                  const SizedBox(width: 6),
                  Text("IMPUESTO ESTIMADO", style: TextStyle(color: _cGastos, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 0.6)),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _MontoAnimado(impuestoEstimado, estilo: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w800, fontSize: 30)),
              ),
              const SizedBox(height: 6),
              Text(
                hayPerdida
                    ? "Los costos y gastos superan los ingresos: no hay renta gravable este año."
                    : "Sobre una renta líquida de ${formatearColones(rentaLiquida, decimales: 0)}"
                        "${rentaLiquida > 0 ? ' · tasa efectiva ${tasaEfectiva.toStringAsFixed(1)}%' : ''}",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              if (tarifaUnica != null) ...[
                const SizedBox(height: 4),
                Text("Tarifa única $tarifaUnica% (los ingresos superan el límite de tramos)", style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ],
          ),
        );

        final flujo = _FlujoRenta(
          ingresos: ingresosBrutos,
          costos: costoVentas,
          gastos: gastosDeducibles,
          utilidad: utilidad,
          margen: margen,
          gastosNoDeducibles: gastosNoDeducibles,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(Icons.badge_outlined, tipoContribuyente, AppColors.primary),
                _chipPlazo(
                  DateTime(periodoFiscal + 1, 3, 15),
                  finPeriodo: DateTime(periodoFiscal, 12, 31),
                  enCurso: "Año en curso · vence 15 mar ${periodoFiscal + 1}",
                ),
                if (varIngresos != null) varIngresos,
                if (!configurado) _chip(Icons.warning_amber_rounded, "Sin tramos configurados para este periodo", _cPagar),
              ],
            ),
            const SizedBox(height: 16),
            if (angosto) ...[
              heroe,
              const SizedBox(height: 18),
              flujo,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: heroe),
                  const SizedBox(width: 22),
                  Expanded(flex: 6, child: flujo),
                ],
              ),
            if (mensual.any((m) => (double.tryParse('${m['ingresos']}') ?? 0) != 0)) ...[
              const SizedBox(height: 20),
              Text("Mes a mes", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textStrong)),
              const SizedBox(height: 10),
              _GraficoMensual(mensual: mensual, anio: periodoFiscal),
            ],
            if (gastosPorCategoria.isNotEmpty || desgloseTramos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(color: AppColors.border, height: 1),
            ],
            if (gastosPorCategoria.isNotEmpty)
              _Desplegable(
                titulo: "Gastos deducibles por categoría",
                icono: Icons.category_outlined,
                child: Builder(builder: (context) {
                  final filas = gastosPorCategoria
                      .map((g) => (
                            nombre: categoriasGastoLabel[g['categoria']] ?? g['categoria'].toString(),
                            total: double.tryParse(g['total'].toString()) ?? 0.0,
                          ))
                      .toList()
                    ..sort((a, b) => b.total.compareTo(a.total));
                  final maximo = filas.isEmpty ? 0.0 : filas.first.total;
                  final suma = filas.fold(0.0, (s, f) => s + f.total);
                  return Column(
                    children: filas
                        .map((f) => _filaConBarra(f.nombre, f.total, maximo, _cGastos,
                            extra: suma > 0 ? "${(f.total / suma * 100).toStringAsFixed(0)}%" : null))
                        .toList(),
                  );
                }),
              ),
            if (desgloseTramos.isNotEmpty)
              _Desplegable(
                titulo: "Cómo se calcula el impuesto (tramos)",
                icono: Icons.stacked_bar_chart_rounded,
                child: Builder(builder: (context) {
                  final maximo = desgloseTramos.fold(0.0, (m, t) => math.max(m, double.tryParse('${t['impuesto_tramo']}') ?? 0.0));
                  return Column(
                    children: desgloseTramos.map((t) {
                      final desde = double.tryParse(t['desde'].toString()) ?? 0.0;
                      final hasta = t['hasta'] != null ? double.tryParse(t['hasta'].toString()) : null;
                      final impuestoTramo = double.tryParse(t['impuesto_tramo'].toString()) ?? 0.0;
                      final rango = hasta != null
                          ? "${formatearColones(desde, decimales: 0)} – ${formatearColones(hasta, decimales: 0)}"
                          : "Más de ${formatearColones(desde, decimales: 0)}";
                      return _filaConBarra(rango, impuestoTramo, maximo, _cGastos, extra: "${t['porcentaje']}%");
                    }).toList(),
                  );
                }),
              ),
            const SizedBox(height: 6),
            _nota(
              "Cálculo de referencia: el costo de ventas se aproxima con las compras del año (no se costea inventario por unidad vendida) y no incluye depreciación fiscal detallada, pérdidas de periodos anteriores ni créditos personales (cónyuge/hijos). Verificalo con tu contador antes de presentar el D-101.",
            ),
          ],
        );
      }),
    );
  }
}

/// De los ingresos, cuánto se va en costos, en gastos y cuánto queda: una
/// barra apilada con su leyenda.
class _FlujoRenta extends StatelessWidget {
  final double ingresos, costos, gastos, utilidad, margen, gastosNoDeducibles;
  const _FlujoRenta({
    required this.ingresos,
    required this.costos,
    required this.gastos,
    required this.utilidad,
    required this.margen,
    required this.gastosNoDeducibles,
  });

  @override
  Widget build(BuildContext context) {
    final base = math.max(ingresos, costos + gastos);
    double f(double v) => base > 0 ? math.max(v, 0) / base : 0;
    final segmentos = [
      (costos, _cCostos),
      (gastos, _cGastos),
      (math.max(utilidad, 0.0), _cRenta),
    ].where((s) => s.$1 > 0).toList();

    String pct(double v) => ingresos > 0 ? "${(v / ingresos * 100).toStringAsFixed(0)}%" : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text("Ingresos del año", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _MontoAnimado(ingresos, decimales: 0, estilo: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 16,
            child: segmentos.isEmpty
                ? Container(color: AppColors.surfaceSubtle)
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => Row(
                      children: [
                        for (var i = 0; i < segmentos.length; i++) ...[
                          if (i > 0) Container(width: 2, color: AppColors.surface),
                          Expanded(
                            flex: math.max(1, (f(segmentos[i].$1) * 1000 * t).round()),
                            child: Container(color: segmentos[i].$2),
                          ),
                        ],
                        Expanded(flex: math.max(1, ((1 - t) * 1000).round()), child: Container(color: AppColors.surfaceSubtle)),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _leyenda("Costo de ventas (compras)", costos, _cCostos, pct(costos)),
        _leyenda("Gastos deducibles", gastos, _cGastos, pct(gastos)),
        _leyenda(utilidad < 0 ? "Pérdida" : "Utilidad antes de impuesto", utilidad, utilidad < 0 ? _cPagar : _cRenta,
            ingresos > 0 ? "margen ${margen.toStringAsFixed(0)}%" : ""),
        if (gastosNoDeducibles > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Además hay ${formatearColones(gastosNoDeducibles, decimales: 0)} en gastos no deducibles (no restan para Renta).",
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _leyenda(String etiqueta, double valor, Color color, String extra) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: Text(etiqueta, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text.rich(TextSpan(children: [
                  if (extra.isNotEmpty) TextSpan(text: "$extra   ", style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                  TextSpan(text: formatearColones(valor, decimales: 0), style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600, fontSize: 13)),
                ])),
              ),
            ),
          ],
        ),
      );
}

/// Columnas de ingresos por mes; la parte verde es lo que quedó de
/// utilidad. Al pasar el mouse (o mantener presionado) se ve el detalle.
class _GraficoMensual extends StatelessWidget {
  final List mensual;
  final int anio;
  const _GraficoMensual({required this.mensual, required this.anio});

  @override
  Widget build(BuildContext context) {
    double n(dynamic v) => double.tryParse('$v') ?? 0.0;
    final meses = mensual.map((m) => (
          mes: (m['mes'] as num).toInt(),
          ingresos: n(m['ingresos']),
          costos: n(m['costos']),
          gastos: n(m['gastos_deducibles']),
          renta: n(m['renta']),
        )).toList();
    final maximo = meses.fold(0.0, (mx, m) => math.max(mx, m.ingresos));
    final ahora = DateTime.now();
    const alto = 110.0;

    return Column(
      children: [
        SizedBox(
          height: alto + 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: meses.map((m) {
              final esActual = anio == ahora.year && m.mes == ahora.month;
              final futuro = anio == ahora.year && m.mes > ahora.month;
              final hIngresos = maximo > 0 ? math.max(m.ingresos, 0) / maximo * alto : 0.0;
              final hRenta = m.ingresos > 0 ? (math.max(m.renta, 0) / m.ingresos).clamp(0.0, 1.0) * hIngresos : 0.0;
              return Expanded(
                child: Tooltip(
                  preferBelow: false,
                  message: "${_mesesLargos[m.mes - 1][0].toUpperCase()}${_mesesLargos[m.mes - 1].substring(1)} $anio\n"
                      "Ingresos ${formatearColones(m.ingresos, decimales: 0)}\n"
                      "Costos ${formatearColones(m.costos, decimales: 0)} · Gastos ${formatearColones(m.gastos, decimales: 0)}\n"
                      "${m.renta < 0 ? 'Pérdida' : 'Utilidad'} ${formatearColones(m.renta, decimales: 0)}",
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(milliseconds: 500 + m.mes * 45),
                          curve: Curves.easeOutCubic,
                          builder: (context, t, _) => Container(
                            height: math.max(hIngresos * t, futuro ? 0 : 2),
                            decoration: BoxDecoration(
                              color: _cVentas.withOpacity(esActual ? 0.9 : 0.55),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                            alignment: Alignment.bottomCenter,
                            child: Container(height: hRenta * t, color: _cRenta.withOpacity(0.9)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _mesesCortos[m.mes - 1][0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: esActual ? AppColors.textStrong : AppColors.textMuted,
                            fontWeight: esActual ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _puntoLeyenda(_cVentas.withOpacity(0.7), "Ingresos"),
            const SizedBox(width: 14),
            _puntoLeyenda(_cRenta, "Utilidad"),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Tocá un mes para ver el detalle",
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _puntoLeyenda(Color color, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(texto, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      );
}
