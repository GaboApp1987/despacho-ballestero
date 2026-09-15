import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'documentos_contador_screen.dart';
import 'firmante_contador.dart';
import 'firmante_selector.dart';
import 'negocio.dart';
import 'socio.dart';

/// Informe de certificación GENÉRICO (Circular 02-2022 del Colegio de
/// Contadores Públicos de Costa Rica) -- a diferencia de la certificación
/// de ingresos, acá la materia, procedimientos, resultados y certificación
/// son texto libre, porque un atestiguamiento puede ser sobre cualquier
/// hecho (inscripción de una sociedad, años de actividad, etc.).
class Atestiguamiento {
  final int? id;
  final int? negocio;
  final String? negocioNombre;
  int? firmante;
  final String? firmanteNombre;
  String nombreSolicitante;
  String cedula;
  String calidades;
  String materiaCertificar;
  String dirigidoA;
  String circularEspecifica;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  List<String> procedimientos;
  String resultados;
  String certificacionTexto;
  String salvaguarda;
  String proposito;
  bool efectosTributarios;
  String lugarEmision;

  Atestiguamiento({
    this.id,
    this.negocio,
    this.negocioNombre,
    this.firmante,
    this.firmanteNombre,
    this.nombreSolicitante = '',
    this.cedula = '',
    this.calidades = '',
    this.materiaCertificar = '',
    this.dirigidoA = '',
    this.circularEspecifica = '',
    this.fechaInicio,
    this.fechaFin,
    List<String>? procedimientos,
    this.resultados = '',
    this.certificacionTexto = '',
    this.salvaguarda = '',
    this.proposito = '',
    this.efectosTributarios = false,
    this.lugarEmision = 'San José',
  }) : procedimientos = procedimientos ?? [];

  factory Atestiguamiento.fromJson(Map<String, dynamic> json) => Atestiguamiento(
        id: json['id'],
        negocio: json['negocio'],
        negocioNombre: json['negocio_nombre'],
        firmante: json['firmante'],
        firmanteNombre: json['firmante_nombre'],
        nombreSolicitante: json['nombre_solicitante'] ?? '',
        cedula: json['cedula'] ?? '',
        calidades: json['calidades'] ?? '',
        materiaCertificar: json['materia_certificar'] ?? '',
        dirigidoA: json['dirigido_a'] ?? '',
        circularEspecifica: json['circular_especifica'] ?? '',
        fechaInicio: json['fecha_inicio'] != null ? DateTime.tryParse(json['fecha_inicio']) : null,
        fechaFin: json['fecha_fin'] != null ? DateTime.tryParse(json['fecha_fin']) : null,
        procedimientos: ((json['procedimientos'] as List?) ?? []).map((p) => p.toString()).toList(),
        resultados: json['resultados'] ?? '',
        certificacionTexto: json['certificacion_texto'] ?? '',
        salvaguarda: json['salvaguarda'] ?? '',
        proposito: json['proposito'] ?? '',
        efectosTributarios: json['efectos_tributarios'] ?? false,
        lugarEmision: json['lugar_emision'] ?? 'San José',
      );

  Map<String, dynamic> toJson() => {
        if (negocio != null) 'negocio': negocio,
        if (firmante != null) 'firmante': firmante,
        'nombre_solicitante': nombreSolicitante,
        'cedula': cedula,
        'calidades': calidades,
        'materia_certificar': materiaCertificar,
        'dirigido_a': dirigidoA,
        'circular_especifica': circularEspecifica,
        if (fechaInicio != null) 'fecha_inicio': fechaInicio!.toIso8601String().split('T').first,
        if (fechaFin != null) 'fecha_fin': fechaFin!.toIso8601String().split('T').first,
        'procedimientos': procedimientos,
        'resultados': resultados,
        'certificacion_texto': certificacionTexto,
        'salvaguarda': salvaguarda,
        'proposito': proposito,
        'efectos_tributarios': efectosTributarios,
        'lugar_emision': lugarEmision,
      };
}

class AtestiguamientosScreen extends StatefulWidget {
  const AtestiguamientosScreen({super.key});

  @override
  State<AtestiguamientosScreen> createState() => _AtestiguamientosScreenState();
}

class _AtestiguamientosScreenState extends State<AtestiguamientosScreen> {
  bool _cargando = true;
  List<Atestiguamiento> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await ApiService.get('/atestiguamientos/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _lista = data.map((j) => Atestiguamiento.fromJson(j)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _nuevo() async {
    final creado = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => const AtestiguamientoFormScreen()));
    if (creado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: const Text("Atestiguamientos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        backgroundColor: TemaContador.acento,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Nuevo atestiguamiento"),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _lista.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.verified_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("Todavía no emitiste ningún atestiguamiento.", style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text("Usá el botón \"Nuevo atestiguamiento\" para crear el primero.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _lista.length,
                    itemBuilder: (context, index) {
                      final a = _lista[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: TemaContador.superficie,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: TemaContador.borde)),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0x1A1D4ED8), child: Icon(Icons.verified_outlined, color: TemaContador.acento)),
                          title: Text(a.nombreSolicitante, style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte)),
                          subtitle: Text(
                            "${a.proposito} · ${a.dirigidoA}\n${a.negocioNombre ?? 'Cliente sin cartera de facturación'}",
                            style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5),
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_outlined, color: TemaContador.textoTenue),
                                tooltip: "Descargar PDF",
                                onPressed: () => descargarDocumento(context, 'atestiguamientos', a.id!, 'pdf', 'atestiguamiento'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.description_outlined, color: TemaContador.textoTenue),
                                tooltip: "Descargar Word",
                                onPressed: () => descargarDocumento(context, 'atestiguamientos', a.id!, 'word', 'atestiguamiento'),
                              ),
                              const Icon(Icons.chevron_right, color: TemaContador.acento),
                            ],
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AtestiguamientoFormScreen(atestiguamiento: a))),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class AtestiguamientoFormScreen extends StatefulWidget {
  final Atestiguamiento? atestiguamiento;

  const AtestiguamientoFormScreen({super.key, this.atestiguamiento});

  @override
  State<AtestiguamientoFormScreen> createState() => _AtestiguamientoFormScreenState();
}

class _AtestiguamientoFormScreenState extends State<AtestiguamientoFormScreen> {
  late Atestiguamiento _at;
  bool _clienteExistente = false;
  bool _cargandoNegocios = true;
  bool _guardando = false;
  List<Negocio> _negocios = [];
  Negocio? _negocioSeleccionado;
  bool _firmarConNombreRegistrado = true;
  List<FirmanteContador> _firmantes = [];

  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _calidadesCtrl = TextEditingController();
  final _materiaCtrl = TextEditingController();
  final _dirigidoACtrl = TextEditingController();
  final _circularCtrl = TextEditingController();
  final _resultadosCtrl = TextEditingController();
  final _certificacionCtrl = TextEditingController();
  final _salvaguardaCtrl = TextEditingController();
  final _propositoCtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();
  final List<TextEditingController> _procedimientoCtrls = [];
  bool _conPeriodo = false;

  @override
  void initState() {
    super.initState();
    _at = widget.atestiguamiento ?? Atestiguamiento();
    _clienteExistente = _at.negocio != null;
    _nombreCtrl.text = _at.nombreSolicitante;
    _cedulaCtrl.text = _at.cedula;
    _calidadesCtrl.text = _at.calidades;
    _materiaCtrl.text = _at.materiaCertificar;
    _dirigidoACtrl.text = _at.dirigidoA;
    _circularCtrl.text = _at.circularEspecifica;
    _resultadosCtrl.text = _at.resultados;
    _certificacionCtrl.text = _at.certificacionTexto;
    _salvaguardaCtrl.text = _at.salvaguarda;
    _propositoCtrl.text = _at.proposito;
    _lugarCtrl.text = _at.lugarEmision;
    _conPeriodo = _at.fechaInicio != null && _at.fechaFin != null;
    for (final p in _at.procedimientos) {
      _procedimientoCtrls.add(TextEditingController(text: p));
    }
    if (_procedimientoCtrls.isEmpty) _procedimientoCtrls.add(TextEditingController());
    _cargarNegocios();
    _cargarMiSocio();
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
    _nombreCtrl.dispose();
    _cedulaCtrl.dispose();
    _calidadesCtrl.dispose();
    _materiaCtrl.dispose();
    _dirigidoACtrl.dispose();
    _circularCtrl.dispose();
    _resultadosCtrl.dispose();
    _certificacionCtrl.dispose();
    _salvaguardaCtrl.dispose();
    _propositoCtrl.dispose();
    _lugarCtrl.dispose();
    for (final c in _procedimientoCtrls) {
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
            if (_at.negocio != null) {
              final coincidencias = negocios.where((n) => n.id == _at.negocio);
              _negocioSeleccionado = coincidencias.isEmpty ? null : coincidencias.first;
            }
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _cargandoNegocios = false);
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final actual = (esInicio ? _at.fechaInicio : _at.fechaFin) ?? DateTime.now();
    final elegida = await showDatePicker(context: context, initialDate: actual, firstDate: DateTime(2015), lastDate: DateTime(DateTime.now().year + 1));
    if (elegida == null) return;
    setState(() {
      if (esInicio) {
        _at.fechaInicio = elegida;
      } else {
        _at.fechaFin = elegida;
      }
    });
  }

  bool _validar() {
    if (_nombreCtrl.text.trim().isEmpty || _materiaCtrl.text.trim().isEmpty || _dirigidoACtrl.text.trim().isEmpty || _certificacionCtrl.text.trim().isEmpty || _propositoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Completá al menos nombre, materia a certificar, dirigido a, texto de certificación y propósito.")));
      return false;
    }
    if (!_firmarConNombreRegistrado && _firmantes.isNotEmpty && _at.firmante == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Elegí quién firma este documento.")));
      return false;
    }
    return true;
  }

  Future<void> _guardar({required bool descargarPdf, bool descargarWord = false}) async {
    if (!_validar()) return;
    setState(() => _guardando = true);
    _at
      ..nombreSolicitante = _nombreCtrl.text.trim()
      ..cedula = _cedulaCtrl.text.trim()
      ..calidades = _calidadesCtrl.text.trim()
      ..materiaCertificar = _materiaCtrl.text.trim()
      ..dirigidoA = _dirigidoACtrl.text.trim()
      ..circularEspecifica = _circularCtrl.text.trim()
      ..resultados = _resultadosCtrl.text.trim()
      ..certificacionTexto = _certificacionCtrl.text.trim()
      ..salvaguarda = _salvaguardaCtrl.text.trim()
      ..proposito = _propositoCtrl.text.trim()
      ..lugarEmision = _lugarCtrl.text.trim().isEmpty ? 'San José' : _lugarCtrl.text.trim()
      ..procedimientos = _procedimientoCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (!_conPeriodo) {
      _at.fechaInicio = null;
      _at.fechaFin = null;
    }

    try {
      final body = {
        ..._at.toJson(),
        if (_clienteExistente && _negocioSeleccionado != null) 'negocio': _negocioSeleccionado!.id,
      };
      final esNuevo = _at.id == null;
      final response = esNuevo ? await ApiService.post('/atestiguamientos/', body) : await ApiService.patch('/atestiguamientos/${_at.id}/', body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        _at = Atestiguamiento.fromJson(data);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Atestiguamiento guardado"), backgroundColor: Colors.green));
        if (descargarPdf) await descargarDocumento(context, 'atestiguamientos', _at.id!, 'pdf', 'atestiguamiento');
        if (descargarWord) await descargarDocumento(context, 'atestiguamientos', _at.id!, 'word', 'atestiguamiento');
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

  @override
  Widget build(BuildContext context) {
    final campo = (String c) => TextStyle(color: TemaContador.textoFuerte);
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: Text(_at.id == null ? "Nuevo atestiguamiento" : "Editar atestiguamiento", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
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
              titulo: "¿Para quién es el atestiguamiento?",
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
                              }
                            }),
                          ),
                  ],
                ],
              ),
            ),
            _tarjeta(
              titulo: "Datos del solicitante",
              child: Column(
                children: [
                  TextField(controller: _nombreCtrl, style: campo(''), decoration: _decoracion("Nombre completo *")),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _cedulaCtrl, style: campo(''), decoration: _decoracion("Cédula"))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _calidadesCtrl, style: campo(''), decoration: _decoracion("Calidades (ej: mayor, casado...)"))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: _dirigidoACtrl, style: campo(''), decoration: _decoracion("Dirigido a *")),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _propositoCtrl, style: campo(''), decoration: _decoracion("Propósito *"))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _lugarCtrl, style: campo(''), decoration: _decoracion("Lugar de emisión"))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: _circularCtrl, style: campo(''), decoration: _decoracion("Circular específica (opcional, ej: 16-2022R)")),
                  selectorFirmante(
                    firmarConNombreRegistrado: _firmarConNombreRegistrado,
                    firmantes: _firmantes,
                    firmanteSeleccionado: _at.firmante,
                    onChanged: (v) => setState(() => _at.firmante = v),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Certificado para efectos tributarios", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 13)),
                    value: _at.efectosTributarios,
                    activeColor: TemaContador.acento,
                    onChanged: (v) => setState(() => _at.efectosTributarios = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Corresponde a un periodo específico", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 13)),
                    value: _conPeriodo,
                    activeColor: TemaContador.acento,
                    onChanged: (v) => setState(() => _conPeriodo = v),
                  ),
                  if (_conPeriodo)
                    Row(children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _elegirFecha(esInicio: true),
                          child: InputDecorator(
                            decoration: _decoracion("Desde"),
                            child: Text(_at.fechaInicio == null ? "Elegir" : "${_at.fechaInicio!.day}/${_at.fechaInicio!.month}/${_at.fechaInicio!.year}", style: campo('')),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => _elegirFecha(esInicio: false),
                          child: InputDecorator(
                            decoration: _decoracion("Hasta"),
                            child: Text(_at.fechaFin == null ? "Elegir" : "${_at.fechaFin!.day}/${_at.fechaFin!.month}/${_at.fechaFin!.year}", style: campo('')),
                          ),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
            _tarjeta(
              titulo: "Materia a certificar",
              child: TextField(controller: _materiaCtrl, maxLines: 3, style: campo(''), decoration: _decoracion("Qué se está certificando *")),
            ),
            _tarjeta(
              titulo: "Procedimientos aplicados",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._procedimientoCtrls.asMap().entries.map((entry) {
                    final i = entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(child: TextField(controller: entry.value, style: campo(''), decoration: _decoracion("Procedimiento ${i + 1}"))),
                        IconButton(
                          icon: const Icon(Icons.close, color: TemaContador.textoTenue),
                          onPressed: _procedimientoCtrls.length == 1
                              ? null
                              : () => setState(() {
                                    _procedimientoCtrls.removeAt(i).dispose();
                                  }),
                        ),
                      ]),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => setState(() => _procedimientoCtrls.add(TextEditingController())),
                    style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Agregar procedimiento"),
                  ),
                ],
              ),
            ),
            _tarjeta(titulo: "Resultados", child: TextField(controller: _resultadosCtrl, maxLines: 4, style: campo(''), decoration: _decoracion("Resultados obtenidos"))),
            _tarjeta(titulo: "Certificación", child: TextField(controller: _certificacionCtrl, maxLines: 4, style: campo(''), decoration: _decoracion("Texto de la certificación/conclusión *"))),
            _tarjeta(titulo: "Salvaguarda (opcional)", child: TextField(controller: _salvaguardaCtrl, maxLines: 3, style: campo(''), decoration: _decoracion("Párrafo adicional de salvaguarda"))),
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
