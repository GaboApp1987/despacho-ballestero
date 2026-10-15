import 'dart:convert';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api_service.dart';
import 'export_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';

/// Planilla de los colaboradores (gestion/planilla.py): períodos mensuales o
/// quincenales con CCSS, impuesto al salario, horas extra, comisiones,
/// bonos y deducciones; costo para el patrono, colillas en PDF, Excel y
/// aguinaldo. Va como pestaña de Colaboradores (solo el dueño).

String _f(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _corta(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day}/${d.month}/${d.year}';
}

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre'];

String nombrePeriodo(Map<String, dynamic> p) {
  final desde = DateTime.parse(p['desde']);
  final mes = '${_meses[desde.month - 1]} ${desde.year}';
  if (p['frecuencia'] == 'quincenal') return '${desde.day == 1 ? '1.ª' : '2.ª'} quincena de $mes';
  return mes[0].toUpperCase() + mes.substring(1);
}

num _n(dynamic v) => (v as num?) ?? 0;

class PlanillaTab extends StatefulWidget {
  final Negocio negocio;
  const PlanillaTab({super.key, required this.negocio});

  @override
  State<PlanillaTab> createState() => _PlanillaTabState();
}

class _PlanillaTabState extends State<PlanillaTab> {
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get('/planillas/?negocio=${widget.negocio.id}'));
      if (mounted) setState(() => _datos = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _nueva() async {
    final hoy = DateTime.now();
    var frecuencia = 'mensual';
    var mes = DateTime(hoy.year, hoy.month, 1);
    var segunda = hoy.day > 15;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final meses = [for (var i = -3; i <= 1; i++) DateTime(hoy.year, hoy.month + i, 1)];
          return AlertDialog(
            title: const Text('Nueva planilla'),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'mensual', label: Text('Mensual')),
                    ButtonSegment(value: 'quincenal', label: Text('Quincenal')),
                  ],
                  selected: {frecuencia},
                  onSelectionChanged: (v) => setD(() => frecuencia = v.first),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<DateTime>(
                  initialValue: mes,
                  decoration: const InputDecoration(labelText: 'Mes', border: OutlineInputBorder(), isDense: true),
                  items: [
                    for (final m in meses) DropdownMenuItem(value: m, child: Text('${_meses[m.month - 1]} ${m.year}')),
                  ],
                  onChanged: (v) => setD(() => mes = v ?? mes),
                ),
                if (frecuencia == 'quincenal') ...[
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('1 al 15')),
                      ButtonSegment(value: true, label: Text('16 al fin de mes')),
                    ],
                    selected: {segunda},
                    onSelectionChanged: (v) => setD(() => segunda = v.first),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Entra cada colaborador activo con salario, con su comisión del período ya calculada. '
                  'Después agregás horas extra, bonos y deducciones.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Armar planilla')),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final finMes = DateTime(mes.year, mes.month + 1, 0);
    final desde = frecuencia == 'quincenal' && segunda ? DateTime(mes.year, mes.month, 16) : mes;
    final hasta = frecuencia == 'quincenal' && !segunda ? DateTime(mes.year, mes.month, 15) : finMes;
    try {
      final r = ApiService.verificar(await ApiService.post('/planillas/', {
        'negocio': widget.negocio.id, 'frecuencia': frecuencia, 'desde': _f(desde), 'hasta': _f(hasta),
      }));
      final p = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes)));
      await _cargar();
      if (mounted) _abrir(p);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
    }
  }

  Future<void> _abrir(Map<String, dynamic> p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlanillaDetalleScreen(negocio: widget.negocio, planillaId: p['id'])));
    _cargar();
  }

  Future<void> _riesgos() async {
    final ctrl = TextEditingController(text: formatearNumero(_n(_datos?['riesgos_trabajo_pct']), decimales: 2));
    final valor = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Póliza de Riesgos del Trabajo'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('El porcentaje que cobra el INS según la actividad del negocio (viene en la póliza). Se suma al costo de cada colaborador.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Porcentaje (%)', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
    ctrl.dispose();
    if (valor == null) return;
    try {
      ApiService.verificar(await ApiService.patch('/planillas/config/?negocio=${widget.negocio.id}',
          {'riesgos_trabajo_pct': valor.trim().replaceAll(',', '.')}));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    if (d == null) {
      return Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator());
    }
    final planillas = [for (final p in d['planillas'] as List) Map<String, dynamic>.from(p)];
    final sinSalario = [for (final n in d['sin_salario'] as List) n.toString()];
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _nueva, icon: const Icon(Icons.add), label: const Text('Nueva planilla')),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AguinaldoScreen(negocio: widget.negocio))),
              icon: const Icon(Icons.card_giftcard_outlined),
              label: const Text('Aguinaldo'),
            ),
            OutlinedButton.icon(
              onPressed: _riesgos,
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text('Riesgos del Trabajo: ${formatearNumero(_n(d['riesgos_trabajo_pct']), decimales: 2)} %'),
            ),
          ]),
          if (sinSalario.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(
                'Sin salario (no entran en la planilla): ${sinSalario.join(', ')}. Ponéselo en Equipo, en Editar colaborador.',
                style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
              ),
            ),
          const SizedBox(height: 16),
          if (planillas.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'Todavía no hay planillas. Ponele el salario a cada colaborador (Equipo, Editar) y tocá "Nueva planilla": '
                'se calculan la CCSS, el impuesto al salario y lo que te cuesta cada uno.',
              ),
            ),
          for (final p in planillas)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.border)),
              child: ListTile(
                onTap: () => _abrir(p),
                leading: CircleAvatar(
                  backgroundColor: (p['estado'] == 'cerrada' ? Colors.green : Colors.orange).withValues(alpha: 0.14),
                  child: Icon(p['estado'] == 'cerrada' ? Icons.lock_outline : Icons.edit_note,
                      color: p['estado'] == 'cerrada' ? Colors.green.shade700 : Colors.orange.shade800),
                ),
                title: Text(nombrePeriodo(p), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${p['estado'] == 'cerrada' ? 'Cerrada' : 'Borrador'} · ${p['colaboradores']} '
                  '${p['colaboradores'] == 1 ? 'colaborador' : 'colaboradores'} · Costo ${formatearColones(_n(p['totales']['costo_total']), decimales: 0)}',
                ),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formatearColones(_n(p['totales']['neto']), decimales: 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('a pagar', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class PlanillaDetalleScreen extends StatefulWidget {
  final Negocio negocio;
  final int planillaId;
  const PlanillaDetalleScreen({super.key, required this.negocio, required this.planillaId});

  @override
  State<PlanillaDetalleScreen> createState() => _PlanillaDetalleScreenState();
}

class _PlanillaDetalleScreenState extends State<PlanillaDetalleScreen> {
  Map<String, dynamic>? _p;
  String? _error;
  bool _ocupado = false;

  bool get _cerrada => _p?['estado'] == 'cerrada';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aplicar(dynamic r) => _p = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes)));

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get('/planillas/${widget.planillaId}/'));
      if (mounted) setState(() => _aplicar(r));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _llamar(Future<dynamic> Function() f, {String? listo}) async {
    setState(() => _ocupado = true);
    try {
      final r = ApiService.verificar(await f());
      if (mounted) {
        setState(() => _aplicar(r));
        if (listo != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(listo)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cerrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar planilla'),
        content: const Text('Al cerrarla queda fija: ya no se cambian montos y cuenta para el aguinaldo. ¿Revisaste cada colaborador?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar planilla')),
        ],
      ),
    );
    if (ok == true) _llamar(() => ApiService.post('/planillas/${widget.planillaId}/cerrar/', {}), listo: 'Planilla cerrada');
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar planilla'),
        content: const Text('Se borra este borrador. Podés armarla de nuevo cuando querás.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.delete('/planillas/${widget.planillaId}/'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  Future<void> _editar(Map<String, dynamic> l) async {
    final campos = {
      'horas_extra': TextEditingController(text: _num(l['horas_extra'])),
      'horas_dobles': TextEditingController(text: _num(l['horas_dobles'])),
      'comision': TextEditingController(text: _num(l['comision'])),
      'bonos': TextEditingController(text: _num(l['bonos'])),
      'otras_deducciones': TextEditingController(text: _num(l['otras_deducciones'])),
      'salario_periodo': TextEditingController(text: _num(l['salario_periodo'])),
    };
    final detalle = TextEditingController(text: l['detalle_deducciones'] ?? '');
    final hora = _n(l['salario_base']) / 240;
    Widget campo(String clave, String etiqueta, {String? ayuda}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: campos[clave],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, isDense: true, border: const OutlineInputBorder()),
      ),
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l['nombre']),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              campo('salario_periodo', 'Salario del período (₡)',
                  ayuda: 'Salario mensual ${formatearColones(_n(l['salario_base']), decimales: 0)}. Cambialo si faltó o entró a mitad del período.'),
              Row(children: [
                Expanded(child: campo('horas_extra', 'Horas extra', ayuda: 'x1,5 · ${formatearColones(hora * 1.5, decimales: 0)}/h')),
                const SizedBox(width: 10),
                Expanded(child: campo('horas_dobles', 'Horas dobles', ayuda: 'Feriados x2 · ${formatearColones(hora * 2, decimales: 0)}/h')),
              ]),
              campo('comision', 'Comisión (₡)', ayuda: 'Calculada de sus ventas del período; la podés cambiar.'),
              campo('bonos', 'Bonos u otros pagos (₡)'),
              campo('otras_deducciones', 'Otras deducciones (₡)', ayuda: 'Adelantos, préstamos, embargos…'),
              TextField(
                controller: detalle,
                decoration: const InputDecoration(labelText: 'Detalle de las deducciones', isDense: true, border: OutlineInputBorder()),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'quitar'),
            child: const Text('Quitar de esta planilla'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'guardar'), child: const Text('Guardar')),
        ],
      ),
    );
    final datos = {
      for (final e in campos.entries) e.key: e.value.text.trim().replaceAll(',', '.').isEmpty ? '0' : e.value.text.trim().replaceAll(',', '.'),
      'detalle_deducciones': detalle.text.trim(),
    };
    for (final c in [...campos.values, detalle]) {
      c.dispose();
    }
    if (res == 'guardar') {
      _llamar(() => ApiService.patch('/planillas/${widget.planillaId}/lineas/${l['id']}/', datos));
    } else if (res == 'quitar') {
      _llamar(() => ApiService.delete('/planillas/${widget.planillaId}/lineas/${l['id']}/'));
    }
  }

  static String _num(dynamic v) {
    final n = _n(v);
    if (n == 0) return '';
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }

  // ---------------------------------------------------------------- PDF y Excel
  Future<void> _colillas({Map<String, dynamic>? solo}) async {
    final p = _p!;
    final lineas = solo != null ? [solo] : [for (final l in p['lineas'] as List) Map<String, dynamic>.from(l)];
    final doc = pw.Document();
    pw.Widget fila(String a, num v, {bool fuerte = false, bool resta = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(a, style: pw.TextStyle(fontWeight: fuerte ? pw.FontWeight.bold : null)),
        pw.Text('${resta ? '- ' : ''}${formatearColones(v)}', style: pw.TextStyle(fontWeight: fuerte ? pw.FontWeight.bold : null)),
      ]),
    );
    for (final l in lineas) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(widget.negocio.nombreComercial, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Cédula ${widget.negocio.cedula}'),
          pw.SizedBox(height: 12),
          pw.Text('Comprobante de pago · ${nombrePeriodo(p)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text('Del ${_corta(p['desde'])} al ${_corta(p['hasta'])}'),
          pw.SizedBox(height: 10),
          pw.Text('Colaborador: ${l['nombre']}${(l['cedula'] ?? '').toString().isEmpty ? '' : ' · Cédula ${l['cedula']}'}'),
          pw.Divider(),
          pw.Text('Ingresos', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          fila('Salario del período', _n(l['salario_periodo'])),
          if (_n(l['monto_extras']) > 0)
            fila('Horas extra (${_num(l['horas_extra'])} x1,5${_n(l['horas_dobles']) > 0 ? ', ${_num(l['horas_dobles'])} dobles' : ''})', _n(l['monto_extras'])),
          if (_n(l['comision']) > 0) fila('Comisión', _n(l['comision'])),
          if (_n(l['bonos']) > 0) fila('Bonos u otros pagos', _n(l['bonos'])),
          fila('Salario bruto', _n(l['bruto']), fuerte: true),
          pw.SizedBox(height: 8),
          pw.Text('Deducciones', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          fila('CCSS (10,83 %)', _n(l['ccss_obrero']), resta: true),
          if (_n(l['renta']) > 0) fila('Impuesto al salario', _n(l['renta']), resta: true),
          if (_n(l['otras_deducciones']) > 0)
            fila('Otras${(l['detalle_deducciones'] ?? '').toString().isEmpty ? '' : ': ${l['detalle_deducciones']}'}', _n(l['otras_deducciones']), resta: true),
          pw.Divider(),
          fila('Neto a pagar', _n(l['neto']), fuerte: true),
          pw.SizedBox(height: 50),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(children: [pw.Container(width: 180, height: 1, color: PdfColors.grey), pw.Text('Firma del patrono')]),
            pw.Column(children: [pw.Container(width: 180, height: 1, color: PdfColors.grey), pw.Text('Recibí conforme')]),
          ]),
        ]),
      ));
    }
    final nombre = solo != null ? 'Colilla_${solo['nombre']}_${p['desde']}.pdf' : 'Colillas_${p['desde']}.pdf';
    await Printing.sharePdf(bytes: await doc.save(), filename: nombre.replaceAll(' ', '_'));
  }

  Future<void> _excel() async {
    final p = _p!;
    final excel = Excel.createExcel();
    final hoja = excel['Planilla'];
    excel.setDefaultSheet('Planilla');
    for (final s in excel.sheets.keys.toList()) {
      if (s != 'Planilla') excel.delete(s);
    }
    const columnas = [
      ('Colaborador', 'nombre'), ('Cédula', 'cedula'), ('Salario período', 'salario_periodo'), ('Horas extra', 'horas_extra'),
      ('Horas dobles', 'horas_dobles'), ('Monto extras', 'monto_extras'), ('Comisión', 'comision'), ('Bonos', 'bonos'),
      ('Bruto', 'bruto'), ('CCSS trabajador', 'ccss_obrero'), ('Impuesto salario', 'renta'), ('Otras deducciones', 'otras_deducciones'),
      ('Neto', 'neto'), ('CCSS patrono', 'ccss_patronal'), ('Riesgos del Trabajo', 'riesgos'), ('Costo total', 'costo_total'),
    ];
    hoja.appendRow([TextCellValue('${widget.negocio.nombreComercial} · Planilla ${nombrePeriodo(p)}')]);
    hoja.appendRow([for (final c in columnas) TextCellValue(c.$1)]);
    for (final l in p['lineas'] as List) {
      hoja.appendRow([
        for (final c in columnas)
          l[c.$2] is num ? DoubleCellValue((l[c.$2] as num).toDouble()) : TextCellValue((l[c.$2] ?? '').toString()),
      ]);
    }
    final t = p['totales'] as Map;
    hoja.appendRow([
      TextCellValue('TOTAL'),
      for (final c in columnas.skip(1))
        t.containsKey(c.$2) ? DoubleCellValue((t[c.$2] as num).toDouble()) : TextCellValue(''),
    ]);
    await ExportService.guardarExcel(excel, 'Planilla_${p['desde']}.xlsx');
  }

  Widget _total(String titulo, num valor, {String? nota, Color? color}) => Container(
    width: 170,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      Text(formatearColones(valor, decimales: 0), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
      if (nota != null) Text(nota, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]),
  );

  Widget _dato(String t, num v, {Color? color}) => Padding(
    padding: const EdgeInsets.only(right: 16, top: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      Text(formatearColones(v, decimales: 0), style: TextStyle(fontWeight: FontWeight.w600, color: color)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(p == null ? 'Planilla' : 'Planilla · ${nombrePeriodo(p)}'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          if (p != null) ...[
            IconButton(tooltip: 'Colillas en PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _colillas()),
            IconButton(tooltip: 'Excel', icon: const Icon(Icons.table_view_outlined), onPressed: _excel),
            if (!_cerrada)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'actualizar') {
                    _llamar(() => ApiService.post('/planillas/${widget.planillaId}/actualizar/', {}),
                        listo: 'Se tomaron los salarios y datos actuales');
                  } else if (v == 'borrar') {
                    _borrar();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'actualizar', child: ListTile(leading: Icon(Icons.sync), title: Text('Actualizar salarios'))),
                  PopupMenuItem(value: 'borrar', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Borrar borrador'))),
                ],
              ),
          ],
        ],
      ),
      bottomNavigationBar: p == null || _cerrada
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _ocupado ? null : _cerrar,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Cerrar planilla'),
                ),
              ),
            ),
      body: p == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_ocupado) const LinearProgressIndicator(minHeight: 2),
                    Text(
                      '${_cerrada ? 'Cerrada' : 'Borrador: tocá a cada colaborador para agregar horas extra, bonos o deducciones'} · '
                      'del ${_corta(p['desde'])} al ${_corta(p['hasta'])}',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      _total('A pagar (neto)', _n(p['totales']['neto']), color: AppColors.primary),
                      _total('Salarios brutos', _n(p['totales']['bruto'])),
                      _total('A la CCSS', _n(p['totales']['ccss_obrero']) + _n(p['totales']['ccss_patronal']),
                          nota: 'Trabajador + patrono'),
                      _total('Impuesto al salario', _n(p['totales']['renta']), nota: 'Retenido, se paga a Hacienda'),
                      _total('Costo total', _n(p['totales']['costo_total']), nota: 'Bruto + cargas patronales + INS'),
                    ]),
                    const SizedBox(height: 16),
                    for (final l in [for (final x in p['lineas'] as List) Map<String, dynamic>.from(x)])
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.border)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _cerrada ? null : () => _editar(l),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(l['nombre'], style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      [
                                        'Salario ${formatearColones(_n(l['salario_base']), decimales: 0)}/mes',
                                        if (_n(l['horas_extra']) + _n(l['horas_dobles']) > 0)
                                          '${_num(l['horas_extra'])}${_n(l['horas_dobles']) > 0 ? ' + ${_num(l['horas_dobles'])} dobles' : ''} h extra',
                                        if ((l['detalle_deducciones'] ?? '').toString().isNotEmpty) l['detalle_deducciones'],
                                      ].join(' · '),
                                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                  ]),
                                ),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text(formatearColones(_n(l['neto'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                  Text('neto', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                ]),
                                IconButton(
                                  tooltip: 'Colilla en PDF',
                                  icon: Icon(Icons.receipt_long_outlined, color: AppColors.textMuted, size: 20),
                                  onPressed: () => _colillas(solo: l),
                                ),
                              ]),
                              Wrap(children: [
                                _dato('Bruto', _n(l['bruto'])),
                                if (_n(l['comision']) > 0) _dato('Comisión', _n(l['comision'])),
                                if (_n(l['bonos']) > 0) _dato('Bonos', _n(l['bonos'])),
                                _dato('CCSS', _n(l['ccss_obrero']), color: Colors.red.shade700),
                                if (_n(l['renta']) > 0) _dato('Impuesto', _n(l['renta']), color: Colors.red.shade700),
                                if (_n(l['otras_deducciones']) > 0) _dato('Otras deducciones', _n(l['otras_deducciones']), color: Colors.red.shade700),
                                _dato('Costo patrono', _n(l['costo_total'])),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'CCSS 2026: trabajador 10,83 % y patrono 26,83 %. Impuesto al salario según el Decreto 45333-H '
                      '(exento hasta ₡918.000), con crédito de ₡1.710 por hijo y ₡2.590 por cónyuge. En una quincena se '
                      'proyecta el mes y se retiene la mitad. Hora extra = salario mensual / 240 x 1,5.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Aguinaldo de cada colaborador: lo bruto de las planillas cerradas del 1
/// de diciembre al 30 de noviembre, entre 12.
class AguinaldoScreen extends StatefulWidget {
  final Negocio negocio;
  const AguinaldoScreen({super.key, required this.negocio});

  @override
  State<AguinaldoScreen> createState() => _AguinaldoScreenState();
}

class _AguinaldoScreenState extends State<AguinaldoScreen> {
  int _anio = DateTime.now().year;
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _datos = null);
    try {
      final r = ApiService.verificar(await ApiService.get('/planillas/aguinaldo/?negocio=${widget.negocio.id}&anio=$_anio'));
      if (mounted) setState(() => _datos = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Aguinaldo'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          DropdownButton<int>(
            value: _anio,
            underline: const SizedBox(),
            items: [for (var a = DateTime.now().year; a >= DateTime.now().year - 3; a--) DropdownMenuItem(value: a, child: Text('$a'))],
            onChanged: (v) {
              _anio = v ?? _anio;
              _cargar();
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: d == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Lo bruto pagado en las planillas cerradas del ${_corta(d['desde'])} al ${_corta(d['hasta'])}, entre 12. '
                  'Se paga a más tardar el 20 de diciembre y no lleva CCSS ni impuesto.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Expanded(child: Text('Total a pagar', style: TextStyle(fontWeight: FontWeight.w700))),
                    Text(formatearColones(_n(d['total'])), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
                ),
                const SizedBox(height: 10),
                if ((d['colaboradores'] as List).isEmpty)
                  Text('No hay planillas cerradas en ese período.', style: TextStyle(color: AppColors.textMuted)),
                for (final c in d['colaboradores'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c['nombre']),
                    subtitle: Text('Bruto del período ${formatearColones(_n(c['bruto']), decimales: 0)}'),
                    trailing: Text(formatearColones(_n(c['aguinaldo'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
    );
  }
}
