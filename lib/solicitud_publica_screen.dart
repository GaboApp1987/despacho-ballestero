import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'avatar_logo.dart';

/// Formulario público (SIN login) para que un cliente le pida una
/// Certificación de Ingresos a su contador -- se llega acá desde un link
/// con el código del contador embebido (equilibracr.com/app/?solicitud=CODIGO),
/// ver main.dart. Lo que se manda cae como SolicitudCertificacion en la
/// bandeja "Solicitudes" del contador correspondiente.
class SolicitudPublicaScreen extends StatefulWidget {
  final String? codigoInicial;
  const SolicitudPublicaScreen({super.key, this.codigoInicial});

  @override
  State<SolicitudPublicaScreen> createState() => _SolicitudPublicaScreenState();
}

class _SolicitudPublicaScreenState extends State<SolicitudPublicaScreen> {
  final _codigoCtrl = TextEditingController();
  bool _verificando = false;
  String? _nombreContador;
  String? _logoContador;
  String? _especialidadContador;
  String? _carneCpaContador;
  String? _errorCodigo;

  bool _enviando = false;
  bool _enviado = false;

  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _tipoCedulaCtrl = TextEditingController();
  final _nacionalidadCtrl = TextEditingController();
  String _estadoCivil = '';
  final _actividadCtrl = TextEditingController();
  final _numeroActividadCtrl = TextEditingController();
  final _anosCtrl = TextEditingController();
  final _propositoCtrl = TextEditingController();
  final _dirigidoACtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _mensajeCtrl = TextEditingController();
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String _moneda = 'CRC';
  final List<PlatformFile> _archivos = [];

  static const Map<String, String> _estadosCiviles = {
    '': 'Preferís no decirlo',
    'soltero': 'Soltero(a)',
    'casado': 'Casado(a)',
    'divorciado': 'Divorciado(a)',
    'viudo': 'Viudo(a)',
    'union_libre': 'Unión libre',
  };

  @override
  void initState() {
    super.initState();
    final codigo = widget.codigoInicial?.trim() ?? '';
    if (codigo.isNotEmpty) {
      _codigoCtrl.text = codigo.toUpperCase();
      _verificarCodigo();
    }
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _cedulaCtrl.dispose();
    _tipoCedulaCtrl.dispose();
    _nacionalidadCtrl.dispose();
    _actividadCtrl.dispose();
    _numeroActividadCtrl.dispose();
    _anosCtrl.dispose();
    _propositoCtrl.dispose();
    _dirigidoACtrl.dispose();
    _telefonoCtrl.dispose();
    _correoCtrl.dispose();
    _mensajeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificarCodigo() async {
    final codigo = _codigoCtrl.text.trim().toUpperCase();
    if (codigo.isEmpty) {
      setState(() => _errorCodigo = "Ingresá el código de tu contador.");
      return;
    }
    setState(() {
      _verificando = true;
      _errorCodigo = null;
      _nombreContador = null;
      _logoContador = null;
      _especialidadContador = null;
      _carneCpaContador = null;
    });
    try {
      final r = await ApiService.get('/solicitudes-certificacion/verificar-codigo/?codigo=$codigo');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes));
        if (mounted) {
          setState(() {
            _nombreContador = data['nombre'];
            _logoContador = data['logo'];
            _especialidadContador = data['especialidad'];
            _carneCpaContador = data['carne_cpa'];
          });
        }
      } else if (mounted) {
        setState(() => _errorCodigo = "No encontramos ningún contador con ese código. Revisalo e intentá de nuevo.");
      }
    } catch (e) {
      if (mounted) setState(() => _errorCodigo = "No se pudo verificar el código. Revisá tu conexión e intentá de nuevo.");
    }
    if (mounted) setState(() => _verificando = false);
  }

  Future<void> _elegirArchivos() async {
    final resultado = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'xlsm', 'xls', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final archivos = resultado?.files ?? [];
    if (archivos.isEmpty) return;
    setState(() => _archivos.addAll(archivos.where((a) => a.bytes != null)));
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
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: (esInicio ? _fechaInicio : _fechaFin) ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (elegida == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = elegida;
      } else {
        _fechaFin = elegida;
      }
    });
  }

  String _detalleError(List<int> bodyBytes) {
    try {
      final data = json.decode(utf8.decode(bodyBytes));
      if (data is Map && data.isNotEmpty) {
        final valor = data.values.first;
        return valor is List ? valor.join(', ') : valor.toString();
      }
      return "intentá de nuevo en un momento.";
    } catch (_) {
      return "intentá de nuevo en un momento.";
    }
  }

  Future<void> _enviar() async {
    if (_nombreCtrl.text.trim().isEmpty ||
        _cedulaCtrl.text.trim().isEmpty ||
        _actividadCtrl.text.trim().isEmpty ||
        _propositoCtrl.text.trim().isEmpty ||
        _dirigidoACtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Completá al menos nombre, cédula, actividad económica, propósito y a quién va dirigida.")),
      );
      return;
    }
    setState(() => _enviando = true);
    try {
      final campos = <String, String>{
        'codigo': _codigoCtrl.text.trim().toUpperCase(),
        'nombre_solicitante': _nombreCtrl.text.trim(),
        'cedula': _cedulaCtrl.text.trim(),
        'tipo_cedula_texto': _tipoCedulaCtrl.text.trim(),
        'nacionalidad': _nacionalidadCtrl.text.trim(),
        'estado_civil': _estadoCivil,
        'actividad_economica': _actividadCtrl.text.trim(),
        'numero_actividad_economica': _numeroActividadCtrl.text.trim(),
        'proposito': _propositoCtrl.text.trim(),
        'dirigido_a': _dirigidoACtrl.text.trim(),
        'moneda': _moneda,
        'telefono_contacto': _telefonoCtrl.text.trim(),
        'correo_contacto': _correoCtrl.text.trim(),
        'mensaje_cliente': _mensajeCtrl.text.trim(),
        if (_anosCtrl.text.trim().isNotEmpty) 'anos_ejerciendo': _anosCtrl.text.trim(),
        if (_fechaInicio != null) 'fecha_inicio': _fechaInicio!.toIso8601String().split('T').first,
        if (_fechaFin != null) 'fecha_fin': _fechaFin!.toIso8601String().split('T').first,
      };
      final response = await ApiService.postMultipartVariosArchivos(
        '/solicitudes-certificacion/publica/',
        campos,
        'archivos',
        _archivos.map((a) => (bytes: a.bytes!, filename: a.name, contentType: _mimeTypePorExtension(a.extension))).toList(),
      );
      if (response.statusCode == 201) {
        if (mounted) setState(() => _enviado = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo enviar: ${_detalleError(response.bodyBytes)}")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo enviar: $e")));
    }
    if (mounted) setState(() => _enviando = false);
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
    return Scaffold(
      backgroundColor: TemaContador.superficie,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.badge_outlined, color: TemaContador.acento, size: 26),
                      const SizedBox(width: 8),
                      const Text("Solicitud de Certificación de Ingresos", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: TemaContador.textoFuerte)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_enviado)
                    _tarjeta(
                      titulo: "¡Listo!",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Tu solicitud fue enviada a ${_nombreContador ?? 'tu contador'}. Te va a contactar en cuanto la revise.",
                            style: const TextStyle(color: TemaContador.textoFuerte),
                          ),
                        ],
                      ),
                    )
                  else if (_nombreContador == null)
                    _tarjeta(
                      titulo: "¿Quién es tu contador?",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Ingresá el código que te compartió tu contador.", style: TextStyle(color: TemaContador.textoTenue, fontSize: 12.5)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _codigoCtrl,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(color: TemaContador.textoFuerte, letterSpacing: 1.5),
                            decoration: _decoracion("Código del contador"),
                            onSubmitted: (_) => _verificarCodigo(),
                          ),
                          if (_errorCodigo != null) ...[
                            const SizedBox(height: 8),
                            Text(_errorCodigo!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                          ],
                          const SizedBox(height: 14),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
                            onPressed: _verificando ? null : _verificarCodigo,
                            child: _verificando ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Continuar"),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [TemaContador.acento.withOpacity(0.08), Colors.green.withOpacity(0.06)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: TemaContador.acento.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          avatarConLogo(
                            logoUrl: _logoContador,
                            nombre: _nombreContador,
                            icono: Icons.badge_outlined,
                            radius: 28,
                            color: TemaContador.acento,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 15),
                                  const SizedBox(width: 6),
                                  Text("Vas a solicitarle una certificación a", style: TextStyle(color: TemaContador.textoTenue, fontSize: 11.5)),
                                ]),
                                const SizedBox(height: 2),
                                Text(_nombreContador ?? '', style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.bold, fontSize: 17)),
                                const SizedBox(height: 2),
                                Text(
                                  "Contador Público Autorizado"
                                  "${(_carneCpaContador != null && _carneCpaContador!.isNotEmpty) ? ' · Carné $_carneCpaContador' : ''}",
                                  style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12),
                                ),
                                if (_especialidadContador != null && _especialidadContador!.isNotEmpty)
                                  Text(_especialidadContador!, style: const TextStyle(color: TemaContador.acento, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _tarjeta(
                      titulo: "Tus datos",
                      child: Column(
                        children: [
                          TextField(controller: _nombreCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Nombre completo *")),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: TextField(controller: _cedulaCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Cédula *"))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _tipoCedulaCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Tipo (física, jurídica...)"))),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: TextField(controller: _nacionalidadCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Nacionalidad"))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _estadoCivil,
                                decoration: _decoracion("Estado civil"),
                                style: const TextStyle(color: TemaContador.textoFuerte),
                                dropdownColor: TemaContador.fondo,
                                items: _estadosCiviles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TemaContador.textoFuerte)))).toList(),
                                onChanged: (v) => setState(() => _estadoCivil = v ?? ''),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: TextField(controller: _telefonoCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Teléfono de contacto"))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _correoCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Correo de contacto"))),
                          ]),
                        ],
                      ),
                    ),
                    _tarjeta(
                      titulo: "Actividad económica",
                      child: Column(
                        children: [
                          TextField(controller: _actividadCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("A qué te dedicás *")),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: TextField(controller: _numeroActividadCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("N.° de actividad (si lo sabés)"))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _anosCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Años ejerciendo"))),
                          ]),
                        ],
                      ),
                    ),
                    _tarjeta(
                      titulo: "Para qué es la certificación",
                      child: Column(
                        children: [
                          Row(children: [
                            Expanded(child: TextField(controller: _propositoCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Propósito (ej: trámite bancario) *"))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _dirigidoACtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Dirigida a (ej: Banco Nacional) *"))),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _elegirFecha(esInicio: true),
                                child: InputDecorator(
                                  decoration: _decoracion("Periodo desde (opcional)"),
                                  child: Text(_fechaInicio == null ? "Elegir" : "${_fechaInicio!.day}/${_fechaInicio!.month}/${_fechaInicio!.year}", style: const TextStyle(color: TemaContador.textoFuerte)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () => _elegirFecha(esInicio: false),
                                child: InputDecorator(
                                  decoration: _decoracion("Periodo hasta (opcional)"),
                                  child: Text(_fechaFin == null ? "Elegir" : "${_fechaFin!.day}/${_fechaFin!.month}/${_fechaFin!.year}", style: const TextStyle(color: TemaContador.textoFuerte)),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _moneda,
                            decoration: _decoracion("Moneda"),
                            style: const TextStyle(color: TemaContador.textoFuerte),
                            dropdownColor: TemaContador.fondo,
                            items: const [
                              DropdownMenuItem(value: 'CRC', child: Text("Colones (CRC)", style: TextStyle(color: TemaContador.textoFuerte))),
                              DropdownMenuItem(value: 'USD', child: Text("Dólares (USD)", style: TextStyle(color: TemaContador.textoFuerte))),
                            ],
                            onChanged: (v) => setState(() => _moneda = v ?? 'CRC'),
                          ),
                        ],
                      ),
                    ),
                    _tarjeta(
                      titulo: "Estados de cuenta (opcional)",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Si querés, adjuntá tus estados de cuenta -- tu contador los va a revisar.", style: TextStyle(color: TemaContador.textoTenue, fontSize: 12.5)),
                          const SizedBox(height: 10),
                          ..._archivos.asMap().entries.map((entry) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.attach_file, size: 18, color: TemaContador.textoTenue),
                                title: Text(entry.value.name, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13), overflow: TextOverflow.ellipsis),
                                trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _archivos.removeAt(entry.key))),
                              )),
                          OutlinedButton.icon(
                            onPressed: _elegirArchivos,
                            style: OutlinedButton.styleFrom(foregroundColor: TemaContador.acento, side: const BorderSide(color: TemaContador.acento)),
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text("Adjuntar estados de cuenta"),
                          ),
                        ],
                      ),
                    ),
                    _tarjeta(
                      titulo: "Algo más que quieras decirle (opcional)",
                      child: TextField(controller: _mensajeCtrl, maxLines: 3, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Comentario para tu contador")),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TemaContador.acento,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: TemaContador.acento.withOpacity(0.5),
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _enviando ? null : _enviar,
                      child: _enviando ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Enviar solicitud"),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Center(
                    child: InkWell(
                      onTap: () => launchUrl(Uri.parse('https://equilibracr.com'), mode: LaunchMode.externalApplication),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(fontSize: 11.5, color: TemaContador.textoTenue),
                          children: [
                            TextSpan(text: "Powered by "),
                            TextSpan(text: "Equilibra", style: TextStyle(fontWeight: FontWeight.bold, color: TemaContador.acento)),
                            TextSpan(text: " · equilibracr.com"),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
