import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'theme/app_theme.dart';

/// Buscar negocios en Google Maps y meterlos al CRM como prospectos
/// (backend: crm_maps.py). Vienen marcados los que tienen celular y todavía
/// no están en el CRM; al agregarlos se les puede escribir por WhatsApp.
class BuscarMapsScreen extends StatefulWidget {
  const BuscarMapsScreen({super.key});

  @override
  State<BuscarMapsScreen> createState() => _BuscarMapsScreenState();
}

class _BuscarMapsScreenState extends State<BuscarMapsScreen> {
  final _textoCtrl = TextEditingController();
  final List<Map<String, dynamic>> _lugares = [];
  final Set<String> _elegidos = {};
  String? _siguiente;
  String _busqueda = '';
  bool _buscando = false;
  bool _agregando = false;

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar({bool mas = false}) async {
    final texto = mas ? _busqueda : _textoCtrl.text.trim();
    if (texto.isEmpty) return;
    setState(() {
      _buscando = true;
      if (!mas) {
        _lugares.clear();
        _elegidos.clear();
        _siguiente = null;
        _busqueda = texto;
      }
    });
    try {
      final r = await ApiService.post('/crm/prospectos/buscar_maps/', {'texto': texto, if (mas) 'pagina': _siguiente});
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200) throw Exception(d['detail'] ?? ApiService.mensajeError(r));
      final nuevos = (d['lugares'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _lugares.addAll(nuevos);
        _elegidos.addAll(nuevos.where((l) => l['celular'] == true && l['ya_en_crm'] != true).map((l) => l['place_id'] as String));
        _siguiente = d['siguiente'];
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _agregar() async {
    setState(() => _agregando = true);
    try {
      final elegidos = _lugares.where((l) => _elegidos.contains(l['place_id'])).toList();
      final r = await ApiService.post('/crm/prospectos/importar_maps/', {'lugares': elegidos, 'busqueda': _busqueda});
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      if (!mounted) return;
      final ids = ((d['ids_celular'] as List?) ?? []).cast<int>();
      final escribir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("${d['creados']} agregados al CRM"),
          content: Text(
            [
              if ((d['repetidos'] ?? 0) > 0) "${d['repetidos']} ya estaban.",
              if (ids.isNotEmpty) "¿Les querés escribir por WhatsApp ahora a los ${ids.length} con celular?",
            ].join(' '),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ids.isEmpty ? "Listo" : "Después")),
            if (ids.isNotEmpty) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Escribirles")),
          ],
        ),
      );
      if (escribir == true && mounted) await enviarWhatsAppProspectos(context, ids);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    } finally {
      if (mounted) setState(() => _agregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Buscar en Google Maps")),
      bottomNavigationBar: _elegidos.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _agregando ? null : _agregar,
                  icon: _agregando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.person_add_alt_1),
                  label: Text("Agregar ${_elegidos.length} al CRM"),
                ),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _textoCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
              decoration: InputDecoration(
                hintText: "Ej.: ferreterías en Cartago, sodas en Heredia, contadores en San José",
                prefixIcon: const Icon(Icons.travel_explore),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _buscando ? null : () => _buscar()),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Vienen marcados los que tienen celular (WhatsApp) y no están en el CRM. Los teléfonos fijos casi nunca tienen WhatsApp.",
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: _lugares.isEmpty && _buscando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      for (final l in _lugares)
                        CheckboxListTile(
                          value: _elegidos.contains(l['place_id']),
                          onChanged: l['ya_en_crm'] == true
                              ? null
                              : (v) => setState(() => v == true ? _elegidos.add(l['place_id']) : _elegidos.remove(l['place_id'])),
                          title: Text(
                            l['nombre'] ?? '',
                            style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [l['categoria'], l['direccion']].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                              Row(
                                children: [
                                  Icon(l['celular'] == true ? Icons.phone_android : Icons.phone, size: 14, color: AppColors.textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    (l['telefono'] ?? '').toString().isEmpty ? "Sin teléfono" : l['telefono'],
                                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                  ),
                                  if (l['ya_en_crm'] == true) ...[
                                    const SizedBox(width: 8),
                                    const Text("Ya está en el CRM", style: TextStyle(fontSize: 12, color: Colors.orange)),
                                  ],
                                  const Spacer(),
                                  if ((l['maps_url'] ?? '').toString().isNotEmpty)
                                    IconButton(
                                      tooltip: "Ver en Google Maps",
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.map_outlined, size: 18),
                                      onPressed: () => launchUrl(Uri.parse(l['maps_url']), mode: LaunchMode.externalApplication),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (_siguiente != null)
                        Center(
                          child: TextButton(onPressed: _buscando ? null : () => _buscar(mas: true), child: Text(_buscando ? "Buscando..." : "Cargar más")),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Escribirle por WhatsApp a uno o varios prospectos (backend:
/// crm/prospectos/enviar_whatsapp/). Devuelve true si salió alguno.
Future<bool> enviarWhatsAppProspectos(BuildContext context, List<int> ids, {String? nombre}) async {
  final ctrl = TextEditingController();
  final mensaje = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(nombre != null ? "WhatsApp a $nombre" : "WhatsApp a ${ids.length} prospecto${ids.length == 1 ? '' : 's'}"),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              minLines: 4,
              maxLines: 8,
              maxLength: 900,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Mensaje",
                hintText: "Ej.: Ayudamos a negocios como el suyo a facturar electrónicamente desde WhatsApp. ¿Le muestro cómo?",
                border: OutlineInputBorder(),
              ),
            ),
            Text(
              "Si no te han escrito en las últimas 24 h, sale con la plantilla aprobada (\"¡Hola {nombre}! Le escribimos de Equilibra. "
              "{tu mensaje} Si le interesa, respóndanos por aquí.\"). Las respuestas llegan a la bandeja y las atiende la IA.",
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
        FilledButton.icon(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), icon: const Icon(Icons.send), label: const Text("Mandar")),
      ],
    ),
  );
  ctrl.dispose();
  if (mensaje == null || mensaje.isEmpty || !context.mounted) return false;
  try {
    final r = await ApiService.post('/crm/prospectos/enviar_whatsapp/', {'ids': ids, 'mensaje': mensaje});
    final d = json.decode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) throw Exception(d['detail'] ?? ApiService.mensajeError(r));
    final partes = <String>["Enviados: ${d['enviados']}"];
    void agregar(String clave, String etiqueta) {
      final lista = (d[clave] as List?) ?? [];
      if (lista.isNotEmpty) partes.add("$etiqueta: ${lista.length}");
    }

    agregar('fuera_de_24h_sin_plantilla', "Sin plantilla aprobada (fuera de 24 h)");
    agregar('sin_numero', "Sin número");
    agregar('no_contactar', "Marcados no contactar");
    agregar('fallidos', "Fallidos");
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(partes.join(' · ')), duration: const Duration(seconds: 6)));
    return (d['enviados'] ?? 0) > 0;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    return false;
  }
}
