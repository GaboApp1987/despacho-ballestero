import 'dart:convert';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'export_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Lo de la planilla que va fuera del período: tasas por año (solo el
/// administrador las edita), vacaciones y el reporte mensual para la CCSS.

num _n(dynamic v) => (v as num?) ?? 0;
String _f(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _corta(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day}/${d.month}/${d.year}';
}

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre'];

// ------------------------------------------------------------------ tasas
/// Tasas de la planilla por año: CCSS, tramos del impuesto al salario,
/// créditos y base mínima contributiva. Solo el administrador las cambia.
class TasasPlanillaScreen extends StatefulWidget {
  const TasasPlanillaScreen({super.key});

  @override
  State<TasasPlanillaScreen> createState() => _TasasPlanillaScreenState();
}

class _TasasPlanillaScreenState extends State<TasasPlanillaScreen> {
  int _anio = DateTime.now().year;
  Map<String, dynamic>? _datos;
  bool _guardada = false;
  bool _puedeEditar = false;
  bool _guardando = false;
  String? _error;
  // Sube al borrar un concepto, para que los campos se vuelvan a armar.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _datos = null;
      _error = null;
    });
    try {
      final r = ApiService.verificar(await ApiService.get('/planillas/tablas/$_anio/'));
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (mounted) {
        setState(() {
          // Copia profunda para editar sin tocar lo cargado.
          _datos = json.decode(json.encode(d['datos'])) as Map<String, dynamic>;
          _guardada = d['guardada'] == true;
          _puedeEditar = d['puede_editar'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      ApiService.verificar(await ApiService.put('/planillas/tablas/$_anio/', {'datos': _datos}));
      if (!mounted) return;
      setState(() => _guardada = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tasas de $_anio guardadas')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _numero(String id, String etiqueta, dynamic valor, ValueChanged<num?> onCambio,
      {String? sufijo, bool permitirVacio = false, double ancho = 130}) {
    return SizedBox(
      width: ancho,
      child: TextFormField(
        key: ValueKey('$_anio-$_version-$id'),
        initialValue: valor == null ? '' : formatearNumero(valor as num, decimales: (valor % 1 == 0) ? 0 : 2).replaceAll('.', ''),
        enabled: _puedeEditar,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: etiqueta, suffixText: sufijo, isDense: true, border: const OutlineInputBorder(),
            hintText: permitirVacio ? 'Sin tope' : null),
        onChanged: (t) => onCambio(t.trim().isEmpty ? null : num.tryParse(t.trim().replaceAll(',', '.'))),
      ),
    );
  }

  Widget _cuotas(String titulo, String clave) {
    final lista = (_datos![clave] as List);
    final total = lista.fold<num>(0, (s, c) => s + _n(c['pct']));
    return _bloque('$titulo · ${formatearNumero(total, decimales: 2)} %', [
      for (final (i, c) in lista.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 150,
              child: TextFormField(
                key: ValueKey('$_anio-$_version-$clave-$i-concepto'),
                initialValue: c['concepto'],
                enabled: _puedeEditar,
                decoration: const InputDecoration(labelText: 'Concepto', isDense: true, border: OutlineInputBorder()),
                onChanged: (t) => c['concepto'] = t,
              ),
            ),
            _numero('$clave-$i-pct', '%', c['pct'], (v) => setState(() => c['pct'] = v ?? 0), ancho: 90),
            DropdownButton<String>(
              value: c['base'],
              items: const [
                DropdownMenuItem(value: 'sem', child: Text('Base mín. SEM')),
                DropdownMenuItem(value: 'ivm', child: Text('Base mín. IVM')),
                DropdownMenuItem(value: 'salario', child: Text('Salario real')),
              ],
              onChanged: _puedeEditar ? (v) => setState(() => c['base'] = v) : null,
            ),
            if (_puedeEditar)
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() {
                lista.removeAt(i);
                _version++;
              })),
          ]),
        ),
      if (_puedeEditar)
        TextButton.icon(
          onPressed: () => setState(() => lista.add({'concepto': '', 'pct': 0, 'base': 'salario'})),
          icon: const Icon(Icons.add),
          label: const Text('Agregar concepto'),
        ),
    ]);
  }

  Widget _bloque(String titulo, List<Widget> hijos) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 10),
      ...hijos,
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    final anios = [for (var a = DateTime.now().year + 1; a >= DateTime.now().year - 2; a--) a];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tasas de planilla'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [const BotonCalculadora(), 
          DropdownButton<int>(
            value: _anio,
            underline: const SizedBox(),
            items: [for (final a in anios) DropdownMenuItem(value: a, child: Text('$a'))],
            onChanged: (v) {
              _anio = v ?? _anio;
              _cargar();
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: d == null || !_puedeEditar
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text('Guardar tasas de $_anio'),
                ),
              ),
            ),
      body: d == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      _guardada
                          ? 'Estas son las tasas guardadas para $_anio. Las planillas en borrador de ese año se recalculan con ellas '
                              '(tocá "Actualizar salarios"); las cerradas no cambian.'
                          : 'Todavía no hay tasas guardadas para $_anio: se usan las del año anterior más reciente. '
                              'Revisalas cada enero (tramos del impuesto, base mínima) y guardalas.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    _cuotas('CCSS del trabajador', 'ccss_trabajador'),
                    _cuotas('CCSS del patrono', 'ccss_patrono'),
                    _bloque('Base mínima contributiva (mensual)', [
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        _numero('bmc_sem', 'SEM (₡)', d['bmc_sem'], (v) => d['bmc_sem'] = v ?? 0, ancho: 160),
                        _numero('bmc_ivm', 'IVM (₡)', d['bmc_ivm'], (v) => d['bmc_ivm'] = v ?? 0, ancho: 160),
                      ]),
                    ]),
                    _bloque('Impuesto al salario (tramos mensuales)', [
                      for (final (i, t) in (d['tramos'] as List).indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(
                              width: 22,
                              child: Text('${i + 1}.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                            ),
                            Expanded(
                              child: _numero('tramo-$i-hasta', 'Hasta (₡)', t['hasta'], (v) => t['hasta'] = v, permitirVacio: true, ancho: 150),
                            ),
                            const SizedBox(width: 8),
                            _numero('tramo-$i-pct', '%', t['pct'], (v) => t['pct'] = v ?? 0, ancho: 80),
                          ]),
                        ),
                      Text('El último tramo va sin tope.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                    _bloque('Créditos fiscales por mes', [
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        _numero('hijo', 'Por hijo (₡)', d['credito_hijo'], (v) => d['credito_hijo'] = v ?? 0, ancho: 160),
                        _numero('conyuge', 'Por cónyuge (₡)', d['credito_conyuge'], (v) => d['credito_conyuge'] = v ?? 0, ancho: 160),
                      ]),
                    ]),
                  ],
                ),
              ),
            ),
    );
  }
}

// -------------------------------------------------------------- vacaciones
class VacacionesScreen extends StatefulWidget {
  final Negocio negocio;
  const VacacionesScreen({super.key, required this.negocio});

  @override
  State<VacacionesScreen> createState() => _VacacionesScreenState();
}

class _VacacionesScreenState extends State<VacacionesScreen> {
  List<Map<String, dynamic>>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get('/planillas/vacaciones/?negocio=${widget.negocio.id}'));
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (mounted) setState(() => _lista = [for (final c in d['colaboradores'] as List) Map<String, dynamic>.from(c)]);
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  /// Días de lunes a sábado entre dos fechas (los domingos no cuentan).
  static int _diasHabiles(DateTime a, DateTime b) {
    var n = 0;
    for (var d = a; !d.isAfter(b); d = d.add(const Duration(days: 1))) {
      if (d.weekday != DateTime.sunday) n++;
    }
    return n;
  }

  Future<void> _registrar(Map<String, dynamic> c) async {
    var desde = DateTime.now();
    var hasta = DateTime.now();
    final dias = TextEditingController(text: '1');
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> elegir(bool inicio) async {
            final d = await showDatePicker(
              context: ctx,
              initialDate: inicio ? desde : hasta,
              firstDate: DateTime.now().subtract(const Duration(days: 730)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d == null) return;
            setD(() {
              if (inicio) {
                desde = d;
                if (hasta.isBefore(desde)) hasta = desde;
              } else {
                hasta = d.isBefore(desde) ? desde : d;
              }
              dias.text = '${_diasHabiles(desde, hasta)}';
            });
          }

          Widget fecha(String t, DateTime d, bool inicio) => Expanded(
            child: InkWell(
              onTap: () => elegir(inicio),
              child: InputDecorator(
                decoration: InputDecoration(labelText: t, isDense: true, border: const OutlineInputBorder()),
                child: Text('${d.day}/${d.month}/${d.year}'),
              ),
            ),
          );

          return AlertDialog(
            title: Text('Vacaciones de ${c['nombre']}'),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [fecha('Desde', desde, true), const SizedBox(width: 10), fecha('Hasta', hasta, false)]),
                const SizedBox(height: 10),
                TextField(
                  controller: dias,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Días', helperText: 'De lunes a sábado; cambialo si no trabaja sábados.', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(controller: nota, decoration: const InputDecoration(labelText: 'Nota (opcional)', isDense: true, border: OutlineInputBorder())),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
            ],
          );
        },
      ),
    );
    final datos = {
      'negocio': widget.negocio.id, 'empleado': c['empleado_id'], 'desde': _f(desde), 'hasta': _f(hasta),
      'dias': dias.text.trim().replaceAll(',', '.'), 'nota': nota.text.trim(),
    };
    dias.dispose();
    nota.dispose();
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.post('/planillas/vacaciones/', datos));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
    }
  }

  Future<void> _borrar(Map<String, dynamic> v) async {
    try {
      ApiService.verificar(await ApiService.delete('/planillas/vacaciones/${v['id']}/'));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  String _d(num v) => formatearNumero(v, decimales: v % 1 == 0 ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Vacaciones'), backgroundColor: AppColors.surface, foregroundColor: AppColors.textStrong, actions: const [BotonCalculadora()]),
      body: lista == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Se ganan proporcionales a los meses trabajados desde que entró (por ley, dos semanas por cada 50 semanas). '
                  'Los días por año de cada uno se cambian en Editar colaborador.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (lista.isEmpty) Text('No hay colaboradores activos.', style: TextStyle(color: AppColors.textMuted)),
                for (final c in lista)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.border)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c['nombre'], style: const TextStyle(fontWeight: FontWeight.w700))),
                          if (c['saldo'] != null)
                            Text('${_d(_n(c['saldo']))} días', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
                        ]),
                        if (c['fecha_ingreso'] == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Sin fecha de ingreso: ponésela en Editar colaborador para calcular sus vacaciones.',
                                style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900)),
                          )
                        else
                          Text(
                            'Entró el ${_corta(c['fecha_ingreso'])} · ${c['dias_anuales']} días por año · ganó ${_d(_n(c['acumuladas']))}, '
                            'tomó ${_d(_n(c['tomadas']))}${_n(c['valor_saldo']) > 0 ? ' · saldo vale ${formatearColones(_n(c['valor_saldo']), decimales: 0)}' : ''}',
                            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                          ),
                        for (final v in c['registros'] as List)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.beach_access_outlined, size: 18, color: AppColors.textMuted),
                            title: Text('${_corta(v['desde'])} al ${_corta(v['hasta'])} · ${_d(_n(v['dias']))} días'),
                            subtitle: (v['nota'] ?? '').toString().isEmpty ? null : Text(v['nota']),
                            trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _borrar(Map<String, dynamic>.from(v))),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _registrar(c),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Registrar vacaciones'),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}

// -------------------------------------------------------------- reporte CCSS
class ReporteCCSSScreen extends StatefulWidget {
  final Negocio negocio;
  const ReporteCCSSScreen({super.key, required this.negocio});

  @override
  State<ReporteCCSSScreen> createState() => _ReporteCCSSScreenState();
}

class _ReporteCCSSScreenState extends State<ReporteCCSSScreen> {
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);
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
      final mes = '${_mes.year}-${_mes.month.toString().padLeft(2, '0')}';
      final r = ApiService.verificar(await ApiService.get('/planillas/reporte-ccss/?negocio=${widget.negocio.id}&mes=$mes'));
      if (mounted) setState(() => _datos = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _excel() async {
    final d = _datos!;
    final excel = Excel.createExcel();
    final hoja = excel['CCSS'];
    excel.setDefaultSheet('CCSS');
    for (final s in excel.sheets.keys.toList()) {
      if (s != 'CCSS') excel.delete(s);
    }
    hoja.appendRow([TextCellValue('${widget.negocio.nombreComercial} · Cédula ${widget.negocio.cedula} · Planilla CCSS ${_meses[_mes.month - 1]} ${_mes.year}')]);
    hoja.appendRow([
      for (final t in ['Cédula', 'Nombre', 'Jornada', 'Salario reportado', 'Novedad', 'Fecha de ingreso', 'CCSS trabajador', 'CCSS patrono'])
        TextCellValue(t),
    ]);
    for (final c in d['colaboradores'] as List) {
      hoja.appendRow([
        TextCellValue(c['cedula'] ?? ''),
        TextCellValue(c['nombre']),
        TextCellValue(c['jornada'] == 'parcial' ? 'Parcial' : 'Completa'),
        DoubleCellValue(_n(c['salario_reportado']).toDouble()),
        TextCellValue(c['novedad'] ?? ''),
        TextCellValue(c['fecha_ingreso'] == null ? '' : _corta(c['fecha_ingreso'])),
        DoubleCellValue(_n(c['ccss_obrero']).toDouble()),
        DoubleCellValue(_n(c['ccss_patronal']).toDouble()),
      ]);
    }
    await ExportService.guardarExcel(excel, 'CCSS_${_mes.year}${_mes.month.toString().padLeft(2, '0')}.xlsx');
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    final hoy = DateTime.now();
    final meses = [for (var i = 0; i < 12; i++) DateTime(hoy.year, hoy.month - i, 1)];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reporte para la CCSS'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [const BotonCalculadora(), 
          DropdownButton<DateTime>(
            value: _mes,
            underline: const SizedBox(),
            items: [for (final m in meses) DropdownMenuItem(value: m, child: Text('${_meses[m.month - 1]} ${m.year}'))],
            onChanged: (v) {
              _mes = v ?? _mes;
              _cargar();
            },
          ),
          if (d != null) IconButton(tooltip: 'Excel', icon: const Icon(Icons.table_view_outlined), onPressed: _excel),
          const SizedBox(width: 8),
        ],
      ),
      body: d == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Lo que se reporta a la CCSS en el mes, por colaborador (si pagás por quincena, se suman las dos). '
                  'Con esto se llena la planilla en la Oficina Virtual de la CCSS, o se le pasa al contador en Excel.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                if (d['hay_borradores'] == true)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text('Hay planillas de este mes en borrador: los montos pueden cambiar hasta que las cerrés.',
                        style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900)),
                  ),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _tarjeta('Salarios reportados', _n(d['total_salarios'])),
                  _tarjeta('Total a la CCSS', _n(d['total_ccss'])),
                ]),
                const SizedBox(height: 12),
                if ((d['colaboradores'] as List).isEmpty) Text('No hay planillas en este mes.', style: TextStyle(color: AppColors.textMuted)),
                for (final c in d['colaboradores'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c['nombre']),
                    subtitle: Text([
                      if ((c['cedula'] ?? '').toString().isNotEmpty) 'Cédula ${c['cedula']}' else 'Sin cédula (ponésela en Editar colaborador)',
                      c['jornada'] == 'parcial' ? 'Jornada parcial' : 'Jornada completa',
                      if ((c['novedad'] ?? '').toString().isNotEmpty) c['novedad'],
                      if (c['bmc_aplicada'] == true) 'Cotiza sobre la base mínima',
                    ].join(' · ')),
                    trailing: Text(formatearColones(_n(c['salario_reportado']), decimales: 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
    );
  }

  Widget _tarjeta(String t, num v) => Container(
    width: 180,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      Text(formatearColones(v, decimales: 0), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    ]),
  );
}
