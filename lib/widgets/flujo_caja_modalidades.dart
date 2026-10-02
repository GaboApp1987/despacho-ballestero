import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme/app_theme.dart';

/// Flujo de caja proyectado en dos modalidades (ver gestion/flujo_caja.py en
/// el backend):
/// - "nueva": empresa nueva / proyecto -- inversión inicial, financiamiento,
///   curva de arranque de ventas; indicadores de proyecto (VAN, TIR,
///   recuperación, punto de equilibrio).
/// - "existente": empresa en marcha -- parte de la historia real de ventas
///   (importable desde Equilibra), saldos por cobrar/pagar y deudas vigentes.
///
/// [EditorParametrosFlujo] arma el mapa `parametros` que espera el backend;
/// [VistaPreviaFlujo] muestra el estado calculado por /calcular/.

const Color _rojo = Color(0xFFB91C1C);
const Color _verde = Color(0xFF15803D);

String formatoMonto(double v, String simbolo) {
  final negativo = v < 0;
  final entero = v.abs().round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buf.write(',');
    buf.write(entero[i]);
  }
  return "${negativo ? '-' : ''}$simbolo$buf";
}

String _cifra(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  if (d.abs() < 0.5) return '-';
  final t = formatoMonto(d.abs(), '');
  return d < 0 ? '($t)' : t;
}

double _num(String texto) => double.tryParse(texto.replaceAll(',', '').replaceAll(' ', '').trim()) ?? 0;

String _textoInicial(dynamic v) {
  if (v == null) return '';
  if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  return v.toString();
}

/// Un campo de una fila de lista (ej. préstamo: nombre, monto, tasa...).
class _Campo {
  final String clave;
  final String etiqueta;
  final bool numerico;
  final int flex;
  final String? sugerencia;
  const _Campo(this.clave, this.etiqueta, {this.numerico = true, this.flex = 2, this.sugerencia});
}

class EditorParametrosFlujo extends StatefulWidget {
  final String tipo; // 'nueva' | 'existente'
  final Map<String, dynamic> parametros;
  final int? negocioId;
  final String simbolo;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const EditorParametrosFlujo({
    super.key,
    required this.tipo,
    required this.parametros,
    required this.onChanged,
    this.negocioId,
    this.simbolo = '₡',
  });

  @override
  State<EditorParametrosFlujo> createState() => EditorParametrosFlujoState();
}

class EditorParametrosFlujoState extends State<EditorParametrosFlujo> {
  final Map<String, TextEditingController> _campos = {};
  final Map<String, bool> _interruptores = {};
  final Map<String, List<Map<String, TextEditingController>>> _listas = {};
  // Historia de ventas (empresa en marcha): 12 meses con etiqueta.
  List<Map<String, dynamic>> _historico = [];
  final List<TextEditingController> _historicoCtrls = [];
  bool _importando = false;
  String? _avisoImportacion;

  static const Map<String, List<_Campo>> _especListas = {
    'inversiones': [_Campo('concepto', 'Concepto', numerico: false, flex: 4, sugerencia: 'Ej. Equipo, mobiliario, local'), _Campo('monto', 'Monto', flex: 3)],
    'inversiones_plan': [_Campo('concepto', 'Concepto', numerico: false, flex: 4, sugerencia: 'Ej. Vehículo nuevo'), _Campo('mes', 'Mes (1-12)', flex: 2), _Campo('monto', 'Monto', flex: 3)],
    'preoperativos': [_Campo('concepto', 'Concepto', numerico: false, flex: 4, sugerencia: 'Ej. Permisos, patente, publicidad de apertura'), _Campo('monto', 'Monto', flex: 3)],
    'aportes': [_Campo('concepto', 'Quién aporta', numerico: false, flex: 4, sugerencia: 'Ej. Socios'), _Campo('monto', 'Monto', flex: 3)],
    'prestamos_nuevos': [
      _Campo('nombre', 'Entidad', numerico: false, flex: 3, sugerencia: 'Ej. Banco Nacional'),
      _Campo('monto', 'Monto', flex: 3),
      _Campo('tasa_anual', 'Tasa %', flex: 2),
      _Campo('plazo_meses', 'Plazo (meses)', flex: 2),
      _Campo('meses_gracia', 'Gracia', flex: 2),
      _Campo('mes_desembolso', 'Mes desemb.', flex: 2),
    ],
    'deudas_existentes': [
      _Campo('nombre', 'Acreedor', numerico: false, flex: 4, sugerencia: 'Ej. BCR préstamo vehículo'),
      _Campo('cuota_mensual', 'Cuota mensual', flex: 3),
      _Campo('meses_restantes', 'Meses que faltan', flex: 2),
    ],
    'gastos_fijos': [
      _Campo('concepto', 'Concepto', numerico: false, flex: 4, sugerencia: 'Ej. Alquiler, electricidad, internet'),
      _Campo('monto', 'Monto mensual', flex: 3),
      _Campo('inflacion_anual_pct', 'Aumento anual %', flex: 2),
    ],
  };

  bool get _nueva => widget.tipo == 'nueva';

  @override
  void initState() {
    super.initState();
    final p = widget.parametros;
    _iniciarDefaults(p);
    final hist = ((p['ventas'] as Map?)?['historico'] as List?) ?? [];
    _cargarHistorico(hist.map((h) => Map<String, dynamic>.from(h as Map)).toList());
    // Avisa el mapa inicial para que la vista previa arranque de una vez.
    WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
  }

  dynamic _leer(Map<String, dynamic> p, String ruta) {
    dynamic actual = p;
    for (final parte in ruta.split('.')) {
      if (actual is Map && actual.containsKey(parte)) {
        actual = actual[parte];
      } else {
        return null;
      }
    }
    return actual;
  }

  void _campo(Map<String, dynamic> p, String ruta, dynamic defecto) {
    _campos[ruta] = TextEditingController(text: _textoInicial(_leer(p, ruta) ?? defecto));
  }

  void _iniciarDefaults(Map<String, dynamic> p) {
    if (_nueva) {
      _campo(p, 'anios', 3);
      _campo(p, 'ventas.mes1', '');
      _campo(p, 'ventas.crecimiento_rampa_pct', 10);
      _campo(p, 'ventas.meses_rampa', 6);
      _campo(p, 'ventas.crecimiento_mensual_pct', 1);
      _campo(p, 'tasa_descuento_anual', 15);
    } else {
      _campo(p, 'ventas.crecimiento_anual_pct', 5);
      _campo(p, 'ventas.base_mensual', '');
      _interruptores['ventas.usar_estacionalidad'] = (_leer(p, 'ventas.usar_estacionalidad') ?? true) == true;
      _campo(p, 'cxc_inicial', '');
      _campo(p, 'cxp_inicial', '');
    }
    _campo(p, 'costo_ventas_pct', 40);
    _campo(p, 'cobro.contado', _nueva ? 100 : 70);
    _campo(p, 'cobro.d30', _nueva ? 0 : 30);
    _campo(p, 'cobro.d60', 0);
    _campo(p, 'pago_proveedores.contado', 100);
    _campo(p, 'pago_proveedores.d30', 0);
    _campo(p, 'planilla.salarios_mensuales', '');
    _campo(p, 'planilla.cargas_sociales_pct', 26.67);
    _campo(p, 'planilla.aumento_anual_pct', 0);
    _interruptores['planilla.aguinaldo'] = (_leer(p, 'planilla.aguinaldo') ?? true) == true;
    _interruptores['iva.aplica'] = (_leer(p, 'iva.aplica') ?? true) == true;
    _campo(p, 'iva.ventas_gravadas_pct', 100);
    _campo(p, 'iva.compras_gravadas_pct', 100);
    _campo(p, 'renta.tasa_efectiva', 0);
    _campo(p, 'escenarios_variacion_pct', 15);

    for (final clave in _especListas.keys) {
      final origen = clave == 'inversiones_plan' ? 'inversiones' : clave;
      if (_nueva && ['deudas_existentes', 'inversiones_plan'].contains(clave)) continue;
      if (!_nueva && ['inversiones', 'preoperativos', 'aportes'].contains(clave)) continue;
      final filas = (p[origen] as List?) ?? [];
      _listas[clave] = filas.map((f) => _nuevaFila(clave, Map<String, dynamic>.from(f as Map))).toList();
    }
  }

  Map<String, TextEditingController> _nuevaFila(String lista, [Map<String, dynamic>? valores]) => {
        for (final c in _especListas[lista]!) c.clave: TextEditingController(text: _textoInicial(valores?[c.clave])),
      };

  void _cargarHistorico(List<Map<String, dynamic>> filas) {
    for (final c in _historicoCtrls) {
      c.dispose();
    }
    _historicoCtrls.clear();
    _historico = filas;
    for (final h in filas) {
      _historicoCtrls.add(TextEditingController(text: _textoInicial(h['ventas'])));
    }
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    for (final filas in _listas.values) {
      for (final f in filas) {
        for (final c in f.values) {
          c.dispose();
        }
      }
    }
    for (final c in _historicoCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _poner(Map<String, dynamic> destino, String ruta, dynamic valor) {
    final partes = ruta.split('.');
    Map<String, dynamic> actual = destino;
    for (final parte in partes.sublist(0, partes.length - 1)) {
      actual = (actual[parte] ??= <String, dynamic>{}) as Map<String, dynamic>;
    }
    actual[partes.last] = valor;
  }

  /// El mapa `parametros` tal como lo espera el backend.
  Map<String, dynamic> parametros() {
    final p = <String, dynamic>{};
    _campos.forEach((ruta, c) {
      if (c.text.trim().isEmpty) return;
      _poner(p, ruta, _num(c.text));
    });
    _interruptores.forEach((ruta, v) => _poner(p, ruta, v));
    _listas.forEach((clave, filas) {
      final destino = clave == 'inversiones_plan' ? 'inversiones' : clave;
      final lista = <Map<String, dynamic>>[];
      for (final f in filas) {
        if (f.values.every((c) => c.text.trim().isEmpty)) continue;
        final fila = <String, dynamic>{};
        for (final campo in _especListas[clave]!) {
          final t = f[campo.clave]!.text.trim();
          if (t.isEmpty) continue;
          fila[campo.clave] = campo.numerico ? _num(t) : t;
        }
        if (destino == 'inversiones' && _nueva) fila['mes'] = 0;
        if (clave == 'aportes') fila['mes'] = 0;
        lista.add(fila);
      }
      p[destino] = lista;
    });
    if (!_nueva) {
      final hist = <Map<String, dynamic>>[];
      for (int i = 0; i < _historico.length; i++) {
        final t = _historicoCtrls[i].text.trim();
        if (t.isEmpty) continue;
        hist.add({'mes': _historico[i]['mes'], 'anio': _historico[i]['anio'], 'etiqueta': _historico[i]['etiqueta'], 'ventas': _num(t)});
      }
      _poner(p, 'ventas.historico', hist);
    }
    return p;
  }

  void _notificar() {
    if (mounted) widget.onChanged(parametros());
  }

  Future<void> _importarHistorial() async {
    if (widget.negocioId == null) return;
    setState(() {
      _importando = true;
      _avisoImportacion = null;
    });
    try {
      final r = await ApiService.get('/flujos-caja-proyectados/historico/?negocio=${widget.negocioId}');
      if (r.statusCode != 200) throw Exception('No se pudo leer el historial (${r.statusCode}).');
      final d = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final meses = ((d['meses'] as List?) ?? []).map((m) => Map<String, dynamic>.from(m as Map)).toList();
      setState(() {
        _cargarHistorico(meses);
        if (d['costo_ventas_pct'] != null) _campos['costo_ventas_pct']!.text = _textoInicial(d['costo_ventas_pct']);
        _campos['iva.ventas_gravadas_pct']!.text = _textoInicial(d['ventas_gravadas_pct'] ?? 100);
        _campos['cxc_inicial']!.text = _textoInicial(d['cxc']);
        _campos['cxp_inicial']!.text = _textoInicial(d['cxp']);
        final promGastos = (d['promedio_gastos'] as num?)?.toDouble() ?? 0;
        final gastos = _listas['gastos_fijos']!;
        final yaEsta = gastos.any((f) => f['concepto']!.text.startsWith('Gastos de operación (promedio'));
        if (promGastos > 0 && !yaEsta) {
          gastos.add(_nuevaFila('gastos_fijos', {'concepto': 'Gastos de operación (promedio últimos 12 meses)', 'monto': promGastos.round()}));
        }
        final conDatos = d['meses_con_datos'] ?? 0;
        _avisoImportacion = conDatos == 0
            ? "Este negocio no tiene ventas registradas en los últimos 12 meses. Digitá la historia a mano."
            : "Se importaron $conDatos meses con movimiento desde Equilibra. Revisá que los gastos no se dupliquen con la planilla.";
      });
      _notificar();
    } catch (e) {
      setState(() => _avisoImportacion = "$e");
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  // ------------------------------------------------------------------ UI

  InputDecoration _deco(String etiqueta, {String? sufijo, String? ayuda, String? prefijo}) => InputDecoration(
        labelText: etiqueta,
        helperText: ayuda,
        helperMaxLines: 2,
        suffixText: sufijo,
        prefixText: prefijo,
        isDense: true,
        labelStyle: const TextStyle(color: TemaContador.textoTenue, fontSize: 13),
        filled: true,
        fillColor: TemaContador.superficie,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
      );

  Widget _campoNum(String ruta, String etiqueta, {String? sufijo, String? ayuda, bool dinero = false}) => TextField(
        controller: _campos[ruta],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: TemaContador.textoFuerte),
        decoration: _deco(etiqueta, sufijo: sufijo, ayuda: ayuda, prefijo: dinero ? '${widget.simbolo} ' : null),
        onChanged: (_) => _notificar(),
      );

  Widget _fila(List<Widget> hijos) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 520) {
          return Column(children: [for (final h in hijos) Padding(padding: const EdgeInsets.only(bottom: 10), child: h)]);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (int i = 0; i < hijos.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: hijos[i])],
          ]),
        );
      });

  Widget _interruptor(String ruta, String titulo, {String? subtitulo}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeThumbColor: TemaContador.acento,
        title: Text(titulo, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: subtitulo == null ? null : Text(subtitulo, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12)),
        value: _interruptores[ruta] ?? true,
        onChanged: (v) {
          setState(() => _interruptores[ruta] = v);
          _notificar();
        },
      );

  Widget _seccion({required IconData icono, required String titulo, String? descripcion, required List<Widget> hijos, bool abierta = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: TemaContador.fondo, borderRadius: BorderRadius.circular(12), border: Border.all(color: TemaContador.borde)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: abierta,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: TemaContador.acento,
          collapsedIconColor: TemaContador.textoTenue,
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: TemaContador.acento.withOpacity(0.08), borderRadius: BorderRadius.circular(9)),
            child: Icon(icono, size: 18, color: TemaContador.acento),
          ),
          title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: TemaContador.textoFuerte)),
          subtitle: descripcion == null ? null : Text(descripcion, style: const TextStyle(fontSize: 12, color: TemaContador.textoTenue)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: hijos,
        ),
      ),
    );
  }

  Widget _lista(String clave, String textoAgregar) {
    final filas = _listas[clave]!;
    final espec = _especListas[clave]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < filas.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LayoutBuilder(builder: (context, c) {
              final angosto = c.maxWidth < 560;
              final campos = [
                for (final campo in espec)
                  TextField(
                    controller: filas[i][campo.clave],
                    keyboardType: campo.numerico ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                    style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13.5),
                    decoration: _deco(campo.etiqueta).copyWith(hintText: campo.sugerencia, hintStyle: const TextStyle(fontSize: 12, color: TemaContador.textoTenue)),
                    onChanged: (_) => _notificar(),
                  ),
              ];
              final quitar = IconButton(
                tooltip: "Quitar",
                icon: const Icon(Icons.close, size: 18, color: TemaContador.textoTenue),
                onPressed: () {
                  setState(() {
                    for (final ctrl in filas.removeAt(i).values) {
                      ctrl.dispose();
                    }
                  });
                  _notificar();
                },
              );
              if (angosto) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 4),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: TemaContador.borde)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Wrap(runSpacing: 8, children: [for (final w in campos) SizedBox(width: double.infinity, child: w)])),
                    quitar,
                  ]),
                );
              }
              return Row(children: [
                for (int k = 0; k < campos.length; k++) ...[
                  if (k > 0) const SizedBox(width: 8),
                  Expanded(flex: espec[k].flex, child: campos[k]),
                ],
                quitar,
              ]);
            }),
          ),
        TextButton.icon(
          onPressed: () => setState(() => filas.add(_nuevaFila(clave))),
          style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
          icon: const Icon(Icons.add, size: 18),
          label: Text(textoAgregar),
        ),
      ],
    );
  }

  Widget _nota(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(texto, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5, height: 1.35)),
      );

  List<Widget> _seccionesComunes() => [
        _seccion(
          icono: Icons.percent,
          titulo: "Costo de ventas, cobros y pagos",
          descripcion: "Cuánto cuesta lo que se vende y cuándo entra/sale la plata",
          hijos: [
            _fila([
              _campoNum('costo_ventas_pct', "Costo de ventas", sufijo: '% de la venta', ayuda: "Mercadería o materia prima por cada ₡100 vendidos"),
            ]),
            _nota("Cobro a clientes (debe sumar 100 %):"),
            _fila([
              _campoNum('cobro.contado', "De contado", sufijo: '%'),
              _campoNum('cobro.d30', "A 30 días", sufijo: '%'),
              _campoNum('cobro.d60', "A 60 días", sufijo: '%'),
            ]),
            _nota("Pago a proveedores:"),
            _fila([
              _campoNum('pago_proveedores.contado', "De contado", sufijo: '%'),
              _campoNum('pago_proveedores.d30', "A 30 días", sufijo: '%'),
            ]),
          ],
        ),
        _seccion(
          icono: Icons.groups_outlined,
          titulo: "Planilla",
          descripcion: "Salarios, cargas sociales CCSS y aguinaldo en diciembre",
          hijos: [
            _fila([
              _campoNum('planilla.salarios_mensuales', "Salarios brutos mensuales", dinero: true),
              _campoNum('planilla.cargas_sociales_pct', "Cargas sociales patronales", sufijo: '%', ayuda: "26,67 % es la carga patronal típica"),
              _campoNum('planilla.aumento_anual_pct', "Aumento anual", sufijo: '%'),
            ]),
            _interruptor('planilla.aguinaldo', "Incluir aguinaldo", subtitulo: "Un mes de salario, pagado en diciembre"),
          ],
        ),
        _seccion(
          icono: Icons.receipt_long_outlined,
          titulo: "Gastos fijos mensuales",
          descripcion: "Alquiler, servicios, publicidad, contabilidad…",
          hijos: [_lista('gastos_fijos', "Agregar gasto fijo")],
        ),
        _seccion(
          icono: Icons.account_balance_outlined,
          titulo: "Impuestos",
          descripcion: "IVA (D-104) y renta (pagos parciales)",
          hijos: [
            _interruptor('iva.aplica', "Cobra IVA", subtitulo: "El IVA neto se paga a Hacienda el mes siguiente"),
            if (_interruptores['iva.aplica'] ?? true)
              _fila([
                _campoNum('iva.ventas_gravadas_pct', "Ventas gravadas", sufijo: '%'),
                _campoNum('iva.compras_gravadas_pct', "Compras gravadas", sufijo: '%'),
              ]),
            _fila([
              _campoNum('renta.tasa_efectiva', "Tasa efectiva de renta", sufijo: '% de la utilidad', ayuda: "Se paga en junio, setiembre y diciembre (parciales)"),
            ]),
          ],
        ),
        _seccion(
          icono: Icons.tune,
          titulo: "Análisis de sensibilidad",
          descripcion: "Escenarios pesimista y optimista",
          hijos: [
            _fila([
              _campoNum('escenarios_variacion_pct', "Variación de ventas para escenarios", sufijo: '%'),
              if (_nueva) _campoNum('tasa_descuento_anual', "Tasa de descuento (VAN)", sufijo: '% anual', ayuda: "Rendimiento mínimo que exigen los socios"),
            ]),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final secciones = _nueva ? _seccionesNueva() : _seccionesExistente();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...secciones, ..._seccionesComunes()]);
  }

  List<Widget> _seccionesNueva() => [
        _seccion(
          icono: Icons.construction_outlined,
          titulo: "Inversión inicial",
          descripcion: "Lo que se necesita antes de abrir (columna \"Inversión inicial\")",
          abierta: true,
          hijos: [
            _nota("Activos: equipo, mobiliario, vehículos, remodelación del local…"),
            _lista('inversiones', "Agregar inversión"),
            const SizedBox(height: 6),
            _nota("Gastos preoperativos: permisos, patente, depósitos, publicidad de apertura, inventario inicial…"),
            _lista('preoperativos', "Agregar gasto preoperativo"),
          ],
        ),
        _seccion(
          icono: Icons.savings_outlined,
          titulo: "Financiamiento",
          descripcion: "Cómo se paga la inversión: aporte de socios y préstamos",
          abierta: true,
          hijos: [
            _nota("Aporte de los socios (capital propio):"),
            _lista('aportes', "Agregar aporte"),
            const SizedBox(height: 6),
            _nota("Préstamos nuevos (cuota nivelada; en los meses de gracia solo se pagan intereses; mes 0 = desembolso antes de abrir):"),
            _lista('prestamos_nuevos', "Agregar préstamo"),
          ],
        ),
        _seccion(
          icono: Icons.trending_up,
          titulo: "Ventas proyectadas",
          descripcion: "Curva de arranque: crecen rápido al inicio y luego se estabilizan",
          abierta: true,
          hijos: [
            _fila([
              _campoNum('ventas.mes1', "Ventas del primer mes (sin IVA)", dinero: true),
              _campoNum('anios', "Horizonte", sufijo: 'años', ayuda: "12 meses en detalle + años completos (máx. 5)"),
            ]),
            _fila([
              _campoNum('ventas.crecimiento_rampa_pct', "Crecimiento en el arranque", sufijo: '% mensual'),
              _campoNum('ventas.meses_rampa', "Duración del arranque", sufijo: 'meses'),
              _campoNum('ventas.crecimiento_mensual_pct', "Crecimiento después", sufijo: '% mensual'),
            ]),
          ],
        ),
      ];

  List<Widget> _seccionesExistente() => [
        _seccion(
          icono: Icons.history,
          titulo: "Historia de ventas (últimos 12 meses)",
          descripcion: "La proyección se ancla a lo que el negocio ya vende",
          abierta: true,
          hijos: [
            if (widget.negocioId != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TemaContador.acento.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: TemaContador.acento.withOpacity(0.25))),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text("Este cliente factura en Equilibra: traé sus datos reales.", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 13)),
                    FilledButton.icon(
                      onPressed: _importando ? null : _importarHistorial,
                      style: FilledButton.styleFrom(backgroundColor: TemaContador.acento),
                      icon: _importando
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_outlined, size: 18),
                      label: const Text("Importar historial de Equilibra"),
                    ),
                  ],
                ),
              ),
            if (_avisoImportacion != null) _nota(_avisoImportacion!),
            if (_historico.isEmpty) ...[
              _nota("Si no tenés el detalle mes a mes, poné el promedio mensual de ventas o generá los 12 meses para digitarlos."),
              _fila([_campoNum('ventas.base_mensual', "Ventas promedio mensuales (sin IVA)", dinero: true)]),
              TextButton.icon(
                onPressed: () {
                  final hoy = DateTime.now();
                  const nombres = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
                  final filas = <Map<String, dynamic>>[];
                  for (int k = 12; k >= 1; k--) {
                    final f = DateTime(hoy.year, hoy.month - k, 1);
                    filas.add({'anio': f.year, 'mes': f.month, 'etiqueta': "${nombres[f.month - 1]} ${f.year % 100}", 'ventas': null});
                  }
                  setState(() => _cargarHistorico(filas));
                },
                style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text("Digitar mes a mes"),
              ),
            ] else ...[
              _gridHistorico(),
              _interruptor('ventas.usar_estacionalidad', "Respetar la estacionalidad",
                  subtitulo: "Los meses fuertes y flojos del año pasado se repiten en la proyección"),
            ],
            _fila([
              _campoNum('ventas.crecimiento_anual_pct', "Crecimiento esperado", sufijo: '% anual', ayuda: "Sobre el promedio histórico; sé conservador"),
            ]),
          ],
        ),
        _seccion(
          icono: Icons.swap_horiz,
          titulo: "Saldos al inicio",
          descripcion: "Lo que ya le deben al negocio y lo que el negocio debe a proveedores",
          hijos: [
            _fila([
              _campoNum('cxc_inicial', "Cuentas por cobrar", dinero: true, ayuda: "Se cobra 60 % el mes 1 y 40 % el mes 2"),
              _campoNum('cxp_inicial', "Cuentas por pagar a proveedores", dinero: true, ayuda: "Se pagan el mes 1"),
            ]),
          ],
        ),
        _seccion(
          icono: Icons.credit_card,
          titulo: "Deudas y préstamos",
          descripcion: "Cuotas vigentes y préstamos nuevos que se quieren tramitar",
          hijos: [
            _nota("Deudas que ya existen:"),
            _lista('deudas_existentes', "Agregar deuda"),
            const SizedBox(height: 6),
            _nota("Préstamo nuevo (ej. el que se está solicitando; mes de desembolso 1-12):"),
            _lista('prestamos_nuevos', "Agregar préstamo nuevo"),
          ],
        ),
        _seccion(
          icono: Icons.construction_outlined,
          titulo: "Inversiones planificadas",
          descripcion: "Compras de equipo, vehículos o ampliaciones en el año",
          hijos: [_lista('inversiones_plan', "Agregar inversión")],
        ),
      ];

  Widget _gridHistorico() {
    double total = 0;
    for (final c in _historicoCtrls) {
      total += _num(c.text);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, c) {
          final columnas = c.maxWidth > 700 ? 6 : (c.maxWidth > 420 ? 4 : 2);
          final ancho = (c.maxWidth - (columnas - 1) * 8) / columnas;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _historico.length; i++)
                SizedBox(
                  width: ancho,
                  child: TextField(
                    controller: _historicoCtrls[i],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13),
                    decoration: _deco(_historico[i]['etiqueta']?.toString() ?? 'Mes ${_historico[i]['mes']}'),
                    onChanged: (_) {
                      setState(() {});
                      _notificar();
                    },
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 8),
        Text(
          "Total 12 meses: ${formatoMonto(total, widget.simbolo)} · promedio ${formatoMonto(total / 12, widget.simbolo)} por mes",
          style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ==================================================================== vista previa

class VistaPreviaFlujo extends StatelessWidget {
  final Map<String, dynamic> resultado;
  final String simbolo;

  const VistaPreviaFlujo({super.key, required this.resultado, required this.simbolo});

  List<double> _lista(dynamic v) => ((v as List?) ?? []).map((x) => (x as num).toDouble()).toList();

  @override
  Widget build(BuildContext context) {
    final ind = Map<String, dynamic>.from(resultado['indicadores'] ?? {});
    final esNueva = resultado['tipo'] == 'nueva';
    final columnas = ((resultado['columnas'] as List?) ?? []).map((c) => c.toString()).toList();
    final saldos = _lista(resultado['saldo_final']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _indicadores(ind, esNueva),
        const SizedBox(height: 14),
        if (saldos.isNotEmpty) _GraficoSaldos(columnas: columnas, saldos: saldos, simbolo: simbolo),
        const SizedBox(height: 14),
        _estado(columnas, esNueva),
        const SizedBox(height: 14),
        _escenarios(),
      ],
    );
  }

  Widget _indicadores(Map<String, dynamic> ind, bool esNueva) {
    double? n(String k) => (ind[k] as num?)?.toDouble();
    final cobertura = n('cobertura_deuda_anio1');
    final necesidad = n('necesidad_financiamiento') ?? 0;
    final tarjetas = <Widget>[
      _Indicador(
        titulo: "Ventas año 1",
        valor: formatoMonto(n('ventas_anio1') ?? 0, simbolo),
        detalle: esNueva
            ? "Promedio ${formatoMonto(n('ventas_promedio_mensual') ?? 0, simbolo)}/mes"
            : (n('crecimiento_vs_historico_pct') == null ? "Sin historia cargada" : "${n('crecimiento_vs_historico_pct')!.toStringAsFixed(1)} % vs. histórico"),
      ),
      _Indicador(
        titulo: "Utilidad operativa año 1",
        valor: formatoMonto(n('utilidad_operativa_anio1') ?? 0, simbolo),
        detalle: n('margen_operativo_pct') == null ? '' : "Margen ${n('margen_operativo_pct')!.toStringAsFixed(1)} %",
        estado: (n('utilidad_operativa_anio1') ?? 0) >= 0 ? _Estado.bien : _Estado.mal,
      ),
      _Indicador(
        titulo: "Punto de equilibrio",
        valor: n('punto_equilibrio_mensual') == null ? '—' : formatoMonto(n('punto_equilibrio_mensual')!, simbolo),
        detalle: "Ventas mensuales para no perder",
      ),
      _Indicador(
        titulo: "Cobertura de deuda",
        valor: cobertura == null ? "Sin deuda" : "${cobertura.toStringAsFixed(2)} x",
        detalle: cobertura == null ? "No hay cuotas en el año 1" : (cobertura >= 1.2 ? "Cumple lo que piden los bancos (≥ 1,20)" : "Por debajo de 1,20 que piden los bancos"),
        estado: cobertura == null ? _Estado.neutro : (cobertura >= 1.2 ? _Estado.bien : _Estado.mal),
      ),
      _Indicador(
        titulo: "Saldo mínimo de caja",
        valor: formatoMonto(n('saldo_minimo') ?? 0, simbolo),
        detalle: necesidad > 0 ? "Faltan ${formatoMonto(necesidad, simbolo)} (${ind['saldo_minimo_periodo'] ?? ''})" : "La caja nunca queda en rojo",
        estado: necesidad > 0 ? _Estado.mal : _Estado.bien,
      ),
      if (esNueva) ...[
        _Indicador(
          titulo: "Recuperación de la inversión",
          valor: ind['recuperacion_meses'] == null ? "No se recupera" : "Mes ${ind['recuperacion_meses']}",
          detalle: "Inversión ${formatoMonto(n('inversion_total') ?? 0, simbolo)}",
          estado: ind['recuperacion_meses'] == null ? _Estado.mal : _Estado.bien,
        ),
        _Indicador(
          titulo: "VAN (${(n('tasa_descuento_pct') ?? 15).toStringAsFixed(0)} %)",
          valor: formatoMonto(n('van') ?? 0, simbolo),
          detalle: (n('van') ?? 0) >= 0 ? "El proyecto crea valor" : "No alcanza el rendimiento exigido",
          estado: (n('van') ?? 0) >= 0 ? _Estado.bien : _Estado.mal,
        ),
        _Indicador(
          titulo: "TIR anual",
          valor: n('tir_anual_pct') == null ? '—' : "${n('tir_anual_pct')!.toStringAsFixed(1)} %",
          detalle: "Rentabilidad del proyecto",
          estado: n('tir_anual_pct') == null
              ? _Estado.neutro
              : (n('tir_anual_pct')! >= (n('tasa_descuento_pct') ?? 15) ? _Estado.bien : _Estado.mal),
        ),
      ],
    ];
    return LayoutBuilder(builder: (context, c) {
      final columnas = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
      final ancho = (c.maxWidth - (columnas - 1) * 10) / columnas;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tarjetas) SizedBox(width: ancho, child: t)]);
    });
  }

  Widget _estado(List<String> columnas, bool esNueva) {
    final filas = <DataRow>[];
    const estiloNegrita = TextStyle(fontWeight: FontWeight.w800, color: TemaContador.textoFuerte, fontSize: 12.5);
    const estiloNormal = TextStyle(color: TemaContador.textoFuerte, fontSize: 12.5);

    DataRow fila(String concepto, List<double> valores, {bool negrita = false, Color? fondo, double? total}) {
      final estilo = negrita ? estiloNegrita : estiloNormal;
      return DataRow(
        color: fondo == null ? null : WidgetStatePropertyAll(fondo),
        cells: [
          DataCell(Text(concepto, style: estilo)),
          for (final v in valores) DataCell(Text(_cifra(v), style: estilo.copyWith(color: v < -0.5 ? _rojo : null))),
          if (!esNueva) DataCell(Text(_cifra(total ?? valores.fold<double>(0, (a, b) => a + b)), style: estiloNegrita)),
        ],
      );
    }

    final saldoIni = _lista(resultado['saldo_inicial']);
    filas.add(fila("Saldo inicial de caja", saldoIni, negrita: true, total: saldoIni.isEmpty ? 0 : saldoIni.first));
    for (final s in (resultado['secciones'] as List? ?? [])) {
      final sec = Map<String, dynamic>.from(s as Map);
      filas.add(DataRow(
        color: WidgetStatePropertyAll(TemaContador.acento.withOpacity(0.06)),
        cells: [
          DataCell(Text(sec['titulo'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: TemaContador.acento, letterSpacing: 0.4))),
          for (int i = 0; i < columnas.length + (esNueva ? 0 : 1); i++) const DataCell(SizedBox()),
        ],
      ));
      for (final f in (sec['filas'] as List)) {
        final m = Map<String, dynamic>.from(f as Map);
        filas.add(fila("   ${m['concepto']}", _lista(m['valores']), total: (m['total'] as num?)?.toDouble()));
      }
      final sub = Map<String, dynamic>.from(sec['subtotal'] as Map);
      filas.add(fila(sub['concepto'].toString(), _lista(sub['valores']), negrita: true, total: (sub['total'] as num?)?.toDouble()));
    }
    filas.add(fila("FLUJO NETO DEL PERÍODO", _lista(resultado['flujo_neto']), negrita: true, fondo: TemaContador.superficie));
    final saldoFin = _lista(resultado['saldo_final']);
    filas.add(fila("SALDO FINAL DE CAJA", saldoFin, negrita: true, fondo: TemaContador.superficie, total: saldoFin.isEmpty ? 0 : saldoFin.last));

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: TemaContador.borde)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(TemaContador.textoFuerte),
          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
          headingRowHeight: 38,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 34,
          columnSpacing: 22,
          horizontalMargin: 12,
          columns: [
            const DataColumn(label: Text("Concepto")),
            for (final c in columnas) DataColumn(label: Text(c), numeric: true),
            if (!esNueva) const DataColumn(label: Text("Total"), numeric: true),
          ],
          rows: filas,
        ),
      ),
    );
  }

  Widget _escenarios() {
    final esc = (resultado['escenarios'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (esc.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Análisis de sensibilidad", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: TemaContador.textoFuerte)),
        const SizedBox(height: 4),
        const Text("Qué pasa si las ventas salen menores o mayores a lo proyectado.", style: TextStyle(color: TemaContador.textoTenue, fontSize: 12.5)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final ancho = c.maxWidth > 560 ? (c.maxWidth - 20) / 3 : c.maxWidth;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in esc)
              SizedBox(
                width: ancho,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: e['nombre'] == 'Base' ? TemaContador.acento.withOpacity(0.05) : TemaContador.fondo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: e['nombre'] == 'Base' ? TemaContador.acento.withOpacity(0.35) : TemaContador.borde),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("${e['nombre']} (${(e['variacion_ventas_pct'] as num) >= 0 ? '+' : ''}${(e['variacion_ventas_pct'] as num).toStringAsFixed(0)} % ventas)",
                        style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte, fontSize: 13)),
                    const SizedBox(height: 6),
                    _parEsc("Saldo final", formatoMonto((e['saldo_final'] as num).toDouble(), simbolo), (e['saldo_final'] as num) < 0),
                    _parEsc("Saldo mínimo", formatoMonto((e['saldo_minimo'] as num).toDouble(), simbolo), (e['saldo_minimo'] as num) < 0),
                    _parEsc("Cobertura deuda", e['cobertura_deuda_anio1'] == null ? 'Sin deuda' : "${(e['cobertura_deuda_anio1'] as num).toStringAsFixed(2)} x",
                        e['cobertura_deuda_anio1'] != null && (e['cobertura_deuda_anio1'] as num) < 1.2),
                  ]),
                ),
              ),
          ]);
        }),
      ],
    );
  }

  Widget _parEsc(String etiqueta, String valor, bool malo) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5))),
          Text(valor, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: malo ? _rojo : TemaContador.textoFuerte)),
        ]),
      );
}

enum _Estado { bien, mal, neutro }

class _Indicador extends StatelessWidget {
  final String titulo;
  final String valor;
  final String detalle;
  final _Estado estado;

  const _Indicador({required this.titulo, required this.valor, required this.detalle, this.estado = _Estado.neutro});

  @override
  Widget build(BuildContext context) {
    final color = switch (estado) { _Estado.bien => _verde, _Estado.mal => _rojo, _Estado.neutro => TemaContador.textoTenue };
    final icono = switch (estado) { _Estado.bien => Icons.check_circle, _Estado.mal => Icons.error_outline, _Estado.neutro => null };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TemaContador.fondo, borderRadius: BorderRadius.circular(12), border: Border.all(color: TemaContador.borde)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(titulo, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12, fontWeight: FontWeight.w600))),
            if (icono != null) Icon(icono, size: 15, color: color),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          if (detalle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(detalle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: estado == _Estado.neutro ? TemaContador.textoTenue : color, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

/// Saldo de caja al cierre de cada período: barras sobre una línea de cero
/// (las negativas en rojo, con el monto al pasar el mouse).
class _GraficoSaldos extends StatelessWidget {
  final List<String> columnas;
  final List<double> saldos;
  final String simbolo;

  const _GraficoSaldos({required this.columnas, required this.saldos, required this.simbolo});

  @override
  Widget build(BuildContext context) {
    final maximo = saldos.fold<double>(0, (a, b) => b > a ? b : a);
    final minimo = saldos.fold<double>(0, (a, b) => b < a ? b : a);
    final rango = (maximo - minimo) == 0 ? 1.0 : (maximo - minimo);
    const alto = 130.0;
    final yCero = alto * (maximo / rango);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(color: TemaContador.fondo, borderRadius: BorderRadius.circular(12), border: Border.all(color: TemaContador.borde)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Saldo de caja al cierre de cada período", style: TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte, fontSize: 13)),
          const SizedBox(height: 10),
          SizedBox(
            height: alto,
            child: Stack(children: [
              Positioned(left: 0, right: 0, top: yCero, child: Container(height: 1, color: TemaContador.borde)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < saldos.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: "${columnas.length > i ? columnas[i] : ''}: ${formatoMonto(saldos[i], simbolo)}",
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Stack(children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: saldos[i] >= 0 ? yCero - alto * (saldos[i] / rango) : yCero + 1,
                              height: (alto * (saldos[i].abs() / rango)).clamp(1.0, alto),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: saldos[i] >= 0 ? TemaContador.acento : _rojo,
                                  borderRadius: saldos[i] >= 0
                                      ? const BorderRadius.vertical(top: Radius.circular(4))
                                      : const BorderRadius.vertical(bottom: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Row(children: [
            for (int i = 0; i < saldos.length; i++)
              Expanded(
                child: Text(
                  i == 0 || i == saldos.length - 1 || saldos.length <= 8 || i % 3 == 0 ? (columnas.length > i ? columnas[i] : '') : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(fontSize: 10, color: TemaContador.textoTenue),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

/// Llama a /flujos-caja-proyectados/calcular/ con un pequeño retardo para no
/// recalcular en cada tecla.
class CalculadoraFlujo {
  Timer? _timer;
  int _version = 0;

  void calcular({
    required String tipo,
    required Map<String, dynamic> parametros,
    required DateTime? fechaInicio,
    required double saldoInicial,
    required void Function(Map<String, dynamic>? resultado, String? error) alTerminar,
  }) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), () async {
      final version = ++_version;
      try {
        final inicio = fechaInicio ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
        final r = await ApiService.post('/flujos-caja-proyectados/calcular/', {
          'tipo': tipo,
          'parametros': parametros,
          'fecha_inicio': DateTime(inicio.year, inicio.month, 1).toIso8601String().split('T').first,
          'saldo_inicial': saldoInicial,
        });
        if (version != _version) return;
        final data = json.decode(utf8.decode(r.bodyBytes));
        if (r.statusCode == 200) {
          alTerminar(Map<String, dynamic>.from(data as Map), null);
        } else {
          alTerminar(null, (data is Map ? data['detail'] : null)?.toString() ?? "No se pudo calcular (${r.statusCode}).");
        }
      } catch (e) {
        if (version == _version) alTerminar(null, "No se pudo calcular: $e");
      }
    });
  }

  void cancelar() => _timer?.cancel();
}
