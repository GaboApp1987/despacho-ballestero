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

Widget filaDeclaracion(String etiqueta, double valor, {bool resaltado = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(etiqueta, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Text(
          formatearColones(valor),
          style: TextStyle(
            fontSize: resaltado ? 16 : 14,
            fontWeight: resaltado ? FontWeight.bold : FontWeight.w500,
            color: resaltado ? AppColors.textStrong : Colors.grey[700],
          ),
        ),
      ],
    ),
  );
}

Widget buildDeclaracionIva(Map<String, dynamic> d) {
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

  final bool sinSaldo = saldoIva.abs() < 0.01;
  final Color colorSaldo = sinSaldo ? Colors.grey[700]! : (aPagar ? Colors.red[700]! : Colors.green[700]!);
  final Color fondoSaldo = sinSaldo ? AppColors.surfaceSubtle : (aPagar ? Colors.red[50]! : Colors.green[50]!);
  final String etiquetaSaldo = sinSaldo ? "Sin saldo de IVA en el periodo" : (aPagar ? "IVA a pagar" : "IVA a favor (saldo acumulable)");

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // DÉBITO FISCAL (VENTAS)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("DÉBITO FISCAL (VENTAS)", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  filaDeclaracion("Ventas gravadas", ventasGravadas),
                  filaDeclaracion("IVA de ventas", debitoFiscal, resaltado: true),
                ],
              ),
            ),
            Container(width: 1, height: 70, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 20)),
            // CRÉDITO FISCAL (COMPRAS)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("CRÉDITO FISCAL (COMPRAS)", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  filaDeclaracion("Compras netas", comprasTotales),
                  filaDeclaracion("IVA de compras (est.)", creditoFiscal, resaltado: true),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: fondoSaldo, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Expanded(
                child: Text(etiquetaSaldo, overflow: TextOverflow.ellipsis, style: TextStyle(color: colorSaldo, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text(formatearColones(saldoIva.abs()), style: TextStyle(color: colorSaldo, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "$cantFacturas factura(s) · $cantNotas nota(s) de crédito · $cantCompras compra(s) en el periodo",
          style: TextStyle(color: Colors.grey[400], fontSize: 11),
        ),
        if (debitoPorTarifa.isNotEmpty || creditoPorTarifa.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 6),
          Text("Detalle por tarifa de IVA", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _tablaPorTarifa("Ventas (débito)", debitoPorTarifa)),
              const SizedBox(width: 20),
              Expanded(child: _tablaPorTarifa("Compras (crédito)", creditoPorTarifa)),
            ],
          ),
        ],
        if (lineasSinImpuesto > 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "$lineasSinImpuesto línea(s) de compra son de productos sin impuesto asignado: no se incluyeron en el crédito fiscal. Asígnales una tarifa en Productos para un cálculo más exacto.",
                  style: TextStyle(color: Colors.orange[700], fontSize: 11),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
          "Cálculo de referencia para armar la declaración; verifícalo antes de presentarlo ante Hacienda.",
          style: TextStyle(color: Colors.grey[400], fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
    ),
  );
}

Widget buildDeclaracionRenta(Map<String, dynamic> d) {
  final bool configurado = d['parametros_configurados'] == true;
  final ingresosBrutos = numDeDeclaracion(d, 'ingresos_brutos');
  final costoVentas = numDeDeclaracion(d, 'costo_ventas');
  final gastosDeducibles = numDeDeclaracion(d, 'gastos_deducibles');
  final gastosNoDeducibles = numDeDeclaracion(d, 'gastos_no_deducibles');
  final rentaLiquida = numDeDeclaracion(d, 'renta_liquida_gravable');
  final impuestoEstimado = numDeDeclaracion(d, 'impuesto_estimado');
  final tipoContribuyente = d['tipo_contribuyente'] == 'juridica' ? 'Persona Jurídica' : 'Persona Física con Actividad Lucrativa';
  final tarifaUnica = d['tarifa_unica_aplicada'] as String?;
  final gastosPorCategoria = (d['gastos_por_categoria'] as List?) ?? [];
  final desgloseTramos = (d['desglose_tramos'] as List?) ?? [];

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text("Régimen: $tipoContribuyente", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
            if (!configurado)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(20)),
                child: Text("Sin tramos configurados para este periodo", style: TextStyle(color: Colors.red[700], fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("INGRESOS Y COSTOS", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  filaDeclaracion("Ingresos brutos (ventas)", ingresosBrutos),
                  filaDeclaracion("Costo de ventas (compras)", costoVentas),
                  filaDeclaracion("Gastos deducibles", gastosDeducibles),
                  if (gastosNoDeducibles > 0) filaDeclaracion("Gastos no deducibles", gastosNoDeducibles),
                ],
              ),
            ),
            Container(width: 1, height: 90, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 20)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("RESULTADO", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  filaDeclaracion("Renta líquida gravable", rentaLiquida, resaltado: true),
                  filaDeclaracion("Impuesto estimado", impuestoEstimado, resaltado: true),
                  if (tarifaUnica != null)
                    Text("Tarifa única aplicada: $tarifaUnica% (ingresos brutos superan el límite de tramos)", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          ],
        ),
        if (gastosPorCategoria.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 6),
          Text("Gastos deducibles por categoría", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...gastosPorCategoria.map((g) {
            final cat = categoriasGastoLabel[g['categoria']] ?? g['categoria'].toString();
            final total = double.tryParse(g['total'].toString()) ?? 0.0;
            return filaDeclaracion(cat, total);
          }),
        ],
        if (desgloseTramos.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 6),
          Text("Desglose por tramo", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...desgloseTramos.map((t) {
            final desde = double.tryParse(t['desde'].toString()) ?? 0.0;
            final hastaStr = t['hasta'];
            final hasta = hastaStr != null ? double.tryParse(hastaStr.toString()) : null;
            final pct = t['porcentaje'];
            final impuestoTramo = double.tryParse(t['impuesto_tramo'].toString()) ?? 0.0;
            final rango = hasta != null
                ? "${formatearColones(desde, decimales: 0)} - ${formatearColones(hasta, decimales: 0)}"
                : "Más de ${formatearColones(desde, decimales: 0)}";
            return filaDeclaracion("$rango ($pct%)", impuestoTramo);
          }),
        ],
        const SizedBox(height: 10),
        Text(
          "Cálculo de referencia: el costo de ventas se aproxima con las compras del año (no se costea inventario por unidad vendida) y no incluye depreciación fiscal detallada, pérdidas de periodos anteriores ni créditos personales (cónyuge/hijos). Verifíquelo con su contador antes de presentar el D-101.",
          style: TextStyle(color: Colors.grey[400], fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
    ),
  );
}

Widget _tablaPorTarifa(String titulo, List tarifas) {
  if (tarifas.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text("Sin líneas en el periodo", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      ],
    );
  }
  final totalBase = tarifas.fold(0.0, (s, t) => s + (double.tryParse(t['base'].toString()) ?? 0.0));
  final totalIva = tarifas.fold(0.0, (s, t) => s + (double.tryParse(t['iva'].toString()) ?? 0.0));

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Table(
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2)},
        children: [
          TableRow(children: [
            Text("Tarifa", style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
            Text("Base", textAlign: TextAlign.right, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
            Text("IVA", textAlign: TextAlign.right, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
            Text("Total", textAlign: TextAlign.right, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
          ...tarifas.map((t) {
            final tarifa = t['tarifa'];
            final base = double.tryParse(t['base'].toString()) ?? 0.0;
            final iva = double.tryParse(t['iva'].toString()) ?? 0.0;
            return TableRow(children: [
              Padding(padding: const EdgeInsets.only(top: 4), child: Text("$tarifa%", style: const TextStyle(fontSize: 12))),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(formatearColones(base, decimales: 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(formatearColones(iva, decimales: 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(formatearColones(base + iva, decimales: 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
            ]);
          }),
          TableRow(children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: Text("Total", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]))),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(formatearColones(totalBase, decimales: 0), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]))),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(formatearColones(totalIva, decimales: 0), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]))),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(formatearColones(totalBase + totalIva, decimales: 0), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]))),
          ]),
        ],
      ),
    ],
  );
}
