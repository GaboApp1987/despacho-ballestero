import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'theme/app_theme.dart';

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

  String _hora(int h) => h == 0
      ? "12 a. m."
      : h < 12
      ? "$h a. m."
      : h == 12
      ? "12 m. d."
      : "${h - 12} p. m.";

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
              actions: [IconButton(tooltip: "Actualizar", icon: const Icon(Icons.refresh), onPressed: _cargar)],
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
                          if (c['vinculado'] == true && c['saludo_activo'] == true)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
                              child: Row(
                                children: [
                                  Text("Hora:", style: TextStyle(color: AppColors.textMuted)),
                                  const SizedBox(width: 10),
                                  DropdownButton<int>(
                                    value: (c['saludo_hora'] ?? 7) as int,
                                    items: [for (var h = 5; h <= 12; h++) DropdownMenuItem(value: h, child: Text(_hora(h)))],
                                    onChanged: (h) => _cambiar({'hora': h}, usuarioId: c['usuario_id'] as int),
                                  ),
                                ],
                              ),
                            ),
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
