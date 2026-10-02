import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'documentos_contador_screen.dart';
import 'firmante_contador.dart';
import 'firmante_selector.dart';
import 'negocio.dart';
import 'socio.dart';
import 'widgets/flujo_caja_modalidades.dart';

class MesFlujoCaja {
  final String mes;
  double ingresos;
  double egresos;

  MesFlujoCaja({required this.mes, this.ingresos = 0, this.egresos = 0});

  double get neto => ingresos - egresos;

  factory MesFlujoCaja.fromJson(Map<String, dynamic> json) => MesFlujoCaja(
        mes: json['mes'] ?? '',
        ingresos: (json['ingresos'] ?? 0).toDouble(),
        egresos: (json['egresos'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {'mes': mes, 'ingresos': ingresos, 'egresos': egresos};
}

/// Información financiera prospectiva (NITA 3400 / Circular 21-2010 del
/// Colegio de CPA de Costa Rica) -- proyección de 12 meses con supuestos.
class FlujoCajaProyectado {
  final int? id;
  final int? negocio;
  final String? negocioNombre;
  int? firmante;
  final String? firmanteNombre;
  String nombreSolicitante;
  String cedula;
  String dirigidoA;
  String proposito;
  List<String> supuestos;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  String moneda;
  List<MesFlujoCaja> datosMensuales;
  double saldoInicial;
  String lugarEmision;
  /// 'simple' (ingresos/egresos digitados a mano), 'nueva' (empresa nueva /
  /// proyecto) o 'existente' (empresa en marcha) -- ver gestion/flujo_caja.py.
  String tipo;
  Map<String, dynamic> parametros;
  Map<String, dynamic> resultado;

  FlujoCajaProyectado({
    this.id,
    this.negocio,
    this.negocioNombre,
    this.firmante,
    this.firmanteNombre,
    this.nombreSolicitante = '',
    this.cedula = '',
    this.dirigidoA = '',
    this.proposito = '',
    List<String>? supuestos,
    this.fechaInicio,
    this.fechaFin,
    this.moneda = 'CRC',
    List<MesFlujoCaja>? datosMensuales,
    this.saldoInicial = 0,
    this.lugarEmision = 'San José',
    this.tipo = 'nueva',
    Map<String, dynamic>? parametros,
    Map<String, dynamic>? resultado,
  })  : supuestos = supuestos ?? [],
        datosMensuales = datosMensuales ?? [],
        parametros = parametros ?? {},
        resultado = resultado ?? {};

  bool get esDetallado => tipo == 'nueva' || tipo == 'existente';

  String get nombreTipo => switch (tipo) { 'nueva' => 'Empresa nueva', 'existente' => 'Empresa en marcha', _ => 'Manual' };

  factory FlujoCajaProyectado.fromJson(Map<String, dynamic> json) => FlujoCajaProyectado(
        id: json['id'],
        negocio: json['negocio'],
        negocioNombre: json['negocio_nombre'],
        firmante: json['firmante'],
        firmanteNombre: json['firmante_nombre'],
        nombreSolicitante: json['nombre_solicitante'] ?? '',
        cedula: json['cedula'] ?? '',
        dirigidoA: json['dirigido_a'] ?? '',
        proposito: json['proposito'] ?? '',
        supuestos: ((json['supuestos'] as List?) ?? []).map((s) => s.toString()).toList(),
        fechaInicio: json['fecha_inicio'] != null ? DateTime.tryParse(json['fecha_inicio']) : null,
        fechaFin: json['fecha_fin'] != null ? DateTime.tryParse(json['fecha_fin']) : null,
        moneda: json['moneda'] ?? 'CRC',
        datosMensuales: ((json['datos_mensuales'] as List?) ?? []).map((m) => MesFlujoCaja.fromJson(m)).toList(),
        saldoInicial: double.tryParse(json['saldo_inicial']?.toString() ?? '0') ?? 0,
        lugarEmision: json['lugar_emision'] ?? 'San José',
        tipo: json['tipo'] ?? 'simple',
        parametros: Map<String, dynamic>.from(json['parametros'] ?? {}),
        resultado: Map<String, dynamic>.from(json['resultado'] ?? {}),
      );

  Map<String, dynamic> toJson() => {
        if (negocio != null) 'negocio': negocio,
        if (firmante != null) 'firmante': firmante,
        'nombre_solicitante': nombreSolicitante,
        'cedula': cedula,
        'dirigido_a': dirigidoA,
        'proposito': proposito,
        'supuestos': supuestos,
        if (fechaInicio != null) 'fecha_inicio': fechaInicio!.toIso8601String().split('T').first,
        if (fechaFin != null && !esDetallado) 'fecha_fin': fechaFin!.toIso8601String().split('T').first,
        'moneda': moneda,
        if (!esDetallado) 'datos_mensuales': datosMensuales.map((m) => m.toJson()).toList(),
        'tipo': tipo,
        if (esDetallado) 'parametros': parametros,
        'saldo_inicial': saldoInicial,
        'lugar_emision': lugarEmision,
      };
}

class FlujoCajaScreen extends StatefulWidget {
  const FlujoCajaScreen({super.key});

  @override
  State<FlujoCajaScreen> createState() => _FlujoCajaScreenState();
}

class _FlujoCajaScreenState extends State<FlujoCajaScreen> {
  bool _cargando = true;
  List<FlujoCajaProyectado> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await ApiService.get('/flujos-caja-proyectados/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _lista = data.map((j) => FlujoCajaProyectado.fromJson(j)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _nuevo() async {
    final creado = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => const FlujoCajaFormScreen()));
    if (creado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: const Text("Flujo de Caja Proyectado", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        backgroundColor: TemaContador.acento,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Nuevo flujo de caja"),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _lista.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.trending_up, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("Todavía no creaste ningún flujo de caja proyectado.", style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text("Usá el botón \"Nuevo flujo de caja\" para crear el primero.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _lista.length,
                    itemBuilder: (context, index) {
                      final f = _lista[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: TemaContador.superficie,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: TemaContador.borde)),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0x1A1D4ED8), child: Icon(Icons.trending_up, color: TemaContador.acento)),
                          title: Text(f.nombreSolicitante, style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte)),
                          subtitle: Text(
                            "${f.nombreTipo} · ${f.proposito} · ${f.dirigidoA}\n${f.negocioNombre ?? 'Cliente sin cartera de facturación'}",
                            style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5),
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_outlined, color: TemaContador.textoTenue),
                                tooltip: "Descargar PDF",
                                onPressed: () => descargarDocumento(context, 'flujos-caja-proyectados', f.id!, 'pdf', 'flujo_caja_proyectado'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.description_outlined, color: TemaContador.textoTenue),
                                tooltip: "Descargar Word",
                                onPressed: () => descargarDocumento(context, 'flujos-caja-proyectados', f.id!, 'word', 'flujo_caja_proyectado'),
                              ),
                              const Icon(Icons.chevron_right, color: TemaContador.acento),
                            ],
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FlujoCajaFormScreen(flujo: f))),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class FlujoCajaFormScreen extends StatefulWidget {
  final FlujoCajaProyectado? flujo;

  const FlujoCajaFormScreen({super.key, this.flujo});

  @override
  State<FlujoCajaFormScreen> createState() => _FlujoCajaFormScreenState();
}

class _FlujoCajaFormScreenState extends State<FlujoCajaFormScreen> {
  late FlujoCajaProyectado _flujo;
  bool _clienteExistente = false;
  bool _cargandoNegocios = true;
  bool _guardando = false;
  List<Negocio> _negocios = [];
  Negocio? _negocioSeleccionado;
  bool _firmarConNombreRegistrado = true;
  List<FirmanteContador> _firmantes = [];

  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _dirigidoACtrl = TextEditingController();
  final _propositoCtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();
  final _saldoInicialCtrl = TextEditingController();
  final List<TextEditingController> _supuestoCtrls = [];

  final CalculadoraFlujo _calculadora = CalculadoraFlujo();
  Map<String, dynamic>? _vistaPrevia;
  String? _errorCalculo;
  bool _calculando = false;

  final Map<String, TextEditingController> _ingresoCtrls = {};
  final Map<String, TextEditingController> _egresoCtrls = {};

  static const List<String> _mesesNombres = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _flujo = widget.flujo ?? FlujoCajaProyectado();
    _clienteExistente = _flujo.negocio != null;
    _nombreCtrl.text = _flujo.nombreSolicitante;
    _cedulaCtrl.text = _flujo.cedula;
    _dirigidoACtrl.text = _flujo.dirigidoA;
    _propositoCtrl.text = _flujo.proposito;
    _lugarCtrl.text = _flujo.lugarEmision;
    _saldoInicialCtrl.text = _flujo.saldoInicial == 0 ? '' : _flujo.saldoInicial.toStringAsFixed(2);
    for (final s in _flujo.supuestos) {
      _supuestoCtrls.add(TextEditingController(text: s));
    }
    if (_supuestoCtrls.isEmpty) _supuestoCtrls.add(TextEditingController());

    if (_flujo.datosMensuales.isEmpty) {
      final ahora = DateTime.now();
      _flujo.fechaInicio ??= DateTime(ahora.year, ahora.month, 1);
      _flujo.fechaFin ??= DateTime(ahora.year, ahora.month + 11, 1);
      for (int i = 0; i < 12; i++) {
        final mesIdx = (ahora.month - 1 + i) % 12;
        _flujo.datosMensuales.add(MesFlujoCaja(mes: _mesesNombres[mesIdx]));
      }
    }
    for (int i = 0; i < _flujo.datosMensuales.length; i++) {
      final m = _flujo.datosMensuales[i];
      final clave = '$i#${m.mes}';
      _ingresoCtrls[clave] = TextEditingController(text: m.ingresos == 0 ? '' : m.ingresos.toStringAsFixed(2));
      _egresoCtrls[clave] = TextEditingController(text: m.egresos == 0 ? '' : m.egresos.toStringAsFixed(2));
    }
    if (_flujo.resultado.isNotEmpty) _vistaPrevia = _flujo.resultado;
    _cargarNegocios();
    _cargarMiSocio();
  }

  void _recalcular() {
    if (!_flujo.esDetallado) return;
    setState(() => _calculando = true);
    _calculadora.calcular(
      tipo: _flujo.tipo,
      parametros: _flujo.parametros,
      fechaInicio: _flujo.fechaInicio,
      saldoInicial: double.tryParse(_saldoInicialCtrl.text.replaceAll(',', '')) ?? 0,
      alTerminar: (resultado, error) {
        if (!mounted) return;
        setState(() {
          _calculando = false;
          if (resultado != null) _vistaPrevia = resultado;
          _errorCalculo = error;
        });
      },
    );
  }

  void _cambiarTipo(String tipo) {
    if (tipo == _flujo.tipo) return;
    setState(() {
      _flujo.tipo = tipo;
      _flujo.parametros = {};
      _vistaPrevia = null;
      _errorCalculo = null;
    });
  }

  Future<void> _cargarMiSocio() async {
    try {
      final r = await ApiService.get('/socios/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted && data.isNotEmpty) {
          final socio = Socio.fromJson(data.first);
          setState(() {
            _firmarConNombreRegistrado = socio.firmarConNombreRegistrado;
            _firmantes = socio.firmantes;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _calculadora.cancelar();
    _nombreCtrl.dispose();
    _cedulaCtrl.dispose();
    _dirigidoACtrl.dispose();
    _propositoCtrl.dispose();
    _lugarCtrl.dispose();
    _saldoInicialCtrl.dispose();
    for (final c in _supuestoCtrls) {
      c.dispose();
    }
    for (final c in _ingresoCtrls.values) {
      c.dispose();
    }
    for (final c in _egresoCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarNegocios() async {
    try {
      final r = await ApiService.get('/negocios/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        final negocios = data.map((j) => Negocio.fromJson(j)).toList();
        if (mounted) {
          setState(() {
            _negocios = negocios;
            if (_flujo.negocio != null) {
              final coincidencias = negocios.where((n) => n.id == _flujo.negocio);
              _negocioSeleccionado = coincidencias.isEmpty ? null : coincidencias.first;
            }
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _cargandoNegocios = false);
  }

  double get _totalIngresos {
    double total = 0;
    for (final c in _ingresoCtrls.values) {
      total += double.tryParse(c.text.replaceAll(',', '')) ?? 0;
    }
    return total;
  }

  double get _totalEgresos {
    double total = 0;
    for (final c in _egresoCtrls.values) {
      total += double.tryParse(c.text.replaceAll(',', '')) ?? 0;
    }
    return total;
  }

  bool _validar() {
    if (_nombreCtrl.text.trim().isEmpty || _dirigidoACtrl.text.trim().isEmpty || _propositoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Completá al menos nombre, dirigido a y propósito.")));
      return false;
    }
    if (!_firmarConNombreRegistrado && _firmantes.isNotEmpty && _flujo.firmante == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Elegí quién firma este documento.")));
      return false;
    }
    return true;
  }

  Future<void> _guardar({required bool descargarPdf, bool descargarWord = false}) async {
    if (!_validar()) return;
    setState(() => _guardando = true);

    for (int i = 0; i < _flujo.datosMensuales.length; i++) {
      final m = _flujo.datosMensuales[i];
      final clave = '$i#${m.mes}';
      m.ingresos = double.tryParse(_ingresoCtrls[clave]!.text.replaceAll(',', '')) ?? 0;
      m.egresos = double.tryParse(_egresoCtrls[clave]!.text.replaceAll(',', '')) ?? 0;
    }

    _flujo
      ..nombreSolicitante = _nombreCtrl.text.trim()
      ..cedula = _cedulaCtrl.text.trim()
      ..dirigidoA = _dirigidoACtrl.text.trim()
      ..proposito = _propositoCtrl.text.trim()
      ..lugarEmision = _lugarCtrl.text.trim().isEmpty ? 'San José' : _lugarCtrl.text.trim()
      ..saldoInicial = double.tryParse(_saldoInicialCtrl.text.replaceAll(',', '')) ?? 0
      ..supuestos = _supuestoCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

    try {
      final body = {
        ..._flujo.toJson(),
        if (_clienteExistente && _negocioSeleccionado != null) 'negocio': _negocioSeleccionado!.id,
      };
      final esNuevo = _flujo.id == null;
      final response = esNuevo ? await ApiService.post('/flujos-caja-proyectados/', body) : await ApiService.patch('/flujos-caja-proyectados/${_flujo.id}/', body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        _flujo = FlujoCajaProyectado.fromJson(data);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Flujo de caja guardado"), backgroundColor: Colors.green));
        if (descargarPdf) await descargarDocumento(context, 'flujos-caja-proyectados', _flujo.id!, 'pdf', 'flujo_caja_proyectado');
        if (descargarWord) await descargarDocumento(context, 'flujos-caja-proyectados', _flujo.id!, 'word', 'flujo_caja_proyectado');
        if (mounted) Navigator.pop(context, true);
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final actual = (esInicio ? _flujo.fechaInicio : _flujo.fechaFin) ?? DateTime.now();
    final elegida = await showDatePicker(context: context, initialDate: actual, firstDate: DateTime(2015), lastDate: DateTime(DateTime.now().year + 3));
    if (elegida == null) return;
    _calculadora.cancelar();
    Future.microtask(_recalcular);
    setState(() {
      if (esInicio) {
        _flujo.fechaInicio = _flujo.esDetallado ? DateTime(elegida.year, elegida.month, 1) : elegida;
      } else {
        _flujo.fechaFin = elegida;
      }
    });
  }

  InputDecoration _decoracion(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: TemaContador.textoTenue),
        filled: true,
        fillColor: TemaContador.superficie,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
      );

  Widget _tarjeta({required String titulo, required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: TemaContador.fondo, borderRadius: BorderRadius.circular(14), border: Border.all(color: TemaContador.borde)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: TemaContador.textoFuerte)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  String _simboloMoneda() => _flujo.moneda == 'USD' ? r'$' : '₡';

  Widget _selectorTipo() {
    Widget opcion(String tipo, IconData icono, String titulo, String descripcion) {
      final activo = _flujo.tipo == tipo;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _cambiarTipo(tipo),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: activo ? TemaContador.acento.withOpacity(0.06) : TemaContador.superficie,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: activo ? TemaContador.acento : TemaContador.borde, width: activo ? 1.6 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icono, color: activo ? TemaContador.acento : TemaContador.textoTenue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: activo ? TemaContador.acento : TemaContador.textoFuerte)),
                const SizedBox(height: 2),
                Text(descripcion, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12, height: 1.3)),
              ]),
            ),
            if (activo) const Icon(Icons.check_circle, color: TemaContador.acento, size: 18),
          ]),
        ),
      );
    }

    final opciones = [
      opcion('nueva', Icons.rocket_launch_outlined, "Empresa nueva",
          "Proyecto o negocio que va a empezar: inversión inicial, financiamiento, arranque de ventas. Incluye VAN, TIR y recuperación."),
      opcion('existente', Icons.storefront_outlined, "Empresa en marcha",
          "Negocio con historia: parte de sus ventas reales (se importan de Equilibra), cuentas por cobrar/pagar y deudas vigentes."),
      opcion('simple', Icons.edit_note, "Manual", "Digitar ingresos y egresos de cada mes (formato anterior)."),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 640) {
        return Column(children: [for (final o in opciones) Padding(padding: const EdgeInsets.only(bottom: 8), child: o)]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 5, child: opciones[0]),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: opciones[1]),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: opciones[2]),
        ]),
      );
    });
  }

  Widget _vistaPreviaWidget() {
    if (_vistaPrevia == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(children: [
          if (_calculando) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          if (_calculando) const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorCalculo ?? (_calculando ? "Calculando…" : "Completá los datos y el estado aparece acá."),
              style: TextStyle(color: _errorCalculo != null ? Colors.red : TemaContador.textoTenue),
            ),
          ),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedOpacity(
          opacity: _calculando ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2)),
        ),
        if (_errorCalculo != null)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_errorCalculo!, style: const TextStyle(color: Colors.red))),
        VistaPreviaFlujo(resultado: _vistaPrevia!, simbolo: _simboloMoneda()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final campo = const TextStyle(color: TemaContador.textoFuerte);
    double saldoAcumulado = _flujo.saldoInicial;

    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: Text(_flujo.id == null ? "Nuevo flujo de caja" : "Editar flujo de caja", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tarjeta(
              titulo: "¿Qué tipo de flujo de caja?",
              child: _selectorTipo(),
            ),
            _tarjeta(
              titulo: "¿Para quién es el flujo de caja?",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [ButtonSegment(value: false, label: Text("Cliente nuevo")), ButtonSegment(value: true, label: Text("Cliente de mi cartera"))],
                    selected: {_clienteExistente},
                    onSelectionChanged: (s) => setState(() {
                      _clienteExistente = s.first;
                      if (!_clienteExistente) _negocioSeleccionado = null;
                    }),
                    style: SegmentedButton.styleFrom(selectedBackgroundColor: TemaContador.acento, selectedForegroundColor: Colors.white, foregroundColor: TemaContador.textoFuerte, side: const BorderSide(color: TemaContador.borde)),
                  ),
                  if (_clienteExistente) ...[
                    const SizedBox(height: 12),
                    _cargandoNegocios
                        ? const LinearProgressIndicator()
                        : DropdownButtonFormField<Negocio>(
                            initialValue: _negocioSeleccionado,
                            decoration: _decoracion("Elegí el cliente"),
                            style: const TextStyle(color: TemaContador.textoFuerte),
                            dropdownColor: TemaContador.fondo,
                            items: _negocios
                                .map((n) => DropdownMenuItem(value: n, child: Text(n.nombreComercial, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TemaContador.textoFuerte))))
                                .toList(),
                            onChanged: (n) => setState(() {
                              _negocioSeleccionado = n;
                              if (n != null) {
                                _nombreCtrl.text = n.nombreComercial;
                                _cedulaCtrl.text = n.cedula;
                                if (_flujo.id == null && _flujo.tipo == 'nueva') {
                                  _flujo.tipo = 'existente';
                                  _flujo.parametros = {};
                                  _vistaPrevia = null;
                                }
                              }
                            }),
                          ),
                  ],
                ],
              ),
            ),
            _tarjeta(
              titulo: "Datos generales",
              child: Column(
                children: [
                  TextField(controller: _nombreCtrl, style: campo, decoration: _decoracion("Nombre / razón social *")),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _cedulaCtrl, style: campo, decoration: _decoracion("Cédula"))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _dirigidoACtrl, style: campo, decoration: _decoracion("Dirigido a *"))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _propositoCtrl, style: campo, decoration: _decoracion("Propósito *"))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _lugarCtrl, style: campo, decoration: _decoracion("Lugar de emisión"))),
                  ]),
                  selectorFirmante(
                    firmarConNombreRegistrado: _firmarConNombreRegistrado,
                    firmantes: _firmantes,
                    firmanteSeleccionado: _flujo.firmante,
                    onChanged: (v) => setState(() => _flujo.firmante = v),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _flujo.moneda,
                        decoration: _decoracion("Moneda"),
                        style: const TextStyle(color: TemaContador.textoFuerte),
                        dropdownColor: TemaContador.fondo,
                        items: const [
                          DropdownMenuItem(value: 'CRC', child: Text("Colones (CRC)", style: TextStyle(color: TemaContador.textoFuerte))),
                          DropdownMenuItem(value: 'USD', child: Text("Dólares (USD)", style: TextStyle(color: TemaContador.textoFuerte))),
                        ],
                        onChanged: (v) {
                          setState(() => _flujo.moneda = v ?? 'CRC');
                          _recalcular();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _saldoInicialCtrl,
                        style: campo,
                        keyboardType: TextInputType.number,
                        decoration: _decoracion(_flujo.tipo == 'nueva' ? "Caja antes de la inversión" : "Saldo inicial de caja"),
                        onChanged: (_) => _recalcular(),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _elegirFecha(esInicio: true),
                        child: InputDecorator(
                          decoration: _decoracion(_flujo.esDetallado ? "Mes de inicio" : "Desde"),
                          child: Text(
                            _flujo.fechaInicio == null
                                ? "Elegir"
                                : _flujo.esDetallado
                                    ? "${_mesesNombres[_flujo.fechaInicio!.month - 1]} ${_flujo.fechaInicio!.year}"
                                    : "${_flujo.fechaInicio!.day}/${_flujo.fechaInicio!.month}/${_flujo.fechaInicio!.year}",
                            style: campo,
                          ),
                        ),
                      ),
                    ),
                    if (!_flujo.esDetallado) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _elegirFecha(esInicio: false),
                        child: InputDecorator(
                          decoration: _decoracion("Hasta"),
                          child: Text(_flujo.fechaFin == null ? "Elegir" : "${_flujo.fechaFin!.day}/${_flujo.fechaFin!.month}/${_flujo.fechaFin!.year}", style: campo),
                        ),
                      ),
                    ),
                    ],
                  ]),
                ],
              ),
            ),
            if (_flujo.esDetallado) ...[
              _tarjeta(
                titulo: _flujo.tipo == 'nueva' ? "Datos del proyecto" : "Datos del negocio",
                child: EditorParametrosFlujo(
                  key: ValueKey('editor-${_flujo.tipo}-${_negocioSeleccionado?.id}'),
                  tipo: _flujo.tipo,
                  parametros: _flujo.parametros,
                  negocioId: _clienteExistente ? _negocioSeleccionado?.id : null,
                  simbolo: _simboloMoneda(),
                  onChanged: (p) {
                    _flujo.parametros = p;
                    _recalcular();
                  },
                ),
              ),
              _tarjeta(
                titulo: "Vista previa del estado",
                child: _vistaPreviaWidget(),
              ),
            ],
            _tarjeta(
              titulo: _flujo.esDetallado ? "Supuestos adicionales" : "Supuestos de la proyección",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_flujo.esDetallado)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        "Los supuestos del cálculo (ventas, cobros, IVA, planilla, préstamos…) se redactan solos en el informe. Agregá acá solo lo que no se ve en los números, por ejemplo: \"El local ya cuenta con permiso de funcionamiento\".",
                        style: TextStyle(color: TemaContador.textoTenue, fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ..._supuestoCtrls.asMap().entries.map((entry) {
                    final i = entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(child: TextField(controller: entry.value, style: campo, decoration: _decoracion("Supuesto ${i + 1}"))),
                        IconButton(
                          icon: const Icon(Icons.close, color: TemaContador.textoTenue),
                          onPressed: _supuestoCtrls.length == 1
                              ? null
                              : () => setState(() {
                                    _supuestoCtrls.removeAt(i).dispose();
                                  }),
                        ),
                      ]),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => setState(() => _supuestoCtrls.add(TextEditingController())),
                    style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Agregar supuesto"),
                  ),
                ],
              ),
            ),
            if (!_flujo.esDetallado) ...[
            _tarjeta(
              titulo: "Proyección mensual",
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 12.5),
                  dataTextStyle: const TextStyle(color: TemaContador.textoFuerte),
                  columns: const [
                    DataColumn(label: Text("Mes")),
                    DataColumn(label: Text("Ingresos")),
                    DataColumn(label: Text("Egresos")),
                    DataColumn(label: Text("Flujo neto")),
                    DataColumn(label: Text("Saldo acumulado")),
                  ],
                  rows: List.generate(_flujo.datosMensuales.length, (i) {
                    final m = _flujo.datosMensuales[i];
                    final clave = '$i#${m.mes}';
                    final ingresoCtrl = _ingresoCtrls[clave]!;
                    final egresoCtrl = _egresoCtrls[clave]!;
                    final ingreso = double.tryParse(ingresoCtrl.text.replaceAll(',', '')) ?? 0;
                    final egreso = double.tryParse(egresoCtrl.text.replaceAll(',', '')) ?? 0;
                    final neto = ingreso - egreso;
                    saldoAcumulado += neto;
                    return DataRow(cells: [
                      DataCell(Text(m.mes)),
                      DataCell(SizedBox(
                        width: 110,
                        child: TextField(
                          controller: ingresoCtrl,
                          style: campo,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: "0"),
                          onChanged: (_) => setState(() {}),
                        ),
                      )),
                      DataCell(SizedBox(
                        width: 110,
                        child: TextField(
                          controller: egresoCtrl,
                          style: campo,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: "0"),
                          onChanged: (_) => setState(() {}),
                        ),
                      )),
                      DataCell(Text("${_simboloMoneda()} ${neto.toStringAsFixed(2)}", style: TextStyle(color: neto < 0 ? Colors.red : TemaContador.textoFuerte))),
                      DataCell(Text("${_simboloMoneda()} ${saldoAcumulado.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w700, color: saldoAcumulado < 0 ? Colors.red : TemaContador.textoFuerte))),
                    ]);
                  }),
                ),
              ),
            ),
            _tarjeta(
              titulo: "Resumen",
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total ingresos: ${_simboloMoneda()} ${_totalIngresos.toStringAsFixed(2)}", style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w600)),
                  Text("Total egresos: ${_simboloMoneda()} ${_totalEgresos.toStringAsFixed(2)}", style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w600)),
                  Text("Saldo final: ${_simboloMoneda()} ${saldoAcumulado.toStringAsFixed(2)}", style: TextStyle(color: saldoAcumulado < 0 ? Colors.red : TemaContador.acento, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: TemaContador.acento, disabledForegroundColor: TemaContador.textoTenue, side: const BorderSide(color: TemaContador.acento)),
                  onPressed: _guardando ? null : () => _guardar(descargarPdf: false),
                  child: const Text("Guardar"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white, disabledBackgroundColor: TemaContador.acento.withOpacity(0.5), disabledForegroundColor: Colors.white),
                  onPressed: _guardando ? null : () => _guardar(descargarPdf: true),
                  icon: _guardando ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text("Guardar y PDF"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: TemaContador.textoFuerte, foregroundColor: Colors.white, disabledBackgroundColor: TemaContador.textoFuerte.withOpacity(0.5), disabledForegroundColor: Colors.white),
                  onPressed: _guardando ? null : () => _guardar(descargarPdf: false, descargarWord: true),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text("Guardar y Word"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
