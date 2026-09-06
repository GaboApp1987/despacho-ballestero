import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../api_service.dart';

/// Abre el chat de soporte con IA en una hoja modal -- se puede llamar desde
/// cualquier pantalla (login, o ya adentro de la app). `contexto` cambia el
/// tono del asistente ('visitante' antes de iniciar sesión, 'usuario' ya
/// logueado, ver _SOPORTE_SYSTEM_PROMPT_* en el backend). `negocioId` es
/// opcional y solo se manda si hay uno logueado, para que un mensaje que
/// deje el usuario quede asociado a su negocio.
Future<void> mostrarSoporteChat(BuildContext context, {required String contexto, int? negocioId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SoporteChatSheet(contexto: contexto, negocioId: negocioId),
  );
}

class _ChatMensaje {
  final String role; // 'user' | 'assistant'
  final String content;
  const _ChatMensaje(this.role, this.content);

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class _SoporteChatSheet extends StatefulWidget {
  final String contexto;
  final int? negocioId;
  const _SoporteChatSheet({required this.contexto, this.negocioId});

  @override
  State<_SoporteChatSheet> createState() => _SoporteChatSheetState();
}

class _SoporteChatSheetState extends State<_SoporteChatSheet> {
  final List<_ChatMensaje> _mensajes = [
    const _ChatMensaje('assistant', '¡Hola! Soy el asistente de soporte de Equilibra. ¿En qué te ayudo?'),
  ];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _enviando = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _enviarMensaje() async {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() {
      _mensajes.add(_ChatMensaje('user', texto));
      _inputCtrl.clear();
      _enviando = true;
    });
    _scrollAlFinal();

    try {
      final response = await ApiService.post('/soporte/chat/', {
        'mensajes': _mensajes.map((m) => m.toJson()).toList(),
        'contexto': widget.contexto,
      });
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? 'Error desconocido');
      }
      setState(() => _mensajes.add(_ChatMensaje('assistant', data['respuesta'] ?? '')));
    } catch (e) {
      setState(() => _mensajes.add(_ChatMensaje(
            'assistant',
            'No pude responder ahora mismo ($e). Podés dejar tu mensaje con el botón de abajo y te contactamos.',
          )));
    } finally {
      if (mounted) setState(() => _enviando = false);
      _scrollAlFinal();
    }
  }

  Future<void> _abrirDejarMensaje() async {
    final nombreCtrl = TextEditingController();
    final correoCtrl = TextEditingController();
    final mensajeCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dejar mensaje para el equipo'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo *'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Ingresá un correo válido' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: mensajeCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Mensaje *', alignLabelWithHint: true),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Contanos qué necesitás' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (enviar != true) return;

    final transcripcion = _mensajes.map((m) => "${m.role == 'user' ? 'Yo' : 'IA'}: ${m.content}").join('\n');
    try {
      final response = await ApiService.post('/soporte/contacto/', {
        'nombre': nombreCtrl.text.trim(),
        'correo': correoCtrl.text.trim(),
        'mensaje': mensajeCtrl.text.trim(),
        'origen': widget.contexto == 'usuario' ? 'app' : 'login',
        'transcripcion': transcripcion,
        if (widget.negocioId != null) 'negocio': widget.negocioId,
      });
      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Listo! En breve te contactamos.'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception('Error ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo enviar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.82;
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Container(
        height: alto,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.support_agent, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Soporte Equilibra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _mensajes.length,
                itemBuilder: (context, index) {
                  final m = _mensajes[index];
                  final esUsuario = m.role == 'user';
                  return Align(
                    alignment: esUsuario ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: esUsuario ? AppColors.primary : AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        m.content,
                        style: TextStyle(color: esUsuario ? Colors.black : AppColors.textStrong, fontSize: 14, height: 1.35),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_enviando)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _abrirDejarMensaje,
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Dejar mensaje para el equipo', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _enviarMensaje(),
                      decoration: InputDecoration(
                        hintText: 'Escribí tu pregunta...',
                        filled: true,
                        fillColor: AppColors.surfaceSubtle,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _enviando ? null : _enviarMensaje,
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
