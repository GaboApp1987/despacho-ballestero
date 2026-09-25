import 'dart:convert';
import 'package:flutter/material.dart';
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
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: esMio ? _colorAcento : _colorSuperficie,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(m.texto, style: TextStyle(color: esMio ? Colors.white : _colorFuerte, fontSize: 14, height: 1.35)),
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
                  Expanded(
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
