import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Quién recibe los mensajes automáticos de WhatsApp (por ahora, el saludo
/// de la mañana; backend: WhatsAppAutomaticosView). Cada perfil ve su
/// cuenta y las de su cartera (un contador, sus clientes); el
/// administrador además ve todas y el interruptor general. Todo viene
/// apagado: se enciende a propósito por cuenta.
class MensajesAutomaticosScreen extends StatefulWidget {
  /// Dentro de una sección del panel del negocio (sin su propia barra).
  final bool embebido;
  const MensajesAutomaticosScreen({super.key, this.embebido = false});

  @override
  State<MensajesAutomaticosScreen> createState() => _MensajesAutomaticosScreenState();
}

class _MensajesAutomaticosScreenState extends State<MensajesAutomaticosScreen> {
  Map<String, dynamic>? _datos;
  String? _error;
  final Set<int> _guardando = {};
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/whatsapp/automaticos/');
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() {
          _datos = json.decode(utf8.decode(r.bodyBytes));
          _error = null;
        });
      } else {
        setState(() => _error = ApiService.mensajeError(r));
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _cambiar(Map<String, dynamic> cambios, {int? usuarioId}) async {
    if (usuarioId != null) setState(() => _guardando.add(usuarioId));
    try {
      final r = await ApiService.put('/whatsapp/automaticos/', {if (usuarioId != null) 'usuario_id': usuarioId, ...cambios});
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => _datos = d);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d['detail']?.toString() ?? ApiService.mensajeError(r))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    } finally {
      if (mounted && usuarioId != null) setState(() => _guardando.remove(usuarioId));
    }
  }

  String _hora(int h, [int m = 0]) {
    final mm = m.toString().padLeft(2, '0');
    if (h == 0) return "12:$mm a. m.";
    if (h < 12) return "$h:$mm a. m.";
    if (h == 12) return "12:$mm m. d.";
    return "${h - 12}:$mm p. m.";
  }

  static const _letrasDias = ['L', 'K', 'M', 'J', 'V', 'S', 'D'];
  static const _nombresDias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  String _recurrencia(String dias) {
    if (dias == '0123456') return 'todos';
    if (dias == '01234') return 'semana';
    if (dias.length == 1) return 'semanal';
    return 'dias';
  }

  String _resumen(Map<String, dynamic> c) {
    final dias = (c['saludo_dias'] ?? '0123456').toString();
    final cuando = switch (_recurrencia(dias)) {
      'todos' => "todos los días",
      'semana' => "de lunes a viernes",
      'semanal' => "cada ${_nombresDias[int.parse(dias)]}",
      _ => "los ${dias.split('').map((x) => _nombresDias[int.parse(x)]).join(', ')}",
    };
    return "Sale $cuando a las ${_hora((c['saludo_hora'] ?? 7) as int, (c['saludo_minuto'] ?? 0) as int)}.";
  }

  Future<void> _enviarAhora(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("¿Mandarle el saludo ahora a ${c['nombre']}?"),
        content: const Text("Sale en este momento por WhatsApp (además del programado)."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Mandar")),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await ApiService.post('/whatsapp/automaticos/', {'usuario_id': c['usuario_id']});
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d['detail']?.toString() ?? '')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  Future<void> _editarTexto(Map<String, dynamic> c, String porDefecto) async {
    final ctrl = TextEditingController(text: (c['saludo_texto'] ?? '').toString());
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Mensaje para ${c['nombre']}"),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: ctrl,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: porDefecto,
              helperText: "Va después del saludo (¡Buenos días, nombre!). Vacío = el mensaje de siempre.",
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Guardar")),
        ],
      ),
    );
    ctrl.dispose();
    if (texto != null) await _cambiar({'texto': texto}, usuarioId: c['usuario_id'] as int);
  }

  Widget _ajustesCuenta(Map<String, dynamic> c, String porDefecto) {
    final id = c['usuario_id'] as int;
    final dias = (c['saludo_dias'] ?? '0123456').toString();
    final recurrencia = _recurrencia(dias);
    final texto = (c['saludo_texto'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("Hora:", style: TextStyle(color: AppColors.textMuted)),
              DropdownButton<int>(
                value: (c['saludo_hora'] ?? 7) as int,
                items: [for (var h = 5; h <= 21; h++) DropdownMenuItem(value: h, child: Text(_hora(h).replaceAll(':00', '')))],
                onChanged: (h) => _cambiar({'hora': h}, usuarioId: id),
              ),
              DropdownButton<int>(
                value: (c['saludo_minuto'] ?? 0) as int,
                items: [for (final m in [0, 15, 30, 45]) DropdownMenuItem(value: m, child: Text(":${m.toString().padLeft(2, '0')}"))],
                onChanged: (m) => _cambiar({'minuto': m}, usuarioId: id),
              ),
              DropdownButton<String>(
                value: recurrencia,
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text("Todos los días")),
                  DropdownMenuItem(value: 'semana', child: Text("Lunes a viernes")),
                  DropdownMenuItem(value: 'semanal', child: Text("Una vez por semana")),
                  DropdownMenuItem(value: 'dias', child: Text("Días específicos")),
                ],
                onChanged: (v) {
                  final nuevos = switch (v) {
                    'todos' => '0123456',
                    'semana' => '01234',
                    'semanal' => '0',
                    _ => dias.length == 7 ? '024' : dias,
                  };
                  _cambiar({'dias': nuevos}, usuarioId: id);
                },
              ),
            ],
          ),
          if (recurrencia == 'dias' || recurrencia == 'semanal')
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(_letrasDias[i]),
                    tooltip: _nombresDias[i],
                    selected: dias.contains('$i'),
                    onSelected: (v) {
                      String nuevos;
                      if (recurrencia == 'semanal') {
                        nuevos = '$i';
                      } else {
                        final set = dias.split('').toSet();
                        v ? set.add('$i') : set.remove('$i');
                        if (set.isEmpty) return;
                        nuevos = (set.toList()..sort()).join();
                      }
                      _cambiar({'dias': nuevos}, usuarioId: id);
                    },
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Text(_resumen(c), style: TextStyle(fontSize: 12.5, color: Colors.green.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            texto.isEmpty ? "Mensaje: el de siempre — \"$porDefecto\"" : "Mensaje: \"$texto\"",
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _editarTexto(c, porDefecto),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text("Cambiar mensaje"),
              ),
              TextButton.icon(onPressed: () => _enviarAhora(c), icon: const Icon(Icons.send, size: 16), label: const Text("Enviar ahora")),
            ],
          ),
        ],
      ),
    );
  }

  static const _tipos = {'negocio': 'Negocio', 'contador': 'Contador', 'despacho': 'Despacho', 'cuenta': 'Cuenta'};

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    final cuentas = ((d?['cuentas'] as List?) ?? []).cast<Map<String, dynamic>>();
    final q = _busqueda.trim().toLowerCase();
    final visibles = q.isEmpty ? cuentas : cuentas.where((c) => (c['nombre'] ?? '').toString().toLowerCase().contains(q)).toList();
    final encendidas = cuentas.where((c) => c['saludo_activo'] == true && c['vinculado'] == true).length;
    final esAdmin = d?['es_admin'] == true;
    final globalActivo = d?['global_activo'] == true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.embebido
          ? null
          : AppBar(
              title: const Text("Mensajes automáticos de WhatsApp"),
              actions: [const BotonCalculadora(), IconButton(tooltip: "Actualizar", icon: const Icon(Icons.refresh), onPressed: _cargar)],
            ),
      body: d == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, textAlign: TextAlign.center))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  "Saludo de la mañana: el asistente le escribe a la persona, le dice lo pendiente del día (cobros vencidos, "
                  "compras por aceptar, IVA) y le pregunta qué ocupa hacer hoy. Viene apagado: encendelo solo a quien lo quiera. "
                  "Cada mensaje cuesta ₡${(d['precio_mensaje'] as num).toStringAsFixed(0)} y se cobra a fin de mes.",
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (esAdmin)
                  Card(
                    color: AppColors.surface,
                    child: SwitchListTile(
                      value: globalActivo,
                      onChanged: (v) => _cambiar({'global_activo': v}),
                      title: const Text("Interruptor general", style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        globalActivo
                            ? "Encendido: sale a las cuentas que lo tienen activado ($encendidas)."
                            : "Apagado: no sale ningún saludo, aunque una cuenta lo tenga activado.",
                      ),
                    ),
                  )
                else if (!globalActivo)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                    child: const Text(
                      "Los saludos todavía no están habilitados en Equilibra: podés dejarlos listos y empiezan a salir cuando se habiliten.",
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                if (cuentas.length > 6) ...[
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: "Buscar cuenta", isDense: true, border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => _busqueda = v),
                  ),
                ],
                const SizedBox(height: 8),
                for (final c in visibles)
                  Card(
                    color: AppColors.surface,
                    margin: const EdgeInsets.only(top: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: c['saludo_activo'] == true,
                            onChanged: c['vinculado'] != true || _guardando.contains(c['usuario_id'])
                                ? null
                                : (v) => _cambiar({'activo': v}, usuarioId: c['usuario_id'] as int),
                            title: Text(
                              "${c['nombre']}${c['es_mia'] == true ? ' (yo)' : ''}",
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong),
                            ),
                            subtitle: Text(
                              c['vinculado'] == true
                                  ? "${_tipos[c['tipo']] ?? ''} · WhatsApp ${c['telefono']}"
                                  : "${_tipos[c['tipo']] ?? ''} · Sin WhatsApp vinculado (no recibe mensajes)",
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                          if (c['vinculado'] == true && c['saludo_activo'] == true) _ajustesCuenta(c, d['texto_por_defecto']?.toString() ?? ''),
                        ],
                      ),
                    ),
                  ),
                if (visibles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "No hay cuentas para mostrar.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
    );
  }
}
