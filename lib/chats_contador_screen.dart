import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'chat_detalle_screen.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';

class _ConversacionResumen {
  final int id;
  final int negocioId;
  final String negocioNombre;
  final String ultimoMensaje;
  final int noLeidos;

  _ConversacionResumen({
    required this.id,
    required this.negocioId,
    required this.negocioNombre,
    required this.ultimoMensaje,
    required this.noLeidos,
  });

  factory _ConversacionResumen.fromJson(Map<String, dynamic> j) => _ConversacionResumen(
        id: j['id'],
        negocioId: j['negocio_id'],
        negocioNombre: j['negocio_nombre'] ?? '',
        ultimoMensaje: j['ultimo_mensaje'] ?? '',
        noLeidos: j['no_leidos'] ?? 0,
      );
}

/// Bandeja del contador con sus chats -- uno por negocio de su cartera con
/// el que ya empezó una conversación, más el botón para iniciar uno nuevo
/// eligiendo cualquier negocio propio (ver ConversacionChatViewSet.create
/// en el backend, que valida que el negocio elegido sea de su cartera).
class ChatsContadorScreen extends StatefulWidget {
  const ChatsContadorScreen({super.key});

  @override
  State<ChatsContadorScreen> createState() => _ChatsContadorScreenState();
}

class _ChatsContadorScreenState extends State<ChatsContadorScreen> {
  bool _cargando = true;
  List<_ConversacionResumen> _conversaciones = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await ApiService.get('/chat/conversaciones/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _conversaciones = data.map((j) => _ConversacionResumen.fromJson(j)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _abrirConversacion(_ConversacionResumen c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatDetalleScreen(conversacionId: c.id, nombreOtraParte: c.negocioNombre, esContador: true)),
    );
    _cargar();
  }

  Future<void> _nuevoChat() async {
    List<Negocio> negocios = [];
    try {
      final r = await ApiService.get('/negocios/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        negocios = data.map((j) => Negocio.fromJson(j)).toList();
      }
    } catch (_) {}
    final idsConChat = _conversaciones.map((c) => c.negocioId).toSet();
    final disponibles = negocios.where((n) => !idsConChat.contains(n.id)).toList()
      ..sort((a, b) => a.nombreComercial.toLowerCase().compareTo(b.nombreComercial.toLowerCase()));

    if (!mounted) return;
    if (disponibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ya tenés un chat con todos tus negocios, o todavía no tenés ninguno en tu cartera.")),
      );
      return;
    }

    final elegido = await showModalBottomSheet<Negocio>(
      context: context,
      backgroundColor: TemaContador.fondo,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: disponibles.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text("Elegí un negocio para iniciar el chat", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: TemaContador.textoFuerte)),
              );
            }
            final n = disponibles[index - 1];
            return ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0x1A1D4ED8), child: Icon(Icons.storefront_outlined, color: TemaContador.acento)),
              title: Text(n.nombreComercial, style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, n),
            );
          },
        ),
      ),
    );
    if (elegido == null) return;

    try {
      final r = await ApiService.post('/chat/conversaciones/', {'negocio_id': elegido.id});
      if (r.statusCode == 201 && mounted) {
        final conv = _ConversacionResumen.fromJson(json.decode(utf8.decode(r.bodyBytes)));
        await _cargar();
        if (mounted) _abrirConversacion(conv);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo crear el chat: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: const Text("Chats", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoChat,
        backgroundColor: TemaContador.acento,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text("Nuevo chat"),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _conversaciones.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("Todavía no iniciaste ningún chat.", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      const Text("Usá \"Nuevo chat\" para escribirle a un cliente.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _conversaciones.length,
                    itemBuilder: (context, index) {
                      final c = _conversaciones[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: TemaContador.superficie,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: TemaContador.borde)),
                        child: ListTile(
                          leading: Badge(
                            label: Text(c.noLeidos > 99 ? '99+' : '${c.noLeidos}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.red,
                            isLabelVisible: c.noLeidos > 0,
                            offset: const Offset(4, -4),
                            child: const CircleAvatar(backgroundColor: Color(0x1A1D4ED8), child: Icon(Icons.storefront_outlined, color: TemaContador.acento)),
                          ),
                          title: Text(c.negocioNombre, style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte)),
                          subtitle: Text(
                            c.ultimoMensaje.isEmpty ? "Sin mensajes todavía" : c.ultimoMensaje,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: TemaContador.acento),
                          onTap: () => _abrirConversacion(c),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
