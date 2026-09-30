import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'formato.dart';
import 'theme/app_theme.dart';

/// Bandeja de WhatsApp del superusuario: conversaciones de gente que le
/// escribe al número de Equilibra sin tener cuenta vinculada. Primero
/// contesta la IA (backend: WhatsAppWebhookView._atender_visitante); si no
/// lo resuelve o piden una persona, la conversación queda marcada
/// ("Pide una persona") y llega un correo -- desde acá se contesta como
/// persona. El número de la API de Meta no se puede usar en la app de
/// WhatsApp de un teléfono, por eso esta pantalla.
///
/// Sin WebSocket: se refresca sola cada pocos segundos mientras está
/// abierta (poco tráfico, solo la usa el dueño de la plataforma).

/// "+506 7021 2609" a partir de "50670212609".
String formatearTelefonoWhatsApp(String telefono) {
  if (telefono.startsWith('506') && telefono.length == 11) {
    return "+506 ${telefono.substring(3, 7)} ${telefono.substring(7)}";
  }
  return "+$telefono";
}

String _haceCuanto(String? fechaIso) {
  if (fechaIso == null || fechaIso.isEmpty) return '';
  try {
    final diferencia = DateTime.now().toUtc().difference(DateTime.parse(fechaIso).toUtc());
    if (diferencia.inMinutes < 1) return 'ahora';
    if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
    if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
    final cr = aFechaCostaRica(fechaIso);
    return '${cr.day}/${cr.month}';
  } catch (_) {
    return '';
  }
}

class WhatsAppBandejaScreen extends StatefulWidget {
  const WhatsAppBandejaScreen({super.key});

  @override
  State<WhatsAppBandejaScreen> createState() => _WhatsAppBandejaScreenState();
}

class _WhatsAppBandejaScreenState extends State<WhatsAppBandejaScreen> {
  List<Map<String, dynamic>> _conversaciones = [];
  bool _cargando = true;
  String? _error;
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    _cargar();
    _refresco = Timer.periodic(const Duration(seconds: 15), (_) => _cargar(silencioso: true));
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    try {
      final r = await ApiService.get('/whatsapp/conversaciones/');
      if (!mounted) return;
      if (r.statusCode == 200) {
        final data = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
        setState(() {
          _conversaciones = data;
          _error = null;
        });
      } else if (!silencioso) {
        setState(() => _error = "No se pudo cargar la bandeja (HTTP ${r.statusCode}).");
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() => _error = "No se pudo cargar la bandeja: $e");
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(Map<String, dynamic> c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WhatsAppConversacionScreen(conversacionId: c['id'], telefono: c['telefono'] ?? '')),
    );
    _cargar(silencioso: true);
  }

  Widget _etiqueta(String texto, Color color, IconData icono) {
    return Container(
      margin: const EdgeInsets.only(right: 6, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
          Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Bandeja de WhatsApp"),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: "Actualizar", onPressed: _cargar)],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _conversaciones.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          "Todavía nadie escribió al WhatsApp de Equilibra.\nCuando alguien escriba, la IA le contesta primero y la conversación aparece acá.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _conversaciones.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, i) {
                          final c = _conversaciones[i];
                          final pendiente = c['atendido'] != true;
                          final autor = c['ultimo_autor'];
                          final prefijo = autor == 'ia' ? '🤖 ' : (autor == 'equipo' ? 'Vos: ' : '');
                          return ListTile(
                            onTap: () => _abrir(c),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF25D366).withOpacity(0.15),
                              child: const Icon(Icons.chat, color: Color(0xFF25D366)),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    formatearTelefonoWhatsApp(c['telefono'] ?? ''),
                                    style: TextStyle(fontWeight: pendiente ? FontWeight.w800 : FontWeight.w600, color: AppColors.textStrong),
                                  ),
                                ),
                                Text(_haceCuanto(c['ultimo_mensaje_en']), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                if (pendiente) ...[
                                  const SizedBox(width: 8),
                                  Container(width: 9, height: 9, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                                ],
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  "$prefijo${c['ultimo_mensaje'] ?? ''}",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                                Wrap(
                                  children: [
                                    if (c['escalado'] == true && pendiente) _etiqueta("Pide una persona", Colors.orange, Icons.front_hand_outlined),
                                    if (c['ia_pausada'] == true) _etiqueta("IA pausada", Colors.blueGrey, Icons.pause_circle_outline),
                                    if (c['ventana_abierta'] != true) _etiqueta("Fuera de las 24 h", Colors.grey, Icons.schedule),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class WhatsAppConversacionScreen extends StatefulWidget {
  final int conversacionId;
  final String telefono;

  const WhatsAppConversacionScreen({super.key, required this.conversacionId, required this.telefono});

  @override
  State<WhatsAppConversacionScreen> createState() => _WhatsAppConversacionScreenState();
}

class _WhatsAppConversacionScreenState extends State<WhatsAppConversacionScreen> {
  Map<String, dynamic>? _conv;
  bool _cargando = true;
  bool _enviando = false;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _refresco;

  String get _base => '/whatsapp/conversaciones/${widget.conversacionId}';

  @override
  void initState() {
    super.initState();
    _cargar();
    _refresco = Timer.periodic(const Duration(seconds: 8), (_) => _cargar(silencioso: true));
  }

  @override
  void dispose() {
    _refresco?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _aplicar(Map<String, dynamic> data) {
    final antes = (_conv?['historial'] as List?)?.length ?? 0;
    setState(() => _conv = data);
    if ((data['historial'] as List?)?.length != antes) _scrollAlFinal();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      final r = await ApiService.get('$_base/');
      if (!mounted) return;
      if (r.statusCode == 200) _aplicar(json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {
      // Un refresco fallido no interrumpe nada; el próximo lo reintenta.
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _post(String accion, Map<String, dynamic> body, {String? exito}) async {
    try {
      final r = await ApiService.post('$_base/$accion/', body);
      final data = json.decode(utf8.decode(r.bodyBytes));
      if (!mounted) return;
      if (r.statusCode == 200) {
        _aplicar(data);
        if (exito != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exito)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail']?.toString() ?? "Error (HTTP ${r.statusCode})")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _enviar() async {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    final antes = (_conv?['historial'] as List?)?.length ?? 0;
    await _post('responder', {'texto': texto});
    if (mounted && ((_conv?['historial'] as List?)?.length ?? 0) > antes) _inputCtrl.clear();
    if (mounted) setState(() => _enviando = false);
  }

  Widget _burbuja(Map<String, dynamic> t) {
    final autor = t['autor'] ?? 'cliente';
    final esCliente = autor == 'cliente';
    final esIa = autor == 'ia';
    final color = esCliente ? AppColors.surface : (esIa ? AppColors.primary.withOpacity(0.16) : AppColors.primary);
    final colorTexto = autor == 'equipo' ? Colors.white : AppColors.textStrong;
    final hora = horaCostaRica(t['fecha'] ?? '');
    return Align(
      alignment: esCliente ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: esCliente ? Border.all(color: AppColors.border) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!esCliente)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  esIa ? "🤖 Respondió la IA" : "👤 Equipo",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colorTexto.withOpacity(0.75)),
                ),
              ),
            SelectableText(t['texto'] ?? '', style: TextStyle(color: colorTexto, fontSize: 14.5)),
            if (hora.isNotEmpty)
              Align(
                alignment: Alignment.bottomRight,
                child: Text(hora, style: TextStyle(fontSize: 10.5, color: colorTexto.withOpacity(0.6))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _barraEstado() {
    final c = _conv!;
    final pausada = c['ia_pausada'] == true;
    final ventana = c['ventana_abierta'] == true;
    String textoVentana;
    if (ventana && c['ventana_cierra_en'] != null) {
      textoVentana = "Podés responder hasta las ${horaCostaRica(c['ventana_cierra_en'])} (24 h desde su último mensaje).";
    } else {
      textoVentana = "Pasaron más de 24 h desde su último mensaje: Meta no deja escribirle hasta que él vuelva a escribir.";
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(pausada ? Icons.pause_circle_outline : Icons.smart_toy_outlined, size: 18, color: pausada ? Colors.blueGrey : AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pausada ? "IA pausada: estás atendiendo vos" : "La IA está contestando esta conversación",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong, fontSize: 13.5),
                ),
              ),
              TextButton(
                onPressed: () => _post(
                  'pausar_ia',
                  {'pausada': !pausada},
                  exito: pausada ? "La IA vuelve a contestar esta conversación" : "IA pausada: ahora contestás vos",
                ),
                child: Text(pausada ? "Devolver a la IA" : "Tomar conversación"),
              ),
            ],
          ),
          Text(textoVentana, style: TextStyle(fontSize: 12, color: ventana ? AppColors.textMuted : Colors.orange)),
          if (c['escalado'] == true && c['atendido'] != true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("✋ La IA indicó que esta persona necesita hablar con alguien del equipo.", style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historial = ((_conv?['historial'] as List?) ?? []).cast<Map<String, dynamic>>();
    final ventana = _conv?['ventana_abierta'] == true;
    final atendido = _conv?['atendido'] == true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(formatearTelefonoWhatsApp(widget.telefono)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: "Copiar número",
            onPressed: () {
              Clipboard.setData(ClipboardData(text: "+${widget.telefono}"));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Número copiado")));
            },
          ),
          if (_conv != null)
            TextButton.icon(
              onPressed: () => _post('marcar_atendido', {'atendido': !atendido}, exito: atendido ? "Marcada como pendiente" : "Marcada como atendida"),
              icon: Icon(atendido ? Icons.mark_chat_unread_outlined : Icons.done_all),
              label: Text(atendido ? "Pendiente" : "Atendida"),
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _conv == null
              ? const Center(child: Text("No se pudo cargar la conversación."))
              : Column(
                  children: [
                    _barraEstado(),
                    Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: historial.length,
                        itemBuilder: (_, i) => _burbuja(historial[i]),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Focus(
                                // Enter envía también en Flutter Web (ver chat_detalle_screen.dart).
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                                    _enviar();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: TextField(
                                  controller: _inputCtrl,
                                  enabled: ventana && !_enviando,
                                  minLines: 1,
                                  maxLines: 4,
                                  style: TextStyle(color: AppColors.textStrong),
                                  decoration: InputDecoration(
                                    hintText: ventana ? "Escribí tu respuesta (le llega por WhatsApp)..." : "Esperá a que el cliente vuelva a escribir",
                                    filled: true,
                                    fillColor: AppColors.surface,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: AppColors.border)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: AppColors.border)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _enviando
                                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                                : IconButton.filled(
                                    onPressed: ventana ? _enviar : null,
                                    icon: const Icon(Icons.send),
                                    style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
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
