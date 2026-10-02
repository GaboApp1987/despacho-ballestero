import 'package:flutter/material.dart';

/// Selector de período más simple que el calendario de Material (que en
/// la web ocupaba toda la pantalla con el botón de guardar lejísimos, en
/// la esquina): atajos de un toque, una grilla de meses (un toque = ese
/// mes; un segundo toque = desde/hasta) y, si hace falta, días exactos.
/// El botón "Aplicar" queda justo debajo, con el resumen de lo elegido.
Future<DateTimeRange?> elegirPeriodo(BuildContext context, {required DateTimeRange inicial}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => _SelectorPeriodo(inicial: inicial),
  );
}

const _mesesCortos = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];

String _fecha(DateTime f) => "${f.day} ${_mesesCortos[f.month - 1].toLowerCase()} ${f.year}";

class _SelectorPeriodo extends StatefulWidget {
  final DateTimeRange inicial;
  const _SelectorPeriodo({required this.inicial});

  @override
  State<_SelectorPeriodo> createState() => _SelectorPeriodoState();
}

class _SelectorPeriodoState extends State<_SelectorPeriodo> {
  late DateTime _inicio = DateUtils.dateOnly(widget.inicial.start);
  late DateTime _fin = DateUtils.dateOnly(widget.inicial.end);
  late int _anio = _fin.year;
  // Primer mes tocado de un rango de varios meses (esperando el segundo).
  DateTime? _mesPendiente;

  ColorScheme get _cs => Theme.of(context).colorScheme;

  static DateTime _finDeMes(int anio, int mes) => DateTime(anio, mes + 1, 0);

  List<(String, DateTime, DateTime)> get _atajos {
    final hoy = DateTime.now();
    final trimestre = ((hoy.month - 1) ~/ 3) * 3 + 1;
    return [
      ("Este mes", DateTime(hoy.year, hoy.month, 1), _finDeMes(hoy.year, hoy.month)),
      ("Mes pasado", DateTime(hoy.year, hoy.month - 1, 1), DateTime(hoy.year, hoy.month, 0)),
      ("Este trimestre", DateTime(hoy.year, trimestre, 1), _finDeMes(hoy.year, trimestre + 2)),
      ("Este año", DateTime(hoy.year, 1, 1), DateTime(hoy.year, 12, 31)),
      ("Año pasado", DateTime(hoy.year - 1, 1, 1), DateTime(hoy.year - 1, 12, 31)),
    ];
  }

  void _fijar(DateTime inicio, DateTime fin) => setState(() {
        _inicio = inicio;
        _fin = fin;
        _anio = fin.year;
        _mesPendiente = null;
      });

  void _tocarMes(int mes) {
    final elegido = DateTime(_anio, mes, 1);
    final pendiente = _mesPendiente;
    if (pendiente == null) {
      // Primer toque: ese mes completo (y queda listo para extender).
      setState(() {
        _inicio = elegido;
        _fin = _finDeMes(_anio, mes);
        _mesPendiente = elegido;
      });
    } else {
      // Segundo toque: desde el primero hasta este (en cualquier orden).
      final a = pendiente.isBefore(elegido) ? pendiente : elegido;
      final b = pendiente.isBefore(elegido) ? elegido : pendiente;
      _fijar(a, _finDeMes(b.year, b.month));
    }
  }

  Future<void> _diasExactos() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: _inicio, end: _fin),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => Center(
        // En pantallas grandes el calendario quedaba de pantalla completa.
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620), child: child),
      ),
    );
    if (r != null) _fijar(DateUtils.dateOnly(r.start), DateUtils.dateOnly(r.end));
  }

  bool _mesDentro(int mes) {
    final ini = DateTime(_anio, mes, 1);
    final fin = _finDeMes(_anio, mes);
    return !fin.isBefore(_inicio) && !ini.isAfter(_fin);
  }

  bool _mesCompleto(int mes) {
    final ini = DateTime(_anio, mes, 1);
    final fin = _finDeMes(_anio, mes);
    return !ini.isBefore(_inicio) && !fin.isAfter(_fin);
  }

  String get _resumen {
    final dias = _fin.difference(_inicio).inDays + 1;
    return "${_fecha(_inicio)}  →  ${_fecha(_fin)}  ·  $dias día${dias == 1 ? '' : 's'}";
  }

  @override
  Widget build(BuildContext context) {
    final acento = Theme.of(context).colorScheme.primary;
    final hoy = DateTime.now();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.date_range_rounded, color: acento),
                  const SizedBox(width: 8),
                  Expanded(child: Text("Elegí el período", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _cs.onSurface))),
                  IconButton(
                    tooltip: "Cerrar",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in _atajos)
                    ChoiceChip(
                      label: Text(a.$1),
                      selected: DateUtils.isSameDay(a.$2, _inicio) && DateUtils.isSameDay(a.$3, _fin),
                      onSelected: (_) => _fijar(a.$2, a.$3),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  IconButton(
                    tooltip: "Año anterior",
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => setState(() => _anio--),
                  ),
                  Expanded(
                    child: Text("$_anio", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _cs.onSurface)),
                  ),
                  IconButton(
                    tooltip: "Año siguiente",
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _anio >= hoy.year + 1 ? null : () => setState(() => _anio++),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
                children: [
                  for (var m = 1; m <= 12; m++)
                    _celdaMes(m, acento, esActual: _anio == hoy.year && m == hoy.month),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _mesPendiente != null
                    ? "Tocá otro mes para elegir de ${_mesesCortos[_mesPendiente!.month - 1].toLowerCase()} hasta ese."
                    : "Un toque elige el mes; otro toque, hasta qué mes.",
                style: TextStyle(fontSize: 11.5, color: _cs.onSurfaceVariant),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _diasExactos,
                  icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                  label: const Text("Elegir días exactos"),
                ),
              ),
              const Divider(height: 20),
              // Lo elegido y el botón, juntos.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: acento.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Text(_resumen, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: _cs.onSurface)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(context, DateTimeRange(start: _inicio, end: _fin)),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text("Aplicar", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _celdaMes(int mes, Color acento, {required bool esActual}) {
    final completo = _mesCompleto(mes);
    final parcial = !completo && _mesDentro(mes);
    final pendiente = _mesPendiente != null && _mesPendiente!.year == _anio && _mesPendiente!.month == mes;
    return Material(
      color: completo ? acento : (parcial ? acento.withValues(alpha: 0.18) : _cs.surfaceContainerHighest),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _tocarMes(mes),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: pendiente ? _cs.onSurface : (esActual && !completo ? acento : Colors.transparent),
              width: pendiente ? 2 : 1.2,
            ),
          ),
          child: Text(
            _mesesCortos[mes - 1],
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: completo ? Colors.white : _cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
