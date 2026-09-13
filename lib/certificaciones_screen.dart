import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'certificacion_ingreso.dart';
import 'descarga_navegador_stub.dart' if (dart.library.html) 'descarga_navegador_web.dart';
import 'negocio.dart';

/// Lista de certificaciones de ingresos emitidas por el contador, con
/// acceso a crear una nueva. Pantalla propia del contador (no del negocio),
/// por eso siempre usa TemaContador en vez de AppColors.
class CertificacionesScreen extends StatefulWidget {
  const CertificacionesScreen({super.key});

  @override
  State<CertificacionesScreen> createState() => _CertificacionesScreenState();
}

class _CertificacionesScreenState extends State<CertificacionesScreen> {
  bool _cargando = true;
  List<CertificacionIngreso> _certificaciones = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await ApiService.get('/certificaciones-ingreso/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) {
          setState(() => _certificaciones = data.map((j) => CertificacionIngreso.fromJson(j)).toList());
        }
      }
    } catch (_) {
      // si falla, la lista simplemente queda vacía
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _nuevaCertificacion() async {
    final creada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CertificacionFormScreen()),
    );
    if (creada == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte),
          tooltip: "Volver",
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Certificaciones", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevaCertificacion,
        backgroundColor: TemaContador.acento,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Nueva certificación"),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _certificaciones.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.badge_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("Todavía no emitiste ninguna certificación.", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      const Text(
                        "Usá el botón \"Nueva certificación\" para crear la primera.",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _certificaciones.length,
                    itemBuilder: (context, index) {
                      final c = _certificaciones[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: TemaContador.superficie,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: TemaContador.borde),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x1A1D4ED8),
                            child: Icon(Icons.badge_outlined, color: TemaContador.acento),
                          ),
                          title: Text(c.nombreSolicitante, style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte)),
                          subtitle: Text(
                            "${c.proposito} · ${c.dirigidoA}\n${c.negocioNombre ?? 'Cliente sin cartera de facturación'}",
                            style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5),
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right, color: TemaContador.acento),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => CertificacionFormScreen(certificacion: c)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Formulario de una certificación de ingresos: datos fijos del solicitante
/// + tabla de 12 meses (manual o egresos por porcentaje). Un solo scroll en
/// vez de un wizard de varios pasos -- son pocos campos y el contador
/// necesita ver la tabla completa mientras llena los datos.
class CertificacionFormScreen extends StatefulWidget {
  final CertificacionIngreso? certificacion;

  const CertificacionFormScreen({super.key, this.certificacion});

  @override
  State<CertificacionFormScreen> createState() => _CertificacionFormScreenState();
}

class _CertificacionFormScreenState extends State<CertificacionFormScreen> {
  static const List<String> _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  late CertificacionIngreso _cert;
  bool _clienteExistente = false;
  bool _cargandoNegocios = true;
  bool _guardando = false;
  List<Negocio> _negocios = [];
  Negocio? _negocioSeleccionado;

  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _tipoCedulaCtrl = TextEditingController();
  final _nacionalidadCtrl = TextEditingController();
  final _actividadCtrl = TextEditingController();
  final _numeroActividadCtrl = TextEditingController();
  final _anosCtrl = TextEditingController();
  final _propositoCtrl = TextEditingController();
  final _dirigidoACtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();
  final _porcentajeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    final finPorDefecto = DateTime(ahora.year, ahora.month - 1, 0); // último día del mes anterior
    final inicioPorDefecto = DateTime(finPorDefecto.year - 1, finPorDefecto.month + 1, 1);
    _cert = widget.certificacion ??
        CertificacionIngreso(fechaInicio: inicioPorDefecto, fechaFin: finPorDefecto, moneda: 'CRC');
    _clienteExistente = _cert.negocio != null;
    _nombreCtrl.text = _cert.nombreSolicitante;
    _cedulaCtrl.text = _cert.cedula;
    _tipoCedulaCtrl.text = _cert.tipoCedulaTexto;
    _nacionalidadCtrl.text = _cert.nacionalidad;
    _actividadCtrl.text = _cert.actividadEconomica;
    _numeroActividadCtrl.text = _cert.numeroActividadEconomica;
    _anosCtrl.text = _cert.anosEjerciendo?.toString() ?? '';
    _propositoCtrl.text = _cert.proposito;
    _dirigidoACtrl.text = _cert.dirigidoA;
    _lugarCtrl.text = _cert.lugarEmision;
    _porcentajeCtrl.text = _cert.porcentajeEgresos?.toString() ?? '';
    if (_cert.datosMensuales.isEmpty) _regenerarTabla();
    _cargarNegocios();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cedulaCtrl.dispose();
    _tipoCedulaCtrl.dispose();
    _nacionalidadCtrl.dispose();
    _actividadCtrl.dispose();
    _numeroActividadCtrl.dispose();
    _anosCtrl.dispose();
    _propositoCtrl.dispose();
    _dirigidoACtrl.dispose();
    _lugarCtrl.dispose();
    _porcentajeCtrl.dispose();
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
            if (_cert.negocio != null) {
              final coincidencias = negocios.where((n) => n.id == _cert.negocio);
              _negocioSeleccionado = coincidencias.isEmpty ? null : coincidencias.first;
            }
          });
        }
      }
    } catch (_) {
      // sin cartera cargada, el modo "cliente existente" simplemente no ofrece opciones
    }
    if (mounted) setState(() => _cargandoNegocios = false);
  }

  void _prefillDesdeNegocio(Negocio? n) {
    setState(() {
      _negocioSeleccionado = n;
      if (n != null) {
        _nombreCtrl.text = n.nombreComercial;
        _cedulaCtrl.text = n.cedula;
      }
    });
  }

  /// Reconstruye las 12 filas mensuales según fechaInicio/fechaFin,
  /// preservando los montos ya tecleados que coincidan por etiqueta de mes
  /// (para no perder datos si el contador ajusta el periodo después de
  /// haber empezado a llenar la tabla).
  void _regenerarTabla() {
    final anteriores = {for (final m in _cert.datosMensuales) m.mes: m};
    final nuevas = <MesCertificacion>[];
    var cursor = DateTime(_cert.fechaInicio.year, _cert.fechaInicio.month, 1);
    final limite = DateTime(_cert.fechaFin.year, _cert.fechaFin.month, 1);
    while (!cursor.isAfter(limite) && nuevas.length < 24) {
      final etiqueta = "${_meses[cursor.month - 1][0].toUpperCase()}${_meses[cursor.month - 1].substring(1)} ${cursor.year}";
      nuevas.add(anteriores[etiqueta] ?? MesCertificacion(mes: etiqueta));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    setState(() => _cert.datosMensuales = nuevas);
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final actual = esInicio ? _cert.fechaInicio : _cert.fechaFin;
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 1),
      helpText: esInicio ? "Inicio del periodo" : "Fin del periodo",
    );
    if (elegida == null) return;
    setState(() {
      if (esInicio) {
        _cert.fechaInicio = DateTime(elegida.year, elegida.month, 1);
      } else {
        _cert.fechaFin = DateTime(elegida.year, elegida.month + 1, 0);
      }
    });
    _regenerarTabla();
  }

  void _aplicarPorcentajeATodos() {
    final porcentaje = double.tryParse(_porcentajeCtrl.text.replaceAll(',', '.'));
    if (porcentaje == null) return;
    setState(() {
      for (final m in _cert.datosMensuales) {
        m.egresos = m.ingresos * (porcentaje / 100);
      }
    });
  }

  String get _simboloMoneda => switch (_cert.moneda) {
        'USD' => r'$',
        'EUR' => '€',
        _ => '₡',
      };

  double get _promedioIngresos {
    if (_cert.datosMensuales.isEmpty) return 0;
    return _cert.datosMensuales.map((m) => m.ingresos).reduce((a, b) => a + b) / _cert.datosMensuales.length;
  }

  double get _promedioNeto {
    if (_cert.datosMensuales.isEmpty) return 0;
    return _cert.datosMensuales.map((m) => m.total).reduce((a, b) => a + b) / _cert.datosMensuales.length;
  }

  bool _validar() {
    if (_nombreCtrl.text.trim().isEmpty ||
        _cedulaCtrl.text.trim().isEmpty ||
        _actividadCtrl.text.trim().isEmpty ||
        _propositoCtrl.text.trim().isEmpty ||
        _dirigidoACtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Completá al menos nombre, cédula, actividad, propósito y a quién va dirigida.")),
      );
      return false;
    }
    return true;
  }

  Future<void> _guardar({required bool luegoDescargarPdf, bool luegoDescargarWord = false}) async {
    if (!_validar()) return;
    setState(() => _guardando = true);
    _cert
      ..nombreSolicitante = _nombreCtrl.text.trim()
      ..cedula = _cedulaCtrl.text.trim()
      ..tipoCedulaTexto = _tipoCedulaCtrl.text.trim()
      ..nacionalidad = _nacionalidadCtrl.text.trim()
      ..actividadEconomica = _actividadCtrl.text.trim()
      ..numeroActividadEconomica = _numeroActividadCtrl.text.trim()
      ..anosEjerciendo = int.tryParse(_anosCtrl.text.trim())
      ..proposito = _propositoCtrl.text.trim()
      ..dirigidoA = _dirigidoACtrl.text.trim()
      ..lugarEmision = _lugarCtrl.text.trim().isEmpty ? 'San José' : _lugarCtrl.text.trim()
      ..porcentajeEgresos = double.tryParse(_porcentajeCtrl.text.replaceAll(',', '.'));

    try {
      final body = {
        ..._cert.toJson(),
        if (_clienteExistente && _negocioSeleccionado != null) 'negocio': _negocioSeleccionado!.id,
      };
      final esNueva = _cert.id == null;
      final response = esNueva
          ? await ApiService.post('/certificaciones-ingreso/', body)
          : await ApiService.patch('/certificaciones-ingreso/${_cert.id}/', body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        _cert = CertificacionIngreso.fromJson(data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Certificación guardada"), backgroundColor: Colors.green),
          );
        }
        if (luegoDescargarPdf) await _descargar('pdf');
        if (luegoDescargarWord) await _descargar('word');
        if (mounted) Navigator.pop(context, true);
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _descargar(String formato) async {
    if (_cert.id == null) return;
    try {
      final response = await ApiService.get('/certificaciones-ingreso/${_cert.id}/$formato/');
      if (response.statusCode == 200 && mounted) {
        final nombreArchivo = "certificacion_ingresos_${_cert.id}.${formato == 'pdf' ? 'pdf' : 'docx'}";
        if (kIsWeb) {
          descargarBytesEnNavegador(response.bodyBytes, nombreArchivo);
        } else {
          await FilePicker.platform.saveFile(fileName: nombreArchivo, bytes: response.bodyBytes);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo descargar: $e")));
      }
    }
  }

  InputDecoration _decoracion(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: TemaContador.textoTenue),
        filled: true,
        fillColor: TemaContador.superficie,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte),
          tooltip: "Volver",
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _cert.id == null ? "Nueva certificación" : "Editar certificación",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte),
        ),
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
              titulo: "¿Para quién es la certificación?",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text("Cliente nuevo")),
                      ButtonSegment(value: true, label: Text("Cliente de mi cartera")),
                    ],
                    selected: {_clienteExistente},
                    onSelectionChanged: (s) => setState(() {
                      _clienteExistente = s.first;
                      if (!_clienteExistente) _negocioSeleccionado = null;
                    }),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: TemaContador.acento,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: TemaContador.textoFuerte,
                      side: const BorderSide(color: TemaContador.borde),
                    ),
                  ),
                  if (_clienteExistente) ...[
                    const SizedBox(height: 12),
                    _cargandoNegocios
                        ? const LinearProgressIndicator()
                        : DropdownButtonFormField<Negocio>(
                            initialValue: _negocioSeleccionado,
                            decoration: _decoracion("Elegí el cliente"),
                            items: _negocios
                                .map((n) => DropdownMenuItem(value: n, child: Text(n.nombreComercial, overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: _prefillDesdeNegocio,
                          ),
                  ],
                ],
              ),
            ),
            _tarjeta(
              titulo: "Datos del solicitante",
              child: Column(
                children: [
                  TextField(controller: _nombreCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Nombre completo *")),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _cedulaCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Cédula *"))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _tipoCedulaCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Tipo (física, española...)"))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _nacionalidadCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Nacionalidad"))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _cert.estadoCivil,
                        decoration: _decoracion("Estado civil"),
                        items: CertificacionIngreso.estadosCiviles.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => setState(() => _cert.estadoCivil = v ?? 'soltero'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: _actividadCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Actividad económica *")),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _numeroActividadCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("N.° de actividad económica"))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _anosCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Años ejerciéndola"))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: _propositoCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Propósito de la certificación *")),
                  const SizedBox(height: 10),
                  TextField(controller: _dirigidoACtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Dirigido a (ej: Banco Nacional) *")),
                  const SizedBox(height: 10),
                  TextField(controller: _lugarCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Lugar de emisión")),
                ],
              ),
            ),
            _tarjeta(
              titulo: "Periodo y moneda",
              child: Column(
                children: [
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _elegirFecha(esInicio: true),
                        child: InputDecorator(
                          decoration: _decoracion("Desde"),
                          child: Text("${_cert.fechaInicio.month}/${_cert.fechaInicio.year}", style: const TextStyle(color: TemaContador.textoFuerte)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _elegirFecha(esInicio: false),
                        child: InputDecorator(
                          decoration: _decoracion("Hasta"),
                          child: Text("${_cert.fechaFin.month}/${_cert.fechaFin.year}", style: const TextStyle(color: TemaContador.textoFuerte)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        initialValue: _cert.moneda,
                        decoration: _decoracion("Moneda"),
                        items: const [
                          DropdownMenuItem(value: 'CRC', child: Text('₡ CRC')),
                          DropdownMenuItem(value: 'USD', child: Text('\$ USD')),
                          DropdownMenuItem(value: 'EUR', child: Text('€ EUR')),
                        ],
                        onChanged: (v) => setState(() => _cert.moneda = v ?? 'CRC'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            _tarjeta(
              titulo: "Ingresos y egresos mensuales",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'manual', label: Text("Egresos manuales")),
                      ButtonSegment(value: 'porcentaje', label: Text("Egresos por %")),
                    ],
                    selected: {_cert.modoEgresos},
                    onSelectionChanged: (s) => setState(() => _cert.modoEgresos = s.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: TemaContador.acento,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: TemaContador.textoFuerte,
                      side: const BorderSide(color: TemaContador.borde),
                    ),
                  ),
                  if (_cert.modoEgresos == 'porcentaje') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _porcentajeCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: TemaContador.textoFuerte),
                            decoration: _decoracion("% de egresos sobre los ingresos"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white),
                          onPressed: _aplicarPorcentajeATodos,
                          child: const Text("Aplicar a todos"),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(TemaContador.superficie),
                      columns: const [
                        DataColumn(label: Text("Mes")),
                        DataColumn(label: Text("Ingresos"), numeric: true),
                        DataColumn(label: Text("Egresos"), numeric: true),
                        DataColumn(label: Text("Total"), numeric: true),
                      ],
                      rows: _cert.datosMensuales.map((m) {
                        return DataRow(cells: [
                          DataCell(Text(m.mes, style: const TextStyle(color: TemaContador.textoFuerte))),
                          DataCell(SizedBox(
                            width: 110,
                            child: TextFormField(
                              initialValue: m.ingresos == 0 ? '' : m.ingresos.toStringAsFixed(0),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                              onChanged: (v) {
                                m.ingresos = double.tryParse(v.replaceAll(',', '')) ?? 0;
                                if (_cert.modoEgresos == 'porcentaje') {
                                  final porcentaje = double.tryParse(_porcentajeCtrl.text.replaceAll(',', '.'));
                                  if (porcentaje != null) m.egresos = m.ingresos * (porcentaje / 100);
                                }
                                setState(() {});
                              },
                            ),
                          )),
                          DataCell(SizedBox(
                            width: 110,
                            child: TextFormField(
                              key: ValueKey('egr-${m.mes}-${m.egresos}'),
                              initialValue: m.egresos == 0 ? '' : m.egresos.toStringAsFixed(0),
                              enabled: _cert.modoEgresos == 'manual',
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                              onChanged: (v) => setState(() => m.egresos = double.tryParse(v.replaceAll(',', '')) ?? 0),
                            ),
                          )),
                          DataCell(Text("$_simboloMoneda${m.total.toStringAsFixed(0)}", style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold))),
                        ]);
                      }).toList(),
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Ingreso bruto promedio mensual", style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12)),
                      Text("$_simboloMoneda${_promedioIngresos.toStringAsFixed(2)}", style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Ingreso neto promedio mensual", style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12)),
                      Text("$_simboloMoneda${_promedioNeto.toStringAsFixed(2)}", style: const TextStyle(color: TemaContador.acento, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
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
                  style: OutlinedButton.styleFrom(foregroundColor: TemaContador.acento, side: const BorderSide(color: TemaContador.acento)),
                  onPressed: _guardando ? null : () => _guardar(luegoDescargarPdf: false),
                  child: const Text("Guardar"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white),
                  onPressed: _guardando ? null : () => _guardar(luegoDescargarPdf: true),
                  icon: _guardando
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text("Guardar y PDF"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: TemaContador.textoFuerte, foregroundColor: Colors.white),
                  onPressed: _guardando ? null : () => _guardar(luegoDescargarPdf: false, luegoDescargarWord: true),
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

  Widget _tarjeta({required String titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaContador.fondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemaContador.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: TemaContador.textoFuerte)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

