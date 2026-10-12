import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'recorridos.dart';
import 'widgets/recorrido_guiado.dart';
import 'theme/app_theme.dart';

/// Cierre de caja (gestion/caja.py): abrir con el fondo inicial, registrar
/// entradas y salidas de efectivo, y cerrar contando. Los cajeros cierran
/// "a ciegas": no ven cuánto debería haber hasta que cierran.
class CajaScreen extends StatefulWidget {
  final Negocio negocio;
  final String? rolEmpleado;
  const CajaScreen({super.key, required this.negocio, this.rolEmpleado});

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

const _nombresMedio = {'01': 'Efectivo', '02': 'Tarjeta', '06': 'SINPE Móvil', '04': 'Transferencia', '03': 'Cheque'};
const _iconosMedio = {
  '01': Icons.payments_outlined,
  '02': Icons.credit_card,
  '06': Icons.phone_iphone,
  '04': Icons.account_balance_outlined,
  '03': Icons.receipt_outlined,
};
const _billetes = [20000, 10000, 5000, 2000, 1000];
const _monedas = [500, 100, 50, 25, 10, 5];
const _ok = Color(0xFF16A34A), _falta = Color(0xFFDC2626), _sobra = Color(0xFFD97706);

double _n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;
String _hora(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  String dos(int x) => x.toString().padLeft(2, '0');
  return "${dos(d.day)}/${dos(d.month)} ${dos(d.hour)}:${dos(d.minute)}";
}

class _CajaScreenState extends State<CajaScreen> {
  Map<String, dynamic>? _datos;
  bool _cargando = true;
  final _fondoCtrl = TextEditingController();

  bool get _esCajero => widget.rolEmpleado == 'cajero';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/caja/actual/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200 && mounted) _datos = json.decode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
    if (mounted) ofrecerRecorrido(context, clave: GuiaCaja.clave, titulo: "funciona el cierre de caja", iniciar: () => GuiaCaja.mostrar(context));
  }

  Future<void> _abrir() async {
    final r = await ApiService.post('/caja/abrir/', {
      'negocio': widget.negocio.id,
      'fondo_inicial': _n(_fondoCtrl.text.replaceAll(',', '.')),
    });
    if (r.statusCode == 201) {
      _fondoCtrl.clear();
      _aviso("Caja abierta.");
    } else if (mounted) {
      _aviso(ApiService.mensajeError(r));
    }
    _cargar();
  }

  Future<void> _movimiento(String tipo) async {
    final monto = TextEditingController();
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tipo == 'entrada' ? "Entrada de efectivo" : "Salida de efectivo"),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: monto,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "Monto", prefixText: "₡ ", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: motivo,
              maxLength: 150,
              decoration: InputDecoration(
                labelText: "Motivo",
                hintText: tipo == 'entrada' ? "Ej: cambio, sencillo" : "Ej: compra de hielo, retiro para depositar",
                border: const OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ApiService.post('/caja/movimiento/', {
      'negocio': widget.negocio.id,
      'tipo': tipo,
      'monto': _n(monto.text.replaceAll(',', '.')),
      'motivo': motivo.text.trim(),
    });
    if (r.statusCode != 201 && mounted) _aviso(ApiService.mensajeError(r));
    _cargar();
  }

  Future<void> _cerrar() async {
    final resultado = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => _ConteoCaja(negocio: widget.negocio)),
    );
    if (resultado == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ResultadoCierre(negocio: widget.negocio, turno: resultado)));
    _cargar();
  }

  Future<void> _historial() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _HistorialCaja(negocio: widget.negocio)));
  }

  Widget _tarjeta({required Widget child, EdgeInsets? margen}) => Container(
        margin: margen ?? const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: child,
      );

  Widget _cerrada() {
    final ultimo = _datos?['ultimo_cierre'] as Map<String, dynamic>?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tarjeta(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lock_outline, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text("La caja está cerrada", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textStrong)),
          ]),
          const SizedBox(height: 6),
          Text("Abrila al empezar el turno con el dinero que hay en la gaveta para dar cambio.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                key: GuiaCaja.fondo,
                controller: _fondoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: "Fondo inicial", prefixText: "₡ ", isDense: true, border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(onPressed: _abrir, icon: const Icon(Icons.lock_open, size: 18), label: const Text("Abrir caja")),
          ]),
        ]),
      ),
      if (ultimo != null)
        _tarjeta(
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultadoCierre(negocio: widget.negocio, turno: ultimo))),
            child: Row(children: [
              Icon(Icons.history, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Último cierre: ${_hora(ultimo['cerrado_en'])}", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                  Text("por ${ultimo['cerrado_por']}", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ]),
              ),
              _chipDiferencia(_n((ultimo['diferencias'] as Map?)?['01'])),
            ]),
          ),
        ),
    ]);
  }

  Widget _abierta(Map<String, dynamic> t) {
    final resumen = t['resumen'] as Map<String, dynamic>?;
    final movs = (t['movimientos'] as List).cast<Map<String, dynamic>>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tarjeta(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.point_of_sale, color: _ok),
            const SizedBox(width: 8),
            Expanded(child: Text("Caja abierta", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textStrong))),
            Text(_hora(t['abierto_en']), style: TextStyle(color: AppColors.textMuted)),
          ]),
          const SizedBox(height: 4),
          Text("Abrió ${t['abierto_por']} con ${formatearColones(_n(t['fondo_inicial']), decimales: 0)} de fondo",
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 14),
          Wrap(key: GuiaCaja.movimientos, spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _movimiento('entrada'), icon: const Icon(Icons.add, size: 18), label: const Text("Entrada de efectivo")),
            OutlinedButton.icon(onPressed: () => _movimiento('salida'), icon: const Icon(Icons.remove, size: 18), label: const Text("Salida de efectivo")),
            FilledButton.icon(key: GuiaCaja.cerrar, onPressed: _cerrar, icon: const Icon(Icons.lock, size: 18), label: const Text("Cerrar caja")),
          ]),
        ]),
      ),
      if (resumen != null)
        _tarjeta(
          child: Column(key: GuiaCaja.resumen, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Debería haber en este momento", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            const SizedBox(height: 4),
            Text("${resumen['cantidad_ventas']} ventas de contado por ${formatearColones(_n(resumen['total_ventas']), decimales: 0)}"
                "${_n(resumen['total_propinas']) > 0 ? ' · propinas ${formatearColones(_n(resumen['total_propinas']), decimales: 0)}' : ''}",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 10),
            for (final m in _nombresMedio.keys)
              if (_n((resumen['esperado'] as Map)[m]) != 0 || m == '01')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(_iconosMedio[m], size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_nombresMedio[m]!, style: TextStyle(color: AppColors.textStrong))),
                    Text(formatearColones(_n((resumen['esperado'] as Map)[m]), decimales: 0),
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                  ]),
                ),
          ]),
        )
      else
        _tarjeta(
          child: Row(children: [
            Icon(Icons.visibility_off_outlined, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text("Al cerrar vas a contar el dinero sin ver cuánto debería haber; el resultado sale cuando cerrás.",
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ]),
        ),
      if (movs.isNotEmpty)
        _tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Entradas y salidas", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            const SizedBox(height: 6),
            for (final m in movs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(m['tipo'] == 'entrada' ? Icons.south_west : Icons.north_east, color: m['tipo'] == 'entrada' ? _ok : _falta),
                title: Text(m['motivo'], style: TextStyle(color: AppColors.textStrong)),
                subtitle: Text("${m['usuario']} · ${_hora(m['fecha'])}", style: TextStyle(color: AppColors.textMuted)),
                trailing: Text("${m['tipo'] == 'entrada' ? '+' : '−'}${formatearColones(_n(m['monto']), decimales: 0)}",
                    style: TextStyle(fontWeight: FontWeight.w700, color: m['tipo'] == 'entrada' ? _ok : _falta)),
              ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final turno = _datos?['turno'] as Map<String, dynamic>?;
    return Container(
      color: AppColors.surfaceSubtle,
      child: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    Icon(Icons.point_of_sale, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text("Caja", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                    if (!_esCajero)
                      TextButton.icon(key: GuiaCaja.historial, onPressed: _historial, icon: const Icon(Icons.history, size: 18), label: const Text("Historial")),
                    IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh), tooltip: "Actualizar"),
                    BotonGuia(iniciar: () => GuiaCaja.mostrar(context)),
                  ]),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: turno == null ? _cerrada() : _abierta(turno),
                  ),
                ],
              ),
            ),
    );
  }
}

Widget _chipDiferencia(double d) {
  final (texto, color) = d.abs() < 0.5 ? ("Cuadra", _ok) : (d < 0 ? ("Faltan ${formatearColones(-d, decimales: 0)}", _falta) : ("Sobran ${formatearColones(d, decimales: 0)}", _sobra));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
    child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
  );
}

// ------------------------------------------------------------------ Conteo

class _ConteoCaja extends StatefulWidget {
  final Negocio negocio;
  const _ConteoCaja({required this.negocio});

  @override
  State<_ConteoCaja> createState() => _ConteoCajaState();
}

class _ConteoCajaState extends State<_ConteoCaja> {
  final Map<int, TextEditingController> _ctrls = {for (final d in [..._billetes, ..._monedas]) d: TextEditingController()};
  final _otros = {for (final m in ['02', '06', '04', '03']) m: TextEditingController()};
  final _notas = TextEditingController();
  bool _enviando = false;

  int _cantidad(int valor) => int.tryParse(_ctrls[valor]!.text) ?? 0;
  double get _efectivo => _ctrls.keys.fold(0.0, (s, v) => s + v * _cantidad(v));

  void _poner(int valor, int cantidad) => setState(() => _ctrls[valor]!.text = cantidad <= 0 ? '' : '$cantidad');

  Future<void> _confirmar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Cerrar la caja?"),
        content: Text("Efectivo contado: ${formatearColones(_efectivo, decimales: 0)}. Después de cerrar ya no se puede cambiar."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Revisar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Cerrar caja")),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _enviando = true);
    final r = await ApiService.post('/caja/cerrar/', {
      'negocio': widget.negocio.id,
      'contado': {
        '01': _efectivo,
        for (final e in _otros.entries) e.key: _n(e.value.text.replaceAll(',', '.')),
      },
      'notas': _notas.text.trim(),
    });
    if (!mounted) return;
    if (r.statusCode == 200) {
      Navigator.pop(context, json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } else {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.mensajeError(r))));
    }
  }

  Widget _fila(int valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 90, child: Text(formatearColones(valor, decimales: 0), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong))),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _cantidad(valor) > 0 ? () => _poner(valor, _cantidad(valor) - 1) : null,
          ),
          SizedBox(
            width: 60,
            child: TextField(
              controller: _ctrls[valor],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(isDense: true, hintText: '0', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _poner(valor, _cantidad(valor) + 1),
          ),
          const Spacer(),
          Text(formatearColones(valor * _cantidad(valor), decimales: 0), style: TextStyle(color: AppColors.textMuted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(title: const Text("Cerrar caja")),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text("1. Contá el efectivo de la gaveta", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textStrong)),
              const SizedBox(height: 4),
              Text("Cuántos billetes y monedas hay de cada uno (incluido el fondo inicial).", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Text("Billetes", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 12.5)),
              for (final b in _billetes) _fila(b),
              const SizedBox(height: 8),
              Text("Monedas", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 12.5)),
              for (final m in _monedas) _fila(m),
              const Divider(height: 24),
              Row(children: [
                Text("Efectivo contado", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                const Spacer(),
                Text(formatearColones(_efectivo, decimales: 0), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary)),
              ]),
              const SizedBox(height: 22),
              Text("2. Los otros medios", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textStrong)),
              const SizedBox(height: 4),
              Text("El total del cierre del datáfono, lo recibido por SINPE Móvil, etc. Dejalo vacío si no hubo.",
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              for (final e in _otros.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: e.value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _nombresMedio[e.key],
                      prefixIcon: Icon(_iconosMedio[e.key], size: 20),
                      prefixText: "₡ ",
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(controller: _notas, maxLength: 300, maxLines: 2,
                  decoration: const InputDecoration(labelText: "Notas (opcional)", border: OutlineInputBorder())),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _enviando ? null : _confirmar,
                icon: const Icon(Icons.lock),
                label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text("Cerrar caja")),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Resultado

class ResultadoCierre extends StatelessWidget {
  final Negocio negocio;
  final Map<String, dynamic> turno;
  const ResultadoCierre({super.key, required this.negocio, required this.turno});

  Map get _esperado => (turno['esperado'] as Map?) ?? {};
  Map get _contado => (turno['contado'] as Map?) ?? {};
  Map get _resumen => (turno['resumen'] as Map?) ?? {};

  List<String> get _medios => [
        for (final m in _nombresMedio.keys)
          if (m == '01' || _n(_esperado[m]) != 0 || _n(_contado[m]) != 0) m,
      ];

  Future<void> _imprimir() async {
    final doc = pw.Document();
    String c(double v) => "CRC ${formatearNumero(v, decimales: 0)}";
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(negocio.nombreComercial, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text("CIERRE DE CAJA", style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.Text("Abrió: ${turno['abierto_por']} ${_hora(turno['abierto_en'])}", style: const pw.TextStyle(fontSize: 9)),
        pw.Text("Cerró: ${turno['cerrado_por']} ${_hora(turno['cerrado_en'])}", style: const pw.TextStyle(fontSize: 9)),
        pw.Divider(),
        pw.Text("Ventas de contado: ${_resumen['cantidad_ventas'] ?? 0} por ${c(_n(_resumen['total_ventas']))}", style: const pw.TextStyle(fontSize: 9)),
        if (_n(_resumen['total_propinas']) > 0) pw.Text("Propinas: ${c(_n(_resumen['total_propinas']))}", style: const pw.TextStyle(fontSize: 9)),
        pw.Text("Fondo inicial: ${c(_n(turno['fondo_inicial']))}", style: const pw.TextStyle(fontSize: 9)),
        if (_n(_resumen['entradas']) > 0) pw.Text("Entradas: ${c(_n(_resumen['entradas']))}", style: const pw.TextStyle(fontSize: 9)),
        if (_n(_resumen['salidas']) > 0) pw.Text("Salidas: ${c(_n(_resumen['salidas']))}", style: const pw.TextStyle(fontSize: 9)),
        pw.Divider(),
        for (final m in _medios) ...[
          pw.Text(_nombresMedio[m]!, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text("  Esperado: ${c(_n(_esperado[m]))}", style: const pw.TextStyle(fontSize: 10)),
          pw.Text("  Contado:  ${c(_n(_contado[m]))}", style: const pw.TextStyle(fontSize: 10)),
          pw.Text("  Diferencia: ${c(_n(_contado[m]) - _n(_esperado[m]))}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
        ],
        if ((turno['notas'] ?? '').toString().isNotEmpty) ...[pw.Divider(), pw.Text("Notas: ${turno['notas']}", style: const pw.TextStyle(fontSize: 9))],
        pw.SizedBox(height: 24),
        pw.Text("Firma: ______________________", style: const pw.TextStyle(fontSize: 10)),
      ]),
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'Cierre_caja_${_hora(turno['cerrado_en']).replaceAll(RegExp(r'[^0-9]'), '')}');
  }

  @override
  Widget build(BuildContext context) {
    final difEfectivo = _n(_contado['01']) - _n(_esperado['01']);
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(
        title: const Text("Resultado del cierre"),
        actions: [IconButton(tooltip: "Imprimir", icon: const Icon(Icons.print_outlined), onPressed: _imprimir)],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: (difEfectivo.abs() < 0.5 ? _ok : (difEfectivo < 0 ? _falta : _sobra)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  Icon(difEfectivo.abs() < 0.5 ? Icons.check_circle : Icons.error_outline, size: 40,
                      color: difEfectivo.abs() < 0.5 ? _ok : (difEfectivo < 0 ? _falta : _sobra)),
                  const SizedBox(height: 6),
                  Text(
                    difEfectivo.abs() < 0.5
                        ? "El efectivo cuadra"
                        : (difEfectivo < 0 ? "Faltan ${formatearColones(-difEfectivo, decimales: 0)} en efectivo" : "Sobran ${formatearColones(difEfectivo, decimales: 0)} en efectivo"),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textStrong),
                  ),
                  const SizedBox(height: 4),
                  Text("${turno['cerrado_por']} · ${_hora(turno['cerrado_en'])}", style: TextStyle(color: AppColors.textMuted)),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  Row(children: [
                    const Expanded(flex: 3, child: SizedBox()),
                    for (final h in ["Esperado", "Contado", "Diferencia"])
                      Expanded(flex: 3, child: Text(h, textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
                  ]),
                  const Divider(),
                  for (final m in _medios)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text(_nombresMedio[m]!, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textStrong))),
                        Expanded(flex: 3, child: Text(formatearColones(_n(_esperado[m]), decimales: 0), textAlign: TextAlign.right, style: TextStyle(color: AppColors.textStrong))),
                        Expanded(flex: 3, child: Text(formatearColones(_n(_contado[m]), decimales: 0), textAlign: TextAlign.right, style: TextStyle(color: AppColors.textStrong))),
                        Expanded(
                          flex: 3,
                          child: Builder(builder: (_) {
                            final d = _n(_contado[m]) - _n(_esperado[m]);
                            return Text(d.abs() < 0.5 ? "✓" : "${d > 0 ? '+' : '−'}${formatearColones(d.abs(), decimales: 0)}",
                                textAlign: TextAlign.right,
                                style: TextStyle(fontWeight: FontWeight.w800, color: d.abs() < 0.5 ? _ok : (d < 0 ? _falta : _sobra)));
                          }),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              Text(
                "${_resumen['cantidad_ventas'] ?? 0} ventas de contado por ${formatearColones(_n(_resumen['total_ventas']), decimales: 0)}"
                "${_n(_resumen['total_propinas']) > 0 ? ' · propinas ${formatearColones(_n(_resumen['total_propinas']), decimales: 0)}' : ''}"
                " · fondo inicial ${formatearColones(_n(turno['fondo_inicial']), decimales: 0)}",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              if ((turno['notas'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text("Notas: ${turno['notas']}", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: _imprimir, icon: const Icon(Icons.print_outlined), label: const Text("Imprimir cierre")),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Historial

class _HistorialCaja extends StatefulWidget {
  final Negocio negocio;
  const _HistorialCaja({required this.negocio});

  @override
  State<_HistorialCaja> createState() => _HistorialCajaState();
}

class _HistorialCajaState extends State<_HistorialCaja> {
  List<Map<String, dynamic>>? _filas;

  @override
  void initState() {
    super.initState();
    ApiService.get('/caja/turnos/?negocio=${widget.negocio.id}').then((r) {
      if (r.statusCode == 200 && mounted) setState(() => _filas = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>());
    }).catchError((_) {});
  }

  Future<void> _abrir(int id) async {
    final r = await ApiService.get('/caja/turnos/$id/');
    if (r.statusCode != 200 || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ResultadoCierre(negocio: widget.negocio, turno: json.decode(utf8.decode(r.bodyBytes)))));
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(title: const Text("Cierres de caja")),
      body: filas == null
          ? const Center(child: CircularProgressIndicator())
          : filas.isEmpty
              ? Center(child: Text("Todavía no hay cierres.", style: TextStyle(color: AppColors.textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final f = filas[i];
                    return Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.border)),
                        onTap: () => _abrir(f['id'] as int),
                        leading: const Icon(Icons.point_of_sale),
                        title: Text("${_hora(f['abierto_en'])} → ${_hora(f['cerrado_en'])}", style: TextStyle(color: AppColors.textStrong)),
                        subtitle: Text("${f['cerrado_por']} · ventas ${formatearColones(_n(f['total_ventas']), decimales: 0)}",
                            style: TextStyle(color: AppColors.textMuted)),
                        trailing: _chipDiferencia(_n(f['diferencia_efectivo'])),
                      ),
                    );
                  },
                ),
    );
  }
}
