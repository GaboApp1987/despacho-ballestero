import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'socio.dart';
import 'solicitud_certificacion.dart';
import 'certificacion_ingreso.dart';
import 'certificaciones_screen.dart';

/// Bandeja del contador con las solicitudes de Certificación de Ingresos
/// que sus clientes mandaron desde el link público (sin login) -- ver
/// solicitud_publica_screen.dart del lado del cliente.
class SolicitudesCertificacionScreen extends StatefulWidget {
  const SolicitudesCertificacionScreen({super.key});

  @override
  State<SolicitudesCertificacionScreen> createState() => _SolicitudesCertificacionScreenState();
}

class _SolicitudesCertificacionScreenState extends State<SolicitudesCertificacionScreen> {
  bool _cargando = true;
  bool _verCompletadas = false;
  List<SolicitudCertificacion> _solicitudes = [];
  Socio? _miSocio;

  @override
  void initState() {
    super.initState();
    _cargarSocio();
    _cargar();
  }

  Future<void> _cargarSocio() async {
    try {
      final r = await ApiService.get('/socios/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted && data.isNotEmpty) setState(() => _miSocio = Socio.fromJson(data.first));
      }
    } catch (_) {}
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final estado = _verCompletadas ? 'completada' : 'pendiente';
      final r = await ApiService.get('/solicitudes-certificacion/?estado=$estado');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _solicitudes = data.map((j) => SolicitudCertificacion.fromJson(j)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  /// Mensaje corto de WhatsApp: quién es el contador, para qué sirve el
  /// link y qué tiene que hacer el cliente -- pensado para que a la gente
  /// no le dé pereza abrirlo (nada de leer un párrafo largo primero).
  String _mensajePresentacion(String link) {
    final nombre = _miSocio?.nombre ?? 'tu contador';
    return "Hola, soy $nombre, Contador Público Autorizado.\n\n"
        "Desde ahora podés pedirme una Certificación de Ingresos directo desde este link, sin crear cuenta ni contraseña:\n\n"
        "$link\n\n"
        "Completás tus datos (2 minutos) y, si querés, adjuntás tus estados de cuenta. Yo reviso la solicitud y te la resuelvo enseguida.\n\n"
        "Guardá este link, te sirve cada vez que necesités una certificación.\n\n"
        "— Powered by Equilibra · equilibracr.com";
  }

  Future<void> _compartirPorWhatsApp() async {
    final codigo = _miSocio?.codigoPublico;
    if (codigo == null || codigo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todavía no se generó tu código. Intentá de nuevo en un momento.")));
      return;
    }
    final link = 'https://equilibracr.com/app/?solicitud=$codigo';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_mensajePresentacion(link))}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo abrir WhatsApp.")));
    }
  }

  Future<void> _compartirLink() async {
    final codigo = _miSocio?.codigoPublico;
    if (codigo == null || codigo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todavía no se generó tu código. Intentá de nuevo en un momento.")));
      return;
    }
    final link = 'https://equilibracr.com/app/?solicitud=$codigo';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaContador.fondo,
        title: const Text("Compartí este link con tus clientes", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Quien entre a este link va a poder pedirte una Certificación de Ingresos y adjuntar sus estados de cuenta, sin necesitar cuenta ni login.",
                style: TextStyle(color: TemaContador.textoTenue, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(10), border: Border.all(color: TemaContador.borde)),
                child: Row(
                  children: [
                    Expanded(child: SelectableText(link, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13))),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18, color: TemaContador.acento),
                      tooltip: "Copiar link",
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link copiado"), backgroundColor: Colors.green));
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text("Tu código: $codigo", style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar")),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _compartirPorWhatsApp();
            },
            icon: const Icon(Icons.chat_outlined, size: 16),
            label: const Text("WhatsApp"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link copiado"), backgroundColor: Colors.green));
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text("Copiar link"),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDetalle(SolicitudCertificacion s) async {
    final resultado = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => _DetalleSolicitudScreen(solicitud: s)));
    if (resultado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: const Text("Solicitudes de Certificación", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.ios_share, color: TemaContador.acento), tooltip: "Compartir link con clientes", onPressed: _compartirLink),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text("Pendientes"),
                  selected: !_verCompletadas,
                  onSelected: (_) {
                    setState(() => _verCompletadas = false);
                    _cargar();
                  },
                  selectedColor: TemaContador.acento,
                  labelStyle: TextStyle(color: !_verCompletadas ? Colors.white : TemaContador.textoFuerte, fontWeight: FontWeight.w600),
                  backgroundColor: TemaContador.superficie,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Completadas"),
                  selected: _verCompletadas,
                  onSelected: (_) {
                    setState(() => _verCompletadas = true);
                    _cargar();
                  },
                  selectedColor: TemaContador.acento,
                  labelStyle: TextStyle(color: _verCompletadas ? Colors.white : TemaContador.textoFuerte, fontWeight: FontWeight.w600),
                  backgroundColor: TemaContador.superficie,
                ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _solicitudes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_verCompletadas ? Icons.task_alt : Icons.inbox_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _verCompletadas ? "Todavía no completaste ninguna solicitud." : "No tenés solicitudes pendientes.",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            if (!_verCompletadas) ...[
                              const SizedBox(height: 4),
                              const Text("Compartí tu link con \"Compartir link con clientes\" arriba.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _solicitudes.length,
                          itemBuilder: (context, index) {
                            final s = _solicitudes[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              color: TemaContador.superficie,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: TemaContador.borde)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: s.estado == 'pendiente' ? Colors.orange.withOpacity(0.15) : Colors.green.withOpacity(0.15),
                                  child: Icon(s.estado == 'pendiente' ? Icons.hourglass_top : Icons.check, color: s.estado == 'pendiente' ? Colors.orange : Colors.green, size: 18),
                                ),
                                title: Text(s.nombreSolicitante, style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte)),
                                subtitle: Text(
                                  "${s.proposito.isEmpty ? 'Sin propósito indicado' : s.proposito} · ${s.dirigidoA.isEmpty ? 'Sin destinatario' : s.dirigidoA}\n${s.creadoEn.day}/${s.creadoEn.month}/${s.creadoEn.year}"
                                  "${s.archivosAdjuntos.isNotEmpty ? ' · ${s.archivosAdjuntos.length} archivo(s)' : ''}",
                                  style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12),
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right, color: TemaContador.acento),
                                onTap: () => _abrirDetalle(s),
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

class _DetalleSolicitudScreen extends StatefulWidget {
  final SolicitudCertificacion solicitud;
  const _DetalleSolicitudScreen({required this.solicitud});

  @override
  State<_DetalleSolicitudScreen> createState() => _DetalleSolicitudScreenState();
}

class _DetalleSolicitudScreenState extends State<_DetalleSolicitudScreen> {
  bool _procesando = false;

  Future<void> _abrirArchivo(SolicitudArchivoAdjunto archivo) async {
    final uri = Uri.parse(archivo.archivoUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo abrir el archivo.")));
    }
  }

  Future<void> _completar() async {
    setState(() => _procesando = true);
    try {
      final r = await ApiService.post('/solicitudes-certificacion/${widget.solicitud.id}/completar/', {});
      if (r.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo marcar como completada.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
    if (mounted) setState(() => _procesando = false);
  }

  Future<void> _descartar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Descartar solicitud?"),
        content: const Text("Se va a eliminar y no se podrá recuperar."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Descartar", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _procesando = true);
    try {
      final r = await ApiService.delete('/solicitudes-certificacion/${widget.solicitud.id}/');
      if (r.statusCode == 204 && mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {}
    if (mounted) setState(() => _procesando = false);
  }

  Future<void> _usarDatos() async {
    final s = widget.solicitud;
    final ahora = DateTime.now();
    final finPorDefecto = DateTime(ahora.year, ahora.month - 1, 0);
    final inicioPorDefecto = DateTime(finPorDefecto.year - 1, finPorDefecto.month + 1, 1);
    final prellenada = CertificacionIngreso(
      nombreSolicitante: s.nombreSolicitante,
      cedula: s.cedula,
      tipoCedulaTexto: s.tipoCedulaTexto,
      nacionalidad: s.nacionalidad,
      estadoCivil: s.estadoCivil.isEmpty ? 'soltero' : s.estadoCivil,
      actividadEconomica: s.actividadEconomica,
      numeroActividadEconomica: s.numeroActividadEconomica,
      anosEjerciendo: s.anosEjerciendo,
      proposito: s.proposito,
      dirigidoA: s.dirigidoA,
      fechaInicio: s.fechaInicio ?? inicioPorDefecto,
      fechaFin: s.fechaFin ?? finPorDefecto,
      moneda: s.moneda,
    );
    final guardada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => CertificacionFormScreen(certificacion: prellenada)),
    );
    if (guardada == true && mounted) {
      await _completar();
    }
  }

  Widget _campo(String etiqueta, String valor) {
    if (valor.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 11.5, fontWeight: FontWeight.w600)),
          Text(valor, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.solicitud;
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: Text(s.nombreSolicitante, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline, color: TemaContador.textoTenue), tooltip: "Descartar", onPressed: _procesando ? null : _descartar),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(14), border: Border.all(color: TemaContador.borde)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _campo("Nombre completo", s.nombreSolicitante),
                  _campo("Cédula", "${s.cedula} ${s.tipoCedulaTexto}".trim()),
                  _campo("Nacionalidad", s.nacionalidad),
                  _campo("Estado civil", CertificacionIngreso.estadosCiviles[s.estadoCivil] ?? s.estadoCivil),
                  _campo("Teléfono de contacto", s.telefonoContacto),
                  _campo("Correo de contacto", s.correoContacto),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(14), border: Border.all(color: TemaContador.borde)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _campo("Actividad económica", s.actividadEconomica),
                  _campo("N.° de actividad", s.numeroActividadEconomica),
                  _campo("Años ejerciendo", s.anosEjerciendo?.toString() ?? ''),
                  _campo("Propósito", s.proposito),
                  _campo("Dirigida a", s.dirigidoA),
                  _campo("Periodo", s.fechaInicio != null && s.fechaFin != null ? "${s.fechaInicio!.day}/${s.fechaInicio!.month}/${s.fechaInicio!.year} - ${s.fechaFin!.day}/${s.fechaFin!.month}/${s.fechaFin!.year}" : ''),
                  _campo("Moneda", s.moneda),
                ],
              ),
            ),
            if (s.mensajeCliente.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(14), border: Border.all(color: TemaContador.borde)),
                child: _campo("Comentario del cliente", s.mensajeCliente),
              ),
            if (s.archivosAdjuntos.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(14), border: Border.all(color: TemaContador.borde)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Estados de cuenta adjuntos", style: TextStyle(color: TemaContador.textoTenue, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ...s.archivosAdjuntos.map((a) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.attach_file, size: 18, color: TemaContador.acento),
                          title: Text(a.nombreOriginal, style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 13.5), overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.open_in_new, size: 16, color: TemaContador.textoTenue),
                          onTap: () => _abrirArchivo(a),
                        )),
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: s.estado == 'completada'
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: TemaContador.textoFuerte, side: const BorderSide(color: TemaContador.borde)),
                        onPressed: _procesando ? null : _completar,
                        child: const Text("Marcar como completada"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white),
                        onPressed: _procesando ? null : _usarDatos,
                        icon: const Icon(Icons.badge_outlined, size: 18),
                        label: const Text("Usar estos datos"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
