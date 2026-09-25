import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import 'chat_service.dart';
import 'theme/app_theme.dart';

/// Conversación en vivo entre un negocio y su contador -- misma pantalla
/// para los dos lados, cambia el color según `esContador` (igual patrón
/// que PerfilUsuarioScreen) y qué burbujas se muestran a la derecha.
class ChatDetalleScreen extends StatefulWidget {
  final int conversacionId;
  final String nombreOtraParte;
  final bool esContador;

  const ChatDetalleScreen({super.key, required this.conversacionId, required this.nombreOtraParte, this.esContador = false});

  @override
  State<ChatDetalleScreen> createState() => _ChatDetalleScreenState();
}

class _ChatDetalleScreenState extends State<ChatDetalleScreen> {
  final List<MensajeChat> _mensajes = [];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final ChatService _chat;
  bool _cargando = true;
  bool _subiendoArchivo = false;

  Color get _colorFondo => widget.esContador ? TemaContador.fondo : AppColors.background;
  Color get _colorSuperficie => widget.esContador ? TemaContador.superficie : AppColors.surface;
  Color get _colorBorde => widget.esContador ? TemaContador.borde : AppColors.border;
  Color get _colorFuerte => widget.esContador ? TemaContador.textoFuerte : AppColors.textStrong;
  Color get _colorAcento => widget.esContador ? TemaContador.acento : AppColors.primary;

  @override
  void initState() {
    super.initState();
    _chat = ChatService(widget.conversacionId);
    _cargarHistorial();
    _chat.mensajes.listen((m) {
      if (!mounted) return;
      setState(() => _mensajes.add(m));
      _scrollAlFinal();
    });
    _chat.conectar();
    _marcarLeido();
  }

  @override
  void dispose() {
    _chat.cerrar();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    try {
      final r = await ApiService.get('/chat/conversaciones/${widget.conversacionId}/mensajes/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) {
          setState(() => _mensajes.addAll(data.map((j) => MensajeChat.fromJson(j))));
          _scrollAlFinal();
        }
      }
    } catch (_) {
      // sin historial, el chat sigue funcionando para mensajes nuevos
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _marcarLeido() async {
    try {
      await ApiService.post('/chat/conversaciones/${widget.conversacionId}/marcar-leido/', {});
    } catch (_) {}
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _enviar() {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty) return;
    _chat.enviar(texto);
    _inputCtrl.clear();
  }

  String? _mimeTypePorExtension(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
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

  // El archivo se manda por REST (no por el WebSocket -- JSON no es
  // práctico para binarios) y el propio backend lo reenvía al grupo de
  // Channels de la conversación (ver subir_adjunto en el backend), así que
  // acá no se agrega nada "optimista" a la lista: llega solo por el mismo
  // stream _chat.mensajes que ya escucha initState, igual que un mensaje de
  // texto normal.
  Future<void> _elegirYEnviarArchivo() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx', 'xls', 'xlsx'],
      withData: true,
    );
    final archivos = resultado?.files ?? [];
    if (archivos.isEmpty || archivos.first.bytes == null) return;
    final archivo = archivos.first;

    setState(() => _subiendoArchivo = true);
    try {
      final response = await ApiService.postMultipartBytes(
        '/chat/conversaciones/${widget.conversacionId}/mensajes/adjunto/',
        {},
        'archivo',
        archivo.bytes!,
        archivo.name,
        contentType: _mimeTypePorExtension(archivo.extension),
      );
      if (response.statusCode != 201 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo subir el archivo.")),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo subir el archivo: $e")));
    } finally {
      if (mounted) setState(() => _subiendoArchivo = false);
    }
  }

  Future<void> _abrirArchivo(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir el archivo: $url")));
    }
  }

  Widget _burbujaMensaje(MensajeChat m, bool esMio) {
    final colorTexto = esMio ? Colors.white : _colorFuerte;
    if (!m.tieneArchivo) {
      return Text(m.texto, style: TextStyle(color: colorTexto, fontSize: 14, height: 1.35));
    }
    final adjunto = m.archivoEsImagen
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => _abrirArchivo(m.archivoUrl!),
              child: Image.network(
                m.archivoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 200, height: 140, color: _colorBorde,
                  child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                ),
              ),
            ),
          )
        : InkWell(
            onTap: () => _abrirArchivo(m.archivoUrl!),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (esMio ? Colors.white : _colorAcento).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file_outlined, color: colorTexto, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      m.archivoNombre,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorTexto, fontSize: 13, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
          );
    if (m.texto.isEmpty) return adjunto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        adjunto,
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
          child: Text(m.texto, style: TextStyle(color: colorTexto, fontSize: 14, height: 1.35)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        leading: IconButton(icon: Icon(Icons.arrow_back, color: _colorFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: Text(widget.nombreOtraParte, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _colorFuerte)),
        backgroundColor: _colorSuperficie,
        foregroundColor: _colorFuerte,
        iconTheme: IconThemeData(color: _colorFuerte),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _mensajes.isEmpty
                    ? Center(child: Text("Todavía no hay mensajes -- escribí el primero.", style: TextStyle(color: _colorFuerte.withOpacity(0.5))))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _mensajes.length,
                        itemBuilder: (context, index) {
                          final m = _mensajes[index];
                          final esMio = m.enviadoPorSocio == widget.esContador;
                          return Align(
                            alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: m.tieneArchivo && m.archivoEsImagen
                                  ? const EdgeInsets.all(6)
                                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: esMio ? _colorAcento : _colorSuperficie,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: _burbujaMensaje(m, esMio),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  _subiendoArchivo
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: Icon(Icons.attach_file, color: _colorFuerte.withOpacity(0.7)),
                          tooltip: "Adjuntar foto o documento",
                          onPressed: _elegirYEnviarArchivo,
                        ),
                  Expanded(
                    // En Flutter Web, onSubmitted del TextField no siempre
                    // dispara con el Enter físico del teclado (sí funciona
                    // con teclados IME de celular) -- este Focus intercepta
                    // la tecla directamente para que Enter funcione siempre,
                    // sin depender de eso.
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                          _enviar();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _inputCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _enviar(),
                        style: TextStyle(color: _colorFuerte),
                        decoration: InputDecoration(
                          hintText: "Escribí un mensaje...",
                          filled: true,
                          fillColor: _colorSuperficie,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: _colorBorde)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: _colorBorde)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: _colorAcento, width: 1.5)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _enviar,
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(backgroundColor: _colorAcento, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
