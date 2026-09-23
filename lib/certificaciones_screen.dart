import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'certificacion_ingreso.dart';
import 'descarga_navegador_stub.dart' if (dart.library.html) 'descarga_navegador_web.dart';
import 'firmante_contador.dart';
import 'firmante_selector.dart';
import 'negocio.dart';
import 'socio.dart';

/// Nombre de archivo legible para una certificación: el nombre del
/// solicitante en vez de un id suelto.
String _nombreArchivoCertificacion(CertificacionIngreso cert, String formato) {
  final solicitante = cert.nombreSolicitante.trim();
  var nombre = solicitante.isEmpty ? 'certificacion_ingresos_${cert.id}' : solicitante;
  nombre = nombre.replaceAll(RegExp(r'[\\/*?:"<>|]'), '');
  return '$nombre.${formato == 'pdf' ? 'pdf' : 'docx'}';
}

/// Descarga una certificación ya guardada en PDF o Word -- compartida entre
/// la lista (descarga rápida sin abrir el formulario) y el formulario
/// (botones "Guardar y PDF"/"Guardar y Word").
Future<void> descargarCertificacion(BuildContext context, CertificacionIngreso cert, String formato) async {
  try {
    final response = await ApiService.get('/certificaciones-ingreso/${cert.id}/$formato/');
    if (response.statusCode == 200) {
      final nombreArchivo = _nombreArchivoCertificacion(cert, formato);
      if (kIsWeb) {
        descargarBytesEnNavegador(response.bodyBytes, nombreArchivo);
      } else {
        await FilePicker.platform.saveFile(fileName: nombreArchivo, bytes: response.bodyBytes);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo descargar (HTTP ${response.statusCode}).")));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo descargar: $e")));
    }
  }
}

/// Pregunta PDF o Word y comparte esa certificación por el selector nativo
/// (WhatsApp, correo, etc.) en vez de solo descargarla.
Future<void> compartirCertificacion(BuildContext context, CertificacionIngreso cert) async {
  final formato = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: TemaContador.fondo,
      title: const Text("¿En qué formato?", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 16)),
      content: const Text("Elegí cómo querés compartir esta certificación.", style: TextStyle(color: TemaContador.textoTenue)),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
          onPressed: () => Navigator.pop(context, 'pdf'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text("PDF"),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
          onPressed: () => Navigator.pop(context, 'word'),
          icon: const Icon(Icons.description_outlined),
          label: const Text("Word"),
        ),
      ],
    ),
  );
  if (formato == null || !context.mounted) return;
  try {
    final response = await ApiService.get('/certificaciones-ingreso/${cert.id}/$formato/');
    if (response.statusCode == 200) {
      final nombreArchivo = _nombreArchivoCertificacion(cert, formato);
      final mimeType = formato == 'pdf'
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      await Share.shareXFiles(
        [XFile.fromData(response.bodyBytes, name: nombreArchivo, mimeType: mimeType)],
        text: 'Certificación de ingresos de ${cert.nombreSolicitante}.',
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo compartir (HTTP ${response.statusCode}).")));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo compartir: $e")));
    }
  }
}

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
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  /// Las últimas 3 emitidas primero (para encontrar rápido lo recién
  /// hecho), y de ahí para abajo en orden alfabético por nombre del
  /// solicitante -- pedido explícito del usuario, no solo lo más nuevo
  /// primero como antes.
  List<CertificacionIngreso> get _certificacionesOrdenadas {
    final copia = [..._certificaciones]
      ..sort((a, b) => (b.creadoEn ?? DateTime(0)).compareTo(a.creadoEn ?? DateTime(0)));
    final recientes = copia.take(3).toList();
    final resto = copia.skip(3).toList()
      ..sort((a, b) => a.nombreSolicitante.toLowerCase().compareTo(b.nombreSolicitante.toLowerCase()));
    return [...recientes, ...resto];
  }

  List<CertificacionIngreso> get _certificacionesFiltradas {
    final ordenadas = _certificacionesOrdenadas;
    if (_busqueda.isEmpty) return ordenadas;
    return ordenadas.where((c) => c.nombreSolicitante.toLowerCase().contains(_busqueda)).toList();
  }

  @override
  void initState() {
    super.initState();
    _busquedaCtrl.addListener(() => setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase()));
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
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
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: TextField(
                        controller: _busquedaCtrl,
                        style: const TextStyle(color: TemaContador.textoFuerte),
                        decoration: InputDecoration(
                          hintText: "Buscar por nombre...",
                          hintStyle: const TextStyle(color: TemaContador.textoTenue),
                          prefixIcon: const Icon(Icons.search, color: TemaContador.textoTenue),
                          suffixIcon: _busqueda.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, color: TemaContador.textoTenue),
                                  onPressed: () => _busquedaCtrl.clear(),
                                ),
                          filled: true,
                          fillColor: TemaContador.superficie,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _certificacionesFiltradas.isEmpty
                          ? Center(
                              child: Text(
                                "No se encontraron certificaciones con ese nombre.",
                                style: const TextStyle(color: TemaContador.textoTenue),
                              ),
                            )
                          : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _certificacionesFiltradas.length,
                    itemBuilder: (context, index) {
                      final c = _certificacionesFiltradas[index];
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_outlined, color: TemaContador.textoTenue),
                                tooltip: "Descargar PDF",
                                onPressed: () => descargarCertificacion(context, c, 'pdf'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.description_outlined, color: TemaContador.textoTenue),
                                tooltip: "Descargar Word",
                                onPressed: () => descargarCertificacion(context, c, 'word'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_outlined, color: TemaContador.textoTenue),
                                tooltip: "Compartir",
                                onPressed: () => compartirCertificacion(context, c),
                              ),
                              const Icon(Icons.chevron_right, color: TemaContador.acento),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => CertificacionFormScreen(certificacion: c)),
                          ),
                        ),
                      );
                    },
                  ),
                        ),
                    ),
                  ],
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
  bool _analizandoSolicitante = false;
  bool _cargandoEstadosCuenta = false;
  String _progresoEstadosCuenta = '';
  List<Negocio> _negocios = [];
  Negocio? _negocioSeleccionado;
  bool _firmarConNombreRegistrado = true;
  List<FirmanteContador> _firmantes = [];

  // Un controlador/focus estable POR CELDA (clave = "mes#índice de
  // actividad", nunca el monto) para la tabla de 12 meses -- usar el
  // monto como parte de la key del TextFormField (como se hizo al
  // principio) recreaba el widget en cada dígito tecleado y perdía el
  // foco a cada rato. Con un controlador fijo, escribir un valor con
  // código externo (ver _sincronizarCeldasMes) solo actualiza el texto,
  // sin reconstruir nada. Los egresos son uno solo por mes (clave = mes).
  final Map<String, TextEditingController> _ingresosCtrls = {};
  final Map<String, TextEditingController> _egresosCtrls = {};
  final Map<String, FocusNode> _ingresosFocus = {};
  final Map<String, FocusNode> _egresosFocus = {};

  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _tipoCedulaCtrl = TextEditingController();
  final _nacionalidadCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _actividadCtrl = TextEditingController();
  // Actividades ADICIONALES a la principal (_actividadCtrl) -- cuando hay
  // al menos una, la tabla de 12 meses muestra una columna de ingresos por
  // cada actividad en vez de una sola. Ver _actividadesActuales.
  final List<TextEditingController> _actividadesExtraCtrls = [];
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
    _direccionCtrl.text = _cert.direccion;
    _actividadCtrl.text = _cert.actividadEconomica;
    if (_cert.actividades.length > 1) {
      for (final a in _cert.actividades.skip(1)) {
        _actividadesExtraCtrls.add(TextEditingController(text: a));
      }
    }
    _numeroActividadCtrl.text = _cert.numeroActividadEconomica;
    _anosCtrl.text = _cert.anosEjerciendo?.toString() ?? '';
    _propositoCtrl.text = _cert.proposito;
    _dirigidoACtrl.text = _cert.dirigidoA;
    _lugarCtrl.text = _cert.lugarEmision;
    _porcentajeCtrl.text = _cert.porcentajeEgresos?.toString() ?? '';
    if (_cert.datosMensuales.isEmpty) _regenerarTabla();
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
    _tipoCedulaCtrl.dispose();
    _nacionalidadCtrl.dispose();
    _direccionCtrl.dispose();
    _actividadCtrl.dispose();
    _numeroActividadCtrl.dispose();
    _anosCtrl.dispose();
    _propositoCtrl.dispose();
    _dirigidoACtrl.dispose();
    _lugarCtrl.dispose();
    _porcentajeCtrl.dispose();
    for (final c in _actividadesExtraCtrls) {
      c.dispose();
    }
    for (final c in _ingresosCtrls.values) {
      c.dispose();
    }
    for (final c in _egresosCtrls.values) {
      c.dispose();
    }
    for (final f in _ingresosFocus.values) {
      f.dispose();
    }
    for (final f in _egresosFocus.values) {
      f.dispose();
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
    // Los controladores/focus de meses que ya no quedan en la tabla (el
    // contador acortó el periodo) se liberan; los demás se conservan tal
    // cual -- así no se pierde lo que ya estaba tecleado en esos meses.
    final etiquetasNuevas = nuevas.map((m) => m.mes).toSet();
    // _ingresosCtrls/_ingresosFocus están indexados como "mes#actividad";
    // _egresosCtrls/_egresosFocus son uno por mes directo.
    for (final clave in _ingresosCtrls.keys.where((k) => !etiquetasNuevas.contains(k.split('#').first)).toList()) {
      _ingresosCtrls.remove(clave)?.dispose();
      _ingresosFocus.remove(clave)?.dispose();
    }
    for (final clave in _egresosCtrls.keys.where((k) => !etiquetasNuevas.contains(k)).toList()) {
      _egresosCtrls.remove(clave)?.dispose();
      _egresosFocus.remove(clave)?.dispose();
    }
    setState(() => _cert.datosMensuales = nuevas);
    _sincronizarActividadesEnTabla();
  }

  /// Actividades a certificar tal como están AHORA en los campos de texto
  /// (la principal + las adicionales que se hayan agregado). Se usa tanto
  /// para las columnas de la tabla como para lo que se manda a guardar --
  /// nunca hace falta mantener esto sincronizado aparte en _cert.
  List<String> get _actividadesActuales {
    final principal = _actividadCtrl.text.trim();
    final extras = _actividadesExtraCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty);
    final lista = [if (principal.isNotEmpty) principal, ...extras];
    return lista.isEmpty ? const ['Ingresos'] : lista;
  }

  bool get _multiActividad => _actividadesActuales.length > 1;

  /// Ajusta ingresosPorActividad de cada mes a la cantidad actual de
  /// actividades -- por POSICIÓN, no por nombre, para que renombrar una
  /// actividad no le borre el monto ya cargado. Si se agregó una
  /// actividad, la nueva columna arranca en 0; si se quitó, ese monto se
  /// pierde (es lo esperado: esa columna ya no existe).
  void _sincronizarActividadesEnTabla() {
    final cantidad = _actividadesActuales.length;
    setState(() {
      for (final m in _cert.datosMensuales) {
        final valores = m.ingresosPorActividad;
        if (valores.length == cantidad) continue;
        final nuevos = List<double>.generate(cantidad, (i) => i < valores.length ? valores[i] : 0);
        m.ingresosPorActividad = nuevos;
      }
    });
  }

  void _agregarActividad() {
    setState(() => _actividadesExtraCtrls.add(TextEditingController()));
    _sincronizarActividadesEnTabla();
  }

  void _quitarActividad(int index) {
    final ctrl = _actividadesExtraCtrls.removeAt(index);
    ctrl.dispose();
    _sincronizarActividadesEnTabla();
  }

  String _formatoMonto(double valor) => valor == 0 ? '' : valor.toStringAsFixed(0);

  TextEditingController _ctrlIngresos(MesCertificacion m, int actividadIndex) => _ingresosCtrls.putIfAbsent(
        '${m.mes}#$actividadIndex',
        () => TextEditingController(
          text: _formatoMonto(actividadIndex < m.ingresosPorActividad.length ? m.ingresosPorActividad[actividadIndex] : 0),
        ),
      );

  TextEditingController _ctrlEgresos(MesCertificacion m) =>
      _egresosCtrls.putIfAbsent(m.mes, () => TextEditingController(text: _formatoMonto(m.egresos)));

  FocusNode _focusIngresos(MesCertificacion m, int actividadIndex) => _ingresosFocus.putIfAbsent('${m.mes}#$actividadIndex', () => FocusNode());

  FocusNode _focusEgresos(MesCertificacion m) => _egresosFocus.putIfAbsent(m.mes, () => FocusNode());

  /// Refleja los montos de m en los controladores de la tabla cuando el
  /// cambio vino de CÓDIGO (extracción por IA, aplicar % a todos), no de
  /// que el contador esté tecleando ese campo -- así no hace falta
  /// reconstruir el TextFormField (que es lo que perdía el foco antes).
  void _sincronizarCeldasMes(MesCertificacion m) {
    for (var i = 0; i < m.ingresosPorActividad.length; i++) {
      final c = _ingresosCtrls['${m.mes}#$i'];
      if (c != null) c.text = _formatoMonto(m.ingresosPorActividad[i]);
    }
    final cEgr = _egresosCtrls[m.mes];
    if (cEgr != null) cEgr.text = _formatoMonto(m.egresos);
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
        _sincronizarCeldasMes(m);
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
    if (!_firmarConNombreRegistrado && _firmantes.isNotEmpty && _cert.firmante == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Elegí quién firma este documento.")),
      );
      return false;
    }
    return true;
  }

  Future<void> _guardar({
    required bool luegoDescargarPdf,
    bool luegoDescargarWord = false,
    bool quedarseEnPantalla = false,
  }) async {
    if (!_validar()) return;
    setState(() => _guardando = true);
    _cert
      ..nombreSolicitante = _nombreCtrl.text.trim()
      ..cedula = _cedulaCtrl.text.trim()
      ..tipoCedulaTexto = _tipoCedulaCtrl.text.trim()
      ..nacionalidad = _nacionalidadCtrl.text.trim()
      ..direccion = _direccionCtrl.text.trim()
      ..actividadEconomica = _actividadCtrl.text.trim()
      ..actividades = _actividadesActuales
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
        if (!quedarseEnPantalla && mounted) Navigator.pop(context, true);
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
    await descargarCertificacion(context, _cert, formato);
  }

  /// Aplica lo que devolvió Claude a los controladores del formulario --
  /// nunca pisa un campo que Claude no pudo identificar (viene null), y
  /// avisa cuántos campos se llenaron para que el contador sepa qué
  /// revisar antes de guardar.
  void _aplicarDatosSolicitante(Map<String, dynamic> datos) {
    final aplicados = <String>[];
    void set(TextEditingController ctrl, String campo, String etiqueta) {
      final valor = datos[campo];
      if (valor != null && valor.toString().trim().isNotEmpty) {
        ctrl.text = valor.toString();
        aplicados.add(etiqueta);
      }
    }

    set(_nombreCtrl, 'nombre_solicitante', 'Nombre');
    set(_cedulaCtrl, 'cedula', 'Cédula');
    set(_tipoCedulaCtrl, 'tipo_cedula_texto', 'Tipo de cédula');
    set(_nacionalidadCtrl, 'nacionalidad', 'Nacionalidad');
    set(_direccionCtrl, 'direccion', 'Dirección');
    set(_actividadCtrl, 'actividad_economica', 'Actividad económica');
    set(_numeroActividadCtrl, 'numero_actividad_economica', 'N.° de actividad');
    set(_propositoCtrl, 'proposito', 'Propósito');
    set(_dirigidoACtrl, 'dirigido_a', 'Dirigido a');
    if (datos['anos_ejerciendo'] != null) {
      _anosCtrl.text = datos['anos_ejerciendo'].toString();
      aplicados.add('Años ejerciendo');
    }
    final estadoCivil = datos['estado_civil']?.toString();
    if (estadoCivil != null && CertificacionIngreso.estadosCiviles.containsKey(estadoCivil)) {
      setState(() => _cert.estadoCivil = estadoCivil);
      aplicados.add('Estado civil');
    }
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            aplicados.isEmpty ? "No se identificó ningún dato en ese material." : "Se llenaron: ${aplicados.join(', ')}. Revisalos antes de guardar.",
          ),
        ),
      );
    }
  }

  Future<void> _analizarImagenSolicitante() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final archivos = resultado?.files ?? [];
    if (archivos.isEmpty || archivos.first.bytes == null) return;
    final archivo = archivos.first;
    setState(() => _analizandoSolicitante = true);
    try {
      final extension = (archivo.extension ?? 'jpg').toLowerCase();
      final mimeType = extension == 'png' ? 'image/png' : (extension == 'webp' ? 'image/webp' : 'image/jpeg');
      final response = await ApiService.postMultipartBytes(
        '/certificaciones-ingreso/extraer-datos-solicitante/',
        {},
        'imagen',
        archivo.bytes!,
        archivo.name,
        contentType: mimeType,
      );
      if (response.statusCode == 200) {
        _aplicarDatosSolicitante(json.decode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception(json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo analizar la imagen: $e")));
    } finally {
      if (mounted) setState(() => _analizandoSolicitante = false);
    }
  }

  Future<void> _analizarTextoSolicitante() async {
    final textoCtrl = TextEditingController();
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pegar texto"),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: textoCtrl,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Pegá acá el mensaje o los datos que te mandó el cliente (ej. por WhatsApp)...",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, textoCtrl.text.trim()),
            child: const Text("Analizar"),
          ),
        ],
      ),
    );
    if (texto == null || texto.isEmpty) return;
    setState(() => _analizandoSolicitante = true);
    try {
      final response = await ApiService.post('/certificaciones-ingreso/extraer-datos-solicitante/', {'texto': texto});
      if (response.statusCode == 200) {
        _aplicarDatosSolicitante(json.decode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception(json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo analizar el texto: $e")));
    } finally {
      if (mounted) setState(() => _analizandoSolicitante = false);
    }
  }

  /// Suma [meses] (lo que Claude sugirió para UN archivo) dentro de la
  /// tabla ya construida por _regenerarTabla(), por etiqueta de mes -- si
  /// dos estados de cuenta distintos cubren el mismo mes (dos cuentas del
  /// mismo cliente), sus montos se suman en vez de pisarse.
  /// Los estados de cuenta bancarios no distinguen a qué actividad
  /// económica corresponde cada movimiento, así que la IA siempre suma
  /// todo en la PRIMERA actividad (índice 0) -- si el contador certifica
  /// varias, tiene que repartir manualmente cuánto es de cada una.
  void _mezclarMesesSugeridos(List meses) {
    // En modo "egresos por %" los egresos NUNCA vienen del estado de
    // cuenta -- si el porcentaje ya está puesto se recalculan a partir de
    // los ingresos nuevos, y si no, se dejan en 0 (el campo de egresos ya
    // aparece deshabilitado en la tabla en ese modo) para no confundir con
    // un monto real que no tiene nada que ver con el % que se va a usar.
    final porcentaje = _cert.modoEgresos == 'porcentaje' ? double.tryParse(_porcentajeCtrl.text.replaceAll(',', '.')) : null;
    for (final m in meses) {
      final etiqueta = (m['mes'] ?? '').toString();
      final ingresos = (m['ingresos'] as num?)?.toDouble() ?? 0;
      final egresos = (m['egresos'] as num?)?.toDouble() ?? 0;
      final existente = _cert.datosMensuales.where((fila) => fila.mes.toLowerCase() == etiqueta.toLowerCase());
      MesCertificacion fila;
      if (existente.isNotEmpty) {
        fila = existente.first;
        if (fila.ingresosPorActividad.isEmpty) fila.ingresosPorActividad = [0];
        fila.ingresosPorActividad[0] += ingresos;
      } else {
        fila = MesCertificacion(mes: etiqueta, ingresosPorActividad: [ingresos]);
        _cert.datosMensuales.add(fila);
      }
      if (_cert.modoEgresos == 'manual') {
        fila.egresos += egresos;
      } else if (porcentaje != null) {
        fila.egresos = fila.ingresos * (porcentaje / 100);
      }
      _sincronizarCeldasMes(fila);
    }
  }

  String? _mimeTypePorExtension(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'xlsx':
      case 'xlsm':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return null;
    }
  }

  Future<void> _cargarEstadosCuenta() async {
    // La extracción va atada a una certificación ya guardada (se sube como
    // adjunto de ella) -- si todavía es nueva, la guardamos primero en
    // silencio para tener un id antes de subir archivos.
    if (_cert.id == null) {
      if (!_validar()) return;
      await _guardar(luegoDescargarPdf: false, quedarseEnPantalla: true);
      if (_cert.id == null) return;
    }
    final resultado = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'xlsm', 'xls', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final archivos = resultado?.files ?? [];
    if (archivos.isEmpty) return;

    setState(() => _cargandoEstadosCuenta = true);
    var procesados = 0;
    final errores = <String>[];
    for (final archivo in archivos) {
      if (archivo.bytes == null) continue;
      procesados++;
      setState(() => _progresoEstadosCuenta = "Analizando $procesados de ${archivos.length}: ${archivo.name}");
      try {
        final response = await ApiService.postMultipartBytes(
          '/certificaciones-ingreso/${_cert.id}/adjuntos-con-extraccion/',
          {},
          'archivo',
          archivo.bytes!,
          archivo.name,
          contentType: _mimeTypePorExtension(archivo.extension),
        );
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          final meses = (data['meses_sugeridos'] as List?) ?? [];
          if (meses.isEmpty && data['error'] != null) {
            errores.add("${archivo.name}: ${data['error']}");
          } else {
            setState(() => _mezclarMesesSugeridos(meses));
          }
        } else {
          errores.add("${archivo.name}: HTTP ${response.statusCode}");
        }
      } catch (e) {
        errores.add("${archivo.name}: $e");
      }
    }
    setState(() {
      _cargandoEstadosCuenta = false;
      _progresoEstadosCuenta = '';
    });
    final faltaPorcentaje = _cert.modoEgresos == 'porcentaje' && _porcentajeCtrl.text.trim().isEmpty;
    if (mounted) {
      if (errores.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              faltaPorcentaje
                  ? "Se analizaron $procesados archivo(s) (solo ingresos). Escribí el % de egresos arriba de la tabla y tocá \"Aplicar a todos\"."
                  : "Se analizaron $procesados archivo(s). Revisá la tabla antes de generar el documento.",
            ),
            duration: Duration(seconds: faltaPorcentaje ? 6 : 4),
          ),
        );
      } else {
        // Los errores reales (ej. "el modelo no pudo leer el PDF") importan
        // más que un simple contador -- por eso van en un diálogo que se
        // puede leer con calma, no en un SnackBar que desaparece solo.
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("${errores.length} de $procesados archivo(s) con error"),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(child: Text(errores.join('\n\n'))),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendido"))],
          ),
        );
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
                            style: const TextStyle(color: TemaContador.textoFuerte),
                            dropdownColor: TemaContador.fondo,
                            items: _negocios
                                .map((n) => DropdownMenuItem(
                                      value: n,
                                      child: Text(n.nombreComercial, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TemaContador.textoFuerte)),
                                    ))
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _analizandoSolicitante ? null : _analizarImagenSolicitante,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TemaContador.acento,
                            disabledForegroundColor: TemaContador.textoTenue,
                            side: const BorderSide(color: TemaContador.acento),
                          ),
                          icon: _analizandoSolicitante
                              ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.image_outlined, size: 18),
                          label: const Text("Leer imagen/captura"),
                        ),
                        OutlinedButton.icon(
                          onPressed: _analizandoSolicitante ? null : _analizarTextoSolicitante,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TemaContador.acento,
                            disabledForegroundColor: TemaContador.textoTenue,
                            side: const BorderSide(color: TemaContador.acento),
                          ),
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: const Text("Pegar texto"),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Subí una captura (ej. de WhatsApp) o pegá el texto y la IA prellena estos campos -- siempre revisalos antes de guardar.",
                      style: TextStyle(fontSize: 11.5, color: TemaContador.textoTenue),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        style: const TextStyle(color: TemaContador.textoFuerte),
                        dropdownColor: TemaContador.fondo,
                        items: CertificacionIngreso.estadosCiviles.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: TemaContador.textoFuerte))))
                            .toList(),
                        onChanged: (v) => setState(() => _cert.estadoCivil = v ?? 'soltero'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: _direccionCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Dirección")),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _actividadCtrl,
                    style: const TextStyle(color: TemaContador.textoFuerte),
                    decoration: _decoracion("Actividad económica *"),
                    onChanged: (_) => _sincronizarActividadesEnTabla(),
                  ),
                  if (_actividadesExtraCtrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ..._actividadesExtraCtrls.asMap().entries.map((entry) {
                      final i = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                style: const TextStyle(color: TemaContador.textoFuerte),
                                decoration: _decoracion("Otra actividad económica"),
                                onChanged: (_) => _sincronizarActividadesEnTabla(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: TemaContador.textoTenue),
                              tooltip: "Quitar actividad",
                              onPressed: () => _quitarActividad(i),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _agregarActividad,
                      style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text("Agregar otra actividad económica"),
                    ),
                  ),
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
                  selectorFirmante(
                    firmarConNombreRegistrado: _firmarConNombreRegistrado,
                    firmantes: _firmantes,
                    firmanteSeleccionado: _cert.firmante,
                    onChanged: (v) => setState(() => _cert.firmante = v),
                  ),
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
                        style: const TextStyle(color: TemaContador.textoFuerte),
                        dropdownColor: TemaContador.fondo,
                        items: const [
                          DropdownMenuItem(value: 'CRC', child: Text('₡ CRC', style: TextStyle(color: TemaContador.textoFuerte))),
                          DropdownMenuItem(value: 'USD', child: Text('\$ USD', style: TextStyle(color: TemaContador.textoFuerte))),
                          DropdownMenuItem(value: 'EUR', child: Text('€ EUR', style: TextStyle(color: TemaContador.textoFuerte))),
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _cargandoEstadosCuenta ? null : _cargarEstadosCuenta,
                      style: OutlinedButton.styleFrom(
                            foregroundColor: TemaContador.acento,
                            disabledForegroundColor: TemaContador.textoTenue,
                            side: const BorderSide(color: TemaContador.acento),
                          ),
                      icon: _cargandoEstadosCuenta
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(_cargandoEstadosCuenta ? _progresoEstadosCuenta : "Cargar estados de cuenta (IA)"),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Subí los estados de cuenta (PDF/Excel) del cliente -- la IA suma ingresos y egresos por mes. Podés seleccionar varios de una vez.",
                    style: TextStyle(fontSize: 11.5, color: TemaContador.textoTenue),
                  ),
                  const SizedBox(height: 12),
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
                  if (_cert.modoEgresos == 'porcentaje')
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _porcentajeCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: "% de egresos sobre ingresos",
                                labelStyle: const TextStyle(color: TemaContador.textoTenue),
                                floatingLabelStyle: const TextStyle(color: TemaContador.acento, fontWeight: FontWeight.w600),
                                filled: true,
                                fillColor: TemaContador.superficie,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
                              ),
                              onChanged: (_) => _aplicarPorcentajeATodos(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white),
                            onPressed: _aplicarPorcentajeATodos,
                            child: const Text("Recalcular"),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(TemaContador.superficie),
                      headingTextStyle: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 12.5),
                      dataTextStyle: const TextStyle(color: TemaContador.textoFuerte),
                      columns: [
                        const DataColumn(label: Text("Mes")),
                        for (final a in _actividadesActuales)
                          DataColumn(label: Text(_multiActividad ? "Ing.: $a" : "Ingresos"), numeric: true),
                        if (_multiActividad) const DataColumn(label: Text("Total ingresos"), numeric: true),
                        const DataColumn(label: Text("Egresos"), numeric: true),
                        const DataColumn(label: Text("Total"), numeric: true),
                      ],
                      rows: _cert.datosMensuales.map((m) {
                        // Por si la fila viene de un periodo/actividades
                        // anterior con menos columnas de las que hay ahora.
                        while (m.ingresosPorActividad.length < _actividadesActuales.length) {
                          m.ingresosPorActividad.add(0);
                        }
                        return DataRow(cells: [
                          DataCell(Text(m.mes, style: const TextStyle(color: TemaContador.textoFuerte))),
                          for (var i = 0; i < _actividadesActuales.length; i++)
                            DataCell(SizedBox(
                              width: 110,
                              child: TextFormField(
                                controller: _ctrlIngresos(m, i),
                                focusNode: _focusIngresos(m, i),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: TemaContador.textoFuerte),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: TemaContador.superficie,
                                  border: OutlineInputBorder(borderSide: const BorderSide(color: TemaContador.borde)),
                                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: TemaContador.borde)),
                                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
                                ),
                                onChanged: (v) {
                                  m.ingresosPorActividad[i] = double.tryParse(v.replaceAll(',', '')) ?? 0;
                                  if (_cert.modoEgresos == 'porcentaje') {
                                    final porcentaje = double.tryParse(_porcentajeCtrl.text.replaceAll(',', '.'));
                                    if (porcentaje != null) {
                                      m.egresos = m.ingresos * (porcentaje / 100);
                                      _egresosCtrls[m.mes]?.text = _formatoMonto(m.egresos);
                                    }
                                  }
                                  setState(() {});
                                },
                                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                              ),
                            )),
                          if (_multiActividad)
                            DataCell(Text("$_simboloMoneda${m.ingresos.toStringAsFixed(0)}", style: const TextStyle(color: TemaContador.textoFuerte))),
                          DataCell(SizedBox(
                            width: 110,
                            child: TextFormField(
                              controller: _ctrlEgresos(m),
                              focusNode: _focusEgresos(m),
                              enabled: _cert.modoEgresos == 'manual',
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: TemaContador.textoFuerte),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: TemaContador.superficie,
                                border: OutlineInputBorder(borderSide: const BorderSide(color: TemaContador.borde)),
                                enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: TemaContador.borde)),
                                disabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: TemaContador.borde)),
                                focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
                              ),
                              onChanged: (v) => setState(() => m.egresos = double.tryParse(v.replaceAll(',', '')) ?? 0),
                              onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
                  style: OutlinedButton.styleFrom(
                            foregroundColor: TemaContador.acento,
                            disabledForegroundColor: TemaContador.textoTenue,
                            side: const BorderSide(color: TemaContador.acento),
                          ),
                  onPressed: _guardando ? null : () => _guardar(luegoDescargarPdf: false),
                  child: const Text("Guardar"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemaContador.acento,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: TemaContador.acento.withOpacity(0.5),
                    disabledForegroundColor: Colors.white,
                  ),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemaContador.textoFuerte,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: TemaContador.textoFuerte.withOpacity(0.5),
                    disabledForegroundColor: Colors.white,
                  ),
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

