import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';

/// Balance General y Estado de Resultados de un negocio -- se calculan del
/// lado del backend a partir de los Asientos Contables ya cargados (ver
/// EstadosFinancierosView), no hay nada que capturar acá, solo elegir el
/// periodo y mostrar el resultado.
class EstadosFinancierosScreen extends StatefulWidget {
  final int negocioId;
  final String negocioNombre;

  const EstadosFinancierosScreen({super.key, required this.negocioId, required this.negocioNombre});

  @override
  State<EstadosFinancierosScreen> createState() => _EstadosFinancierosScreenState();
}

class _EstadosFinancierosScreenState extends State<EstadosFinancierosScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _datos;
  late DateTime _fechaInicio;
  late DateTime _fechaCorte;

  bool _analizando = false;
  String? _analisis;
  String? _errorAnalisis;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, 1, 1);
    _fechaCorte = ahora;
    _cargar();
  }

  String get _queryPeriodo {
    final fi = _fechaInicio.toIso8601String().split('T').first;
    final fc = _fechaCorte.toIso8601String().split('T').first;
    return 'negocio=${widget.negocioId}&fecha_inicio=$fi&fecha_corte=$fc';
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      // Un análisis viejo corresponde a un periodo distinto una vez que se
      // cambian las fechas -- se descarta para no confundir al contador.
      _analisis = null;
      _errorAnalisis = null;
    });
    try {
      final r = await ApiService.get('/estados-financieros/?$_queryPeriodo');
      if (r.statusCode == 200) {
        if (mounted) setState(() => _datos = json.decode(utf8.decode(r.bodyBytes)));
      } else if (mounted) {
        setState(() => _error = "No se pudo cargar (HTTP ${r.statusCode}).");
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Error: $e");
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _analizarConIA() async {
    setState(() {
      _analizando = true;
      _errorAnalisis = null;
    });
    try {
      final r = await ApiService.post('/estados-financieros/?$_queryPeriodo', {});
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes));
        if (mounted) setState(() => _analisis = data['analisis'] ?? '');
      } else {
        final data = json.decode(utf8.decode(r.bodyBytes));
        if (mounted) setState(() => _errorAnalisis = data['detail']?.toString() ?? "No se pudo generar el análisis (HTTP ${r.statusCode}).");
      }
    } catch (e) {
      if (mounted) setState(() => _errorAnalisis = "No se pudo generar el análisis: $e");
    }
    if (mounted) setState(() => _analizando = false);
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: esInicio ? _fechaInicio : _fechaCorte,
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (elegida == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = elegida;
      } else {
        _fechaCorte = elegida;
      }
    });
    _cargar();
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  String _monto(dynamic v) {
    final n = _num(v);
    final signo = n < 0 ? '-' : '';
    return '$signo₡${n.abs().toStringAsFixed(2)}';
  }

  Widget _fechaChip({required String etiqueta, required DateTime fecha, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(10), border: Border.all(color: TemaContador.borde)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 14, color: TemaContador.acento),
            const SizedBox(width: 8),
            Text("$etiqueta: ${fecha.day}/${fecha.month}/${fecha.year}", style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _alertaBanner({required String nivel, required String mensaje}) {
    final Color color = switch (nivel) {
      'alerta' => Colors.red,
      'aviso' => Colors.orange,
      _ => TemaContador.acento,
    };
    final IconData icono = switch (nivel) {
      'alerta' => Icons.error_outline,
      'aviso' => Icons.warning_amber_rounded,
      _ => Icons.info_outline,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 12.5))),
        ],
      ),
    );
  }

  Widget _indicador(String etiqueta, dynamic valor, {bool esPorcentaje = false}) {
    final n = valor == null ? null : _num(valor);
    final texto = n == null ? '—' : (esPorcentaje ? '${(n * 100).toStringAsFixed(1)}%' : n.toStringAsFixed(2));
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(texto, style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  String _fechaCorta(dynamic iso) {
    final f = DateTime.tryParse(iso?.toString() ?? '');
    if (f == null) return '—';
    return "${f.day}/${f.month}/${f.year}";
  }

  Widget _filaComparacion(String etiqueta, dynamic actual, dynamic anterior, dynamic variacionPct) {
    final variacion = variacionPct == null ? null : _num(variacionPct);
    final subiendo = variacion != null && variacion >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(flex: 2, child: Text(etiqueta, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13))),
          Expanded(flex: 2, child: Text(_monto(actual), style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13), textAlign: TextAlign.right)),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text("vs. ${_monto(anterior)}", style: const TextStyle(color: TemaContador.textoTenue, fontSize: 11.5)),
                const SizedBox(width: 6),
                if (variacion != null) ...[
                  Icon(subiendo ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: subiendo ? Colors.green : Colors.red),
                  Text("${variacion.abs().toStringAsFixed(1)}%", style: TextStyle(color: subiendo ? Colors.green.shade800 : Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                ] else
                  const Text("n/d", style: TextStyle(color: TemaContador.textoTenue, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta({required String titulo, required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: TemaContador.fondo, borderRadius: BorderRadius.circular(14), border: Border.all(color: TemaContador.borde)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: TemaContador.textoFuerte)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _seccion(String titulo, List<dynamic> filas, double total, {bool esNegativoParaTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: TemaContador.acento, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          if (filas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text("Sin movimientos.", style: TextStyle(color: TemaContador.textoTenue, fontSize: 12.5)),
            )
          else
            ...filas.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text("${f['codigo']} · ${f['nombre']}", style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13), overflow: TextOverflow.ellipsis)),
                      Text(_monto(f['saldo']), style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13)),
                    ],
                  ),
                )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total $titulo", style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 13)),
              Text(_monto(total), style: TextStyle(color: esNegativoParaTotal && total < 0 ? Colors.red : TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = _datos?['balance_general'] as Map<String, dynamic>?;
    final er = _datos?['estado_resultados'] as Map<String, dynamic>?;
    final ratios = _datos?['ratios'] as Map<String, dynamic>?;
    final alertas = (_datos?['alertas'] as List?) ?? [];
    final comparacion = _datos?['comparacion_periodo_anterior'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: const Text("Estados Financieros", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.negocioNombre, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _fechaChip(etiqueta: "Desde", fecha: _fechaInicio, onTap: () => _elegirFecha(esInicio: true)),
                          _fechaChip(etiqueta: "Corte", fecha: _fechaCorte, onTap: () => _elegirFecha(esInicio: false)),
                        ],
                      ),
                      if (alertas.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        ...alertas.map((a) => _alertaBanner(nivel: a['nivel'], mensaje: a['mensaje'])),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _analizando ? null : _analizarConIA,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TemaContador.acento,
                            disabledForegroundColor: TemaContador.textoTenue,
                            side: const BorderSide(color: TemaContador.acento),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: _analizando
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_awesome_outlined),
                          label: Text(_analizando ? "Analizando con IA..." : "Analizar con IA"),
                        ),
                      ),
                      if (_errorAnalisis != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_errorAnalisis!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                        ),
                      if (_analisis != null && _analisis!.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: TemaContador.acento.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: TemaContador.acento.withOpacity(0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.auto_awesome_outlined, color: TemaContador.acento, size: 18),
                                  SizedBox(width: 8),
                                  Text("Análisis con IA", style: TextStyle(color: TemaContador.acento, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(_analisis!, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13.5, height: 1.4)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (ratios != null)
                        _tarjeta(
                          titulo: "Indicadores financieros",
                          child: Wrap(
                            spacing: 24,
                            runSpacing: 14,
                            children: [
                              _indicador("Endeudamiento", ratios['endeudamiento'], esPorcentaje: true),
                              _indicador("Apalancamiento", ratios['apalancamiento'], esPorcentaje: true),
                              _indicador("Margen bruto", ratios['margen_bruto'], esPorcentaje: true),
                              _indicador("Margen neto", ratios['margen_neto'], esPorcentaje: true),
                              _indicador("ROA", ratios['roa'], esPorcentaje: true),
                              _indicador("ROE", ratios['roe'], esPorcentaje: true),
                            ],
                          ),
                        ),
                      if (comparacion != null)
                        _tarjeta(
                          titulo: "Comparación con el periodo anterior",
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Periodo anterior: ${_fechaCorta(comparacion['fecha_inicio_anterior'])} - ${_fechaCorta(comparacion['fecha_corte_anterior'])}",
                                style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12),
                              ),
                              const SizedBox(height: 10),
                              _filaComparacion("Ingresos", er?['total_ingresos'], comparacion['total_ingresos_anterior'], comparacion['variacion_ingresos_pct']),
                              _filaComparacion("Utilidad neta", er?['utilidad_neta'], comparacion['utilidad_neta_anterior'], comparacion['variacion_utilidad_pct']),
                              _filaComparacion("Activo total", bg?['total_activo'], comparacion['total_activo_anterior'], comparacion['variacion_activo_pct']),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (er != null)
                        _tarjeta(
                          titulo: "Estado de Resultados (${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} - ${_fechaCorte.day}/${_fechaCorte.month}/${_fechaCorte.year})",
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _seccion("Ingresos", er['ingresos'], _num(er['total_ingresos'])),
                              _seccion("Costos", er['costos'], _num(er['total_costos'])),
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Utilidad bruta", style: TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w700, fontSize: 13.5)),
                                    Text(_monto(er['utilidad_bruta']), style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w700, fontSize: 13.5)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              _seccion("Gastos", er['gastos'], _num(er['total_gastos'])),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: (_num(er['utilidad_neta']) >= 0 ? Colors.green : Colors.red).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Utilidad neta", style: TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 15)),
                                    Text(
                                      _monto(er['utilidad_neta']),
                                      style: TextStyle(color: _num(er['utilidad_neta']) >= 0 ? Colors.green.shade800 : Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (bg != null)
                        _tarjeta(
                          titulo: "Balance General (al ${_fechaCorte.day}/${_fechaCorte.month}/${_fechaCorte.year})",
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _seccion("Activo", bg['activo'], _num(bg['total_activo'])),
                              _seccion("Pasivo", bg['pasivo'], _num(bg['total_pasivo'])),
                              Text("Patrimonio", style: const TextStyle(color: TemaContador.acento, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 6),
                              if ((bg['patrimonio'] as List).isEmpty)
                                const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text("Sin movimientos.", style: TextStyle(color: TemaContador.textoTenue, fontSize: 12.5)))
                              else
                                ...(bg['patrimonio'] as List).map((f) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text("${f['codigo']} · ${f['nombre']}", style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                          Text(_monto(f['saldo']), style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13)),
                                        ],
                                      ),
                                    )),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Resultado del periodo", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 13, fontStyle: FontStyle.italic)),
                                    Text(_monto(bg['resultado_periodo']), style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13, fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Total Patrimonio", style: TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(_monto(bg['total_patrimonio']), style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: (bg['cuadra'] == true ? Colors.green : Colors.orange).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: bg['cuadra'] == true ? Colors.green : Colors.orange),
                                ),
                                child: Row(
                                  children: [
                                    Icon(bg['cuadra'] == true ? Icons.check_circle : Icons.warning_amber_rounded, color: bg['cuadra'] == true ? Colors.green : Colors.orange, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Activo: ${_monto(bg['total_activo'])}   =   Pasivo + Patrimonio: ${_monto(bg['total_pasivo_patrimonio'])}",
                                            style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w600, fontSize: 12.5),
                                          ),
                                          if (bg['cuadra'] != true)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 4),
                                              child: Text(
                                                "El balance no cuadra -- revisá que todos los asientos estén completos y balanceados.",
                                                style: TextStyle(color: TemaContador.textoTenue, fontSize: 11.5),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
