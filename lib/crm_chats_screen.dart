import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'formato.dart';
import 'theme/app_theme.dart';

/// Conversaciones del chat con IA para el CRM (backend: crm.py, chats):
/// "Visitantes" son las del landing y del login (con o sin contacto) y
/// "Soporte de clientes" las de quienes ya usan Equilibra, desde la app.
class ChatsCrmScreen extends StatelessWidget {
  const ChatsCrmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("Chats con la IA"),
          bottom: const TabBar(tabs: [Tab(text: "Visitantes"), Tab(text: "Soporte de clientes")]),
        ),
        body: const TabBarView(children: [_ListaChats(tipo: 'visitantes'), _ListaChats(tipo: 'clientes')]),
      ),
    );
  }
}

class _ListaChats extends StatefulWidget {
  final String tipo;
  const _ListaChats({required this.tipo});

  @override
  State<_ListaChats> createState() => _ListaChatsState();
}

class _ListaChatsState extends State<_ListaChats> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _chats = [];
  bool _cargando = true;
  String _busqueda = '';
  Timer? _espera;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final q = Uri.encodeQueryComponent(_busqueda.trim());
      final r = await ApiService.get('/crm/prospectos/chats/?tipo=${widget.tipo}${q.isEmpty ? '' : '&q=$q'}');
      if (r.statusCode == 200 && mounted) {
        setState(() => _chats = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // Se reintenta al deslizar para actualizar.
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _cuando(String? iso) {
    if (iso == null) return '';
    final f = aFechaCostaRica(iso);
    return '${f.day}/${f.month} ${horaCostaRica(iso)}';
  }

  Future<void> _abrir(Map<String, dynamic> c) async {
    final r = await ApiService.get('/crm/prospectos/chats/${c['id']}/');
    if (r.statusCode != 200 || !mounted) return;
    final d = json.decode(utf8.decode(r.bodyBytes));
    final historial = ((d['historial'] as List?) ?? []).cast<Map<String, dynamic>>();
    final contacto = [d['contacto_nombre'], d['contacto_telefono'], d['contacto_correo']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c['nombre'] ?? 'Chat'),
        content: SizedBox(
          width: 520,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${d['contexto_texto']}${contacto.isEmpty ? ' · sin contacto' : ' · $contacto'}",
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final t in historial)
                      Align(
                        alignment: t['role'] == 'user' ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: t['role'] == 'user' ? AppColors.surface : AppColors.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                            border: t['role'] == 'user' ? Border.all(color: AppColors.border) : null,
                          ),
                          child: SelectableText(t['content'] ?? '', style: TextStyle(fontSize: 13.5, color: AppColors.textStrong)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final esVisitantes = widget.tipo == 'visitantes';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: "Buscar en las conversaciones", isDense: true, border: OutlineInputBorder()),
            onChanged: (v) {
              _busqueda = v;
              _espera?.cancel();
              _espera = Timer(const Duration(milliseconds: 400), _cargar);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            esVisitantes
                ? "Lo que preguntan en el chat del landing y del login. Los que dejaron su WhatsApp o correo ya están en el CRM."
                : "Lo que preguntan por soporte quienes ya usan Equilibra, desde la app.",
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _chats.isEmpty
                  ? Center(child: Text("Todavía no hay conversaciones.", style: TextStyle(color: AppColors.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _chats.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          final c = _chats[i];
                          return ListTile(
                            onTap: () => _abrir(c),
                            leading: CircleAvatar(
                              backgroundColor: (c['en_crm'] == true ? Colors.green : AppColors.primary).withValues(alpha: 0.15),
                              child: Icon(c['en_crm'] == true ? Icons.person_pin : Icons.chat_bubble_outline,
                                  color: c['en_crm'] == true ? Colors.green : AppColors.primary),
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(c['nombre'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong))),
                                Text(_cuando(c['ultimo_mensaje_en']), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              ],
                            ),
                            subtitle: Text(
                              "${c['contexto_texto']} · ${c['mensajes']} mensaje${c['mensajes'] == 1 ? '' : 's'}"
                              "${(c['contacto'] ?? '').toString().isNotEmpty ? ' · ${c['contacto']}' : ''}\n${c['primer_mensaje'] ?? ''}",
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
