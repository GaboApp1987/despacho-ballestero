import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../api_service.dart';
import '../formato.dart';

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
  final _PropuestaFactura? propuesta;
  // 'pendiente' | 'creada' | 'error' -- solo aplica cuando hay `propuesta`.
  String estadoPropuesta = 'pendiente';
  _ChatMensaje(this.role, this.content, {this.propuesta});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Borrador de factura que arma el chat (herramienta preparar_factura del
/// backend) a partir de productos/cliente reales del catálogo -- nunca se
/// crea sola, el usuario la confirma con un botón (ver _confirmarFactura).
class _PropuestaFactura {
  final int clienteId;
  final String clienteNombre;
  final String clienteCedula;
  final List<Map<String, dynamic>> items;
  _PropuestaFactura({
    required this.clienteId,
    required this.clienteNombre,
    required this.clienteCedula,
    required this.items,
  });

  factory _PropuestaFactura.fromJson(Map<String, dynamic> json) {
    return _PropuestaFactura(
      clienteId: json['cliente_id'],
      clienteNombre: json['cliente_nombre'] ?? '',
      clienteCedula: json['cliente_cedula'] ?? '',
      items: (json['items'] as List).cast<Map<String, dynamic>>(),
    );
  }

  double get subtotal => items.fold(0.0, (s, it) => s + (it['precio_unitario'] as num) * (it['cantidad'] as num));
  double get montoIva => items.fold(
      0.0, (s, it) => s + (it['precio_unitario'] as num) * (it['cantidad'] as num) * ((it['impuesto_porcentaje'] as num? ?? 0) / 100));
  double get total => subtotal + montoIva;
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
    _ChatMensaje('assistant', '¡Hola! Soy el asistente de soporte de Equilibra. ¿En qué te ayudo?'),
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
        if (widget.negocioId != null) 'negocio': widget.negocioId,
      });
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? 'Error desconocido');
      }
      final propuestaJson = data['propuesta_factura'];
      setState(() => _mensajes.add(_ChatMensaje(
            'assistant',
            data['respuesta'] ?? '',
            propuesta: propuestaJson != null ? _PropuestaFactura.fromJson(propuestaJson) : null,
          )));
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

  /// Crea de verdad la factura que el chat propuso, solo cuando el usuario
  /// toca "Confirmar" en la tarjeta de la propuesta -- de contado siempre
  /// (ver _SOPORTE_SYSTEM_PROMPT_USUARIO en el backend), reusando el mismo
  /// endpoint que el formulario normal de factura.
  Future<void> _confirmarFactura(_ChatMensaje mensaje) async {
    final propuesta = mensaje.propuesta!;
    setState(() => mensaje.estadoPropuesta = 'creando');
    try {
      final body = {
        'negocio': widget.negocioId,
        'cliente': propuesta.clienteId,
        'consecutivo': '',
        'receptor_nombre': propuesta.clienteNombre,
        'receptor_cedula': propuesta.clienteCedula,
        'total_iva': redondear2(propuesta.montoIva),
        'total_factura': redondear2(propuesta.total),
        'condicion_venta': '01',
        'plazo_credito': 0,
        'detalles': propuesta.items.map((it) {
          final subtotalItem = (it['precio_unitario'] as num) * (it['cantidad'] as num);
          final ivaItem = subtotalItem * ((it['impuesto_porcentaje'] as num? ?? 0) / 100);
          return {
            'producto': it['producto_id'],
            'cantidad': it['cantidad'],
            'precio_unitario': redondear2(it['precio_unitario'] as num),
            'monto_iva': redondear2(ivaItem),
            'subtotal': redondear2(subtotalItem),
          };
        }).toList(),
      };
      final response = await ApiService.post('/facturas/', body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        setState(() => mensaje.estadoPropuesta = 'creada');
        _mensajes.add(_ChatMensaje('assistant', '¡Listo! Factura creada y enviada a Hacienda.'));
        setState(() {});
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      setState(() => mensaje.estadoPropuesta = 'pendiente');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la factura: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
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

  Widget _buildTarjetaPropuesta(_ChatMensaje mensaje) {
    final propuesta = mensaje.propuesta!;
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text('Borrador de factura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Cliente: ${propuesta.clienteNombre}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          ...propuesta.items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${it['cantidad']} x ${it['nombre_producto']} (${formatearColones((it['precio_unitario'] as num).toDouble())})',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total (contado)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(formatearColones(propuesta.total), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          if (mensaje.estadoPropuesta == 'creada')
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text('Factura creada', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: mensaje.estadoPropuesta == 'creando' ? null : () => _confirmarFactura(mensaje),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                child: mensaje.estadoPropuesta == 'creando'
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Confirmar y crear factura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
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
                  return Column(
                    crossAxisAlignment: esUsuario ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Align(
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
                      ),
                      if (m.propuesta != null) _buildTarjetaPropuesta(m),
                    ],
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
