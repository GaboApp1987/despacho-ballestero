import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../formato.dart';

/// Calculadora con historial, desde la barra de arriba de todos los perfiles
/// (negocio, contador, despacho, administrador). El historial queda guardado
/// en el dispositivo (últimas 50 operaciones). Números al estilo de Costa
/// Rica: coma decimal y punto de miles. "%" después de un + o un − es el
/// porcentaje del número anterior (1.000 + 13% = 1.130); si no, divide entre 100.
class BotonCalculadora extends StatelessWidget {
  /// Color del ícono (blanco en las barras de color).
  final Color? color;
  /// Si se da, se usa en vez del IconButton (para las barras con su propio
  /// estilo de botones, ver accionAppBar).
  final Widget Function(VoidCallback abrir)? constructor;
  const BotonCalculadora({super.key, this.color, this.constructor});

  @override
  Widget build(BuildContext context) {
    void abrir() => abrirCalculadora(context);
    if (constructor != null) return constructor!(abrir);
    return IconButton(
      tooltip: "Calculadora",
      icon: Icon(Icons.calculate_outlined, color: color),
      onPressed: abrir,
    );
  }
}

/// Para las pruebas: evalúa como la calculadora (null si es inválida).
double? evaluarCalculadora(String expresion) => _CalculadoraState.evaluar(expresion);

void abrirCalculadora(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const Dialog(
      insetPadding: EdgeInsets.all(16),
      child: _Calculadora(),
    ),
  );
}

class _Calculadora extends StatefulWidget {
  const _Calculadora();

  @override
  State<_Calculadora> createState() => _CalculadoraState();
}

class _CalculadoraState extends State<_Calculadora> {
  static const _claveHistorial = 'calculadora_historial';
  static const _maxHistorial = 50;

  // Expresión con los símbolos internos: dígitos, '.', + - × ÷ %.
  String _expresion = '';
  String? _resultadoPrevio; // vista previa mientras se escribe
  bool _recienCalculado = false;
  List<({String expresion, String resultado})> _historial = [];
  bool _verHistorial = false;
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista = json.decode(prefs.getString(_claveHistorial) ?? '[]') as List;
      if (!mounted) return;
      setState(() => _historial = [
            for (final h in lista) (expresion: h['e'].toString(), resultado: h['r'].toString()),
          ]);
    } catch (_) {}
  }

  Future<void> _guardarHistorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_claveHistorial, json.encode([for (final h in _historial) {'e': h.expresion, 'r': h.resultado}]));
    } catch (_) {}
  }

  // --- Evaluación --------------------------------------------------------

  static bool _esOperador(String c) => '+-×÷'.contains(c);

  /// Evalúa con precedencia (× ÷ antes que + −). null si está incompleta o
  /// es inválida (división entre cero, etc.).
  static double? evaluar(String expr) {
    final tokens = <String>[];
    var numero = '';
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      final esSigno = c == '-' && (i == 0 || _esOperador(expr[i - 1]));
      if ('0123456789.'.contains(c) || esSigno) {
        numero += c;
      } else {
        if (numero.isNotEmpty) {
          tokens.add(numero);
          numero = '';
        }
        tokens.add(c);
      }
    }
    if (numero.isNotEmpty) tokens.add(numero);
    if (tokens.isEmpty) return null;

    var pos = 0;
    // factor := número [%]
    (double, bool)? factor() {
      if (pos >= tokens.length) return null;
      final v = double.tryParse(tokens[pos]);
      if (v == null) return null;
      pos++;
      if (pos < tokens.length && tokens[pos] == '%') {
        pos++;
        return (v, true);
      }
      return (v, false);
    }

    // término := factor ((× | ÷) factor)*
    (double, bool)? termino() {
      var f = factor();
      if (f == null) return null;
      var (valor, esPorcentaje) = f;
      while (pos < tokens.length && (tokens[pos] == '×' || tokens[pos] == '÷')) {
        final op = tokens[pos++];
        final g = factor();
        if (g == null) return null;
        final derecho = g.$2 ? g.$1 / 100 : g.$1;
        final izquierdo = esPorcentaje ? valor / 100 : valor;
        if (op == '÷' && derecho == 0) return null;
        valor = op == '×' ? izquierdo * derecho : izquierdo / derecho;
        esPorcentaje = false;
      }
      return (valor, esPorcentaje);
    }

    final t = termino();
    if (t == null) return null;
    var total = t.$2 ? t.$1 / 100 : t.$1;
    while (pos < tokens.length && (tokens[pos] == '+' || tokens[pos] == '-')) {
      final op = tokens[pos++];
      final u = termino();
      if (u == null) return null;
      // 1.000 + 13% = 1.130: el porcentaje es del total que va.
      final derecho = u.$2 ? total * u.$1 / 100 : u.$1;
      total = op == '+' ? total + derecho : total - derecho;
    }
    if (pos != tokens.length || total.isNaN || total.isInfinite) return null;
    return total;
  }

  static String formatear(double v) {
    final redondeado = double.parse(v.toStringAsFixed(8));
    if (redondeado == redondeado.truncateToDouble()) return formatearNumero(redondeado, decimales: 0);
    final decimales = redondeado.toStringAsFixed(8).split('.')[1].replaceAll(RegExp(r'0+$'), '').length;
    return formatearNumero(redondeado, decimales: decimales);
  }

  /// Expresión para mostrar: números con miles y coma decimal.
  static String mostrar(String expr) {
    return expr.replaceAllMapped(RegExp(r'\d+(\.\d*)?'), (m) {
      final texto = m.group(0)!;
      final partes = texto.split('.');
      final entero = formatearNumero(int.parse(partes[0]), decimales: 0);
      return partes.length > 1 ? '$entero,${partes[1]}' : entero;
    }).replaceAll('-', '−');
  }

  // --- Teclas ------------------------------------------------------------

  void _tecla(String t) {
    setState(() {
      if (t == 'C') {
        _expresion = '';
        _recienCalculado = false;
      } else if (t == '⌫') {
        if (_expresion.isNotEmpty) _expresion = _expresion.substring(0, _expresion.length - 1);
        _recienCalculado = false;
      } else if (t == '=') {
        _calcular();
        return;
      } else if (t == '±') {
        _cambiarSigno();
      } else if (_esOperador(t) || t == '%') {
        if (_expresion.isEmpty && t != '-') return;
        _recienCalculado = false;
        final ultimo = _expresion.isEmpty ? '' : _expresion[_expresion.length - 1];
        if (t == '%') {
          if ('0123456789.'.contains(ultimo) && ultimo.isNotEmpty) _expresion += '%';
        } else if (_esOperador(ultimo)) {
          _expresion = _expresion.substring(0, _expresion.length - 1) + t;
        } else {
          _expresion += t;
        }
      } else {
        // Dígito o punto decimal: si se acaba de calcular, empieza de nuevo.
        if (_recienCalculado) _expresion = '';
        _recienCalculado = false;
        if (t == '.') {
          final numeroActual = RegExp(r'[\d.]*$').stringMatch(_expresion) ?? '';
          if (numeroActual.contains('.')) return;
          if (numeroActual.isEmpty) _expresion += '0';
        }
        if (_expresion.endsWith('%')) _expresion += '×';
        _expresion += t;
      }
      final v = evaluar(_expresion);
      _resultadoPrevio = v != null && RegExp(r'[+\-×÷%]').hasMatch(_expresion.replaceFirst(RegExp(r'^-'), '')) ? formatear(v) : null;
    });
  }

  void _cambiarSigno() {
    final m = RegExp(r'(^|[+\-×÷])(-?)([\d.]+%?)$').firstMatch(_expresion);
    if (m == null) return;
    final inicio = m.start + m.group(1)!.length;
    final negativo = m.group(2) == '-';
    final cuerpo = m.group(3)!;
    // "5 − 3" -> "5 − -3" queda raro: dentro de una resta/suma se cambia el operador.
    if (m.group(1) == '+' || (m.group(1) == '-' && inicio > 0)) {
      final opPos = inicio - 1;
      final nuevoOp = m.group(1) == '+' ? '-' : '+';
      _expresion = _expresion.substring(0, opPos) + nuevoOp + cuerpo;
      return;
    }
    _expresion = _expresion.substring(0, inicio) + (negativo ? '' : '-') + cuerpo;
  }

  void _calcular() {
    final v = evaluar(_expresion);
    if (v == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("La operación está incompleta o no se puede calcular."), duration: Duration(seconds: 2)),
      );
      return;
    }
    final resultado = formatear(v);
    final expresionMostrada = mostrar(_expresion);
    if (expresionMostrada != resultado) {
      _historial.insert(0, (expresion: expresionMostrada, resultado: resultado));
      if (_historial.length > _maxHistorial) _historial = _historial.sublist(0, _maxHistorial);
      _guardarHistorial();
    }
    _expresion = _aInterno(v);
    _resultadoPrevio = null;
    _recienCalculado = true;
  }

  static String _aInterno(double v) {
    final t = double.parse(v.toStringAsFixed(8)).toString();
    return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
  }

  void _usarResultado(String resultado) {
    // "1.234,5" -> "1234.5"
    final interno = resultado.replaceAll('.', '').replaceAll(',', '.').replaceAll('−', '-');
    setState(() {
      final ultimo = _expresion.isEmpty ? '' : _expresion[_expresion.length - 1];
      _expresion = (_expresion.isEmpty || _esOperador(ultimo)) && !_recienCalculado ? _expresion + interno : interno;
      _recienCalculado = false;
      _verHistorial = false;
      final v = evaluar(_expresion);
      _resultadoPrevio = v != null && RegExp(r'[+×÷%]').hasMatch(_expresion) ? formatear(v) : null;
    });
  }

  KeyEventResult _teclado(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final c = e.character;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || c == '=') {
      _tecla('=');
    } else if (k == LogicalKeyboardKey.backspace) {
      _tecla('⌫');
    } else if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.delete) {
      if (k == LogicalKeyboardKey.escape && _expresion.isEmpty) return KeyEventResult.ignored; // cierra
      _tecla('C');
    } else if (c != null && RegExp(r'^[0-9]$').hasMatch(c)) {
      _tecla(c);
    } else if (c == '.' || c == ',') {
      _tecla('.');
    } else if (c == '+' || c == '-' || c == '%') {
      _tecla(c!);
    } else if (c == '*' || c == 'x' || c == 'X') {
      _tecla('×');
    } else if (c == '/') {
      _tecla('÷');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- Interfaz ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _foco,
      autofocus: true,
      onKeyEvent: _teclado,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.calculate_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text("Calculadora", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  IconButton(
                    tooltip: _verHistorial ? "Volver a la calculadora" : "Historial",
                    icon: Icon(_verHistorial ? Icons.calculate : Icons.history),
                    onPressed: () => setState(() => _verHistorial = !_verHistorial),
                  ),
                  IconButton(tooltip: "Cerrar", icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              _pantalla(esquema),
              const SizedBox(height: 10),
              SizedBox(height: 330, child: _verHistorial ? _listaHistorial(esquema) : _teclado4x5(esquema)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pantalla(ColorScheme esquema) {
    final textoPrincipal = _expresion.isEmpty ? '0' : mostrar(_expresion);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: esquema.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SelectableText(
                  textoPrincipal,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  style: TextStyle(fontSize: textoPrincipal.length > 16 ? 22 : 30, fontWeight: FontWeight.w600),
                ),
                SizedBox(
                  height: 20,
                  child: Text(
                    _resultadoPrevio == null ? '' : '= $_resultadoPrevio',
                    style: TextStyle(fontSize: 14, color: esquema.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Copiar",
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              final v = evaluar(_expresion);
              Clipboard.setData(ClipboardData(text: v == null ? textoPrincipal : formatear(v)));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text("Copiado"), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _teclado4x5(ColorScheme esquema) {
    const filas = [
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '+'],
      ['±', '0', '.', '='],
    ];
    return Column(
      children: [
        for (final fila in filas)
          Expanded(
            child: Row(
              children: [
                for (final t in fila)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: _boton(t, esquema),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _boton(String t, ColorScheme esquema) {
    final esIgual = t == '=';
    final esOperador = _esOperador(t) || t == '%';
    final esFuncion = t == 'C' || t == '⌫' || t == '±';
    final fondo = esIgual
        ? esquema.primary
        : esOperador
            ? esquema.primaryContainer
            : esFuncion
                ? esquema.surfaceContainerHigh
                : esquema.surfaceContainerLow;
    final colorTexto = esIgual
        ? esquema.onPrimary
        : esOperador
            ? esquema.onPrimaryContainer
            : t == 'C'
                ? Colors.red.shade400
                : esquema.onSurface;
    final etiqueta = t == '.' ? ',' : (t == '-' ? '−' : t);
    return Material(
      color: fondo,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tecla(t),
        child: Center(
          child: t == '⌫'
              ? Icon(Icons.backspace_outlined, size: 20, color: colorTexto)
              : Text(etiqueta, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: colorTexto)),
        ),
      ),
    );
  }

  Widget _listaHistorial(ColorScheme esquema) {
    if (_historial.isEmpty) {
      return Center(child: Text("Todavía no hay operaciones.", style: TextStyle(color: esquema.onSurfaceVariant)));
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _historial.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final h = _historial[i];
              return ListTile(
                dense: true,
                title: Text(h.expresion, textAlign: TextAlign.right, style: TextStyle(color: esquema.onSurfaceVariant)),
                subtitle: Text("= ${h.resultado}", textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: esquema.onSurface)),
                onTap: () => _usarResultado(h.resultado),
              );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text("Tocá una operación para usar su resultado.",
                  style: TextStyle(fontSize: 11.5, color: esquema.onSurfaceVariant)),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _historial = []);
                _guardarHistorial();
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text("Borrar historial"),
            ),
          ],
        ),
      ],
    );
  }
}
