import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'formato.dart';
import 'theme/app_theme.dart';

/// Mensajes del negocio a SUS clientes (promoción, aviso, saludo): se escribe
/// el texto, se escoge a quién y por dónde, y se manda (backend:
/// promociones.py). Por WhatsApp sale con la plantilla de Equilibra; quien
/// responde BAJA deja de recibirlos.
class PromocionesScreen extends StatefulWidget {
  final int negocioId;
  const PromocionesScreen({super.key, required this.negocioId});

  @override
  State<PromocionesScreen> createState() => _PromocionesScreenState();
}

class _PromocionesScreenState extends State<PromocionesScreen> {
  List<Map<String, dynamic>> _historial = [];
  Map<String, dynamic>? _uso;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargarUso() async {
    try {
      final r = await ApiService.get('/promociones/uso/?negocio=${widget.negocioId}');
      if (r.statusCode == 200 && mounted) setState(() => _uso = json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
  }

  Future<void> _cargar() async {
    _cargarUso();
    try {
      final r = await ApiService.get('/promociones/?negocio=${widget.negocioId}');
      if (r.statusCode == 200 && mounted) {
        final data = json.decode(utf8.decode(r.bodyBytes));
        setState(() => _historial = ((data is Map ? data['results'] : data) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nueva() async {
    final enviada = await showDialog<bool>(
      context: context,
      builder: (_) => _NuevaPromocion(negocioId: widget.negocioId),
    );
    if (enviada == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(onPressed: _nueva, icon: const Icon(Icons.campaign_outlined), label: const Text("Nuevo mensaje")),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  "Mensajes a clientes",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textStrong),
                ),
                const SizedBox(height: 4),
                Text(
                  "Mandales una promoción, un aviso o un saludo a tus clientes por WhatsApp o correo. "
                  "Quien responda BAJA por WhatsApp deja de recibirlos.",
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                if (_uso != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      "Cada mensaje por WhatsApp cuesta ${formatearColones((_uso!['precio_mensaje'] as num).toDouble())} y se cobra a fin de mes "
                      "(por correo no tiene costo). Este mes: ${_uso!['este_mes']['cantidad']} mensajes · "
                      "${formatearColones((_uso!['este_mes']['monto'] as num).toDouble())}.",
                      style: TextStyle(fontSize: 13, color: AppColors.textStrong),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_historial.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      "Todavía no has mandado mensajes.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                for (final p in _historial)
                  Card(
                    color: AppColors.surface,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(
                        p['texto'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textStrong),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          p['enviada_en'] == null
                              ? "Sin enviar"
                              : "${aFechaCostaRica(p['enviada_en']).day}/${aFechaCostaRica(p['enviada_en']).month} · "
                                    "WhatsApp: ${p['enviados_whatsapp']} · Correo: ${p['enviados_correo']}"
                                    "${(p['fallidos'] ?? 0) > 0 ? ' · Fallidos: ${p['fallidos']}' : ''}"
                                    "${(p['sin_contacto'] ?? 0) > 0 ? ' · Sin contacto: ${p['sin_contacto']}' : ''}",
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NuevaPromocion extends StatefulWidget {
  final int negocioId;
  const _NuevaPromocion({required this.negocioId});

  @override
  State<_NuevaPromocion> createState() => _NuevaPromocionState();
}

class _NuevaPromocionState extends State<_NuevaPromocion> {
  final _textoCtrl = TextEditingController();
  final _asuntoCtrl = TextEditingController();
  String _canal = 'whatsapp';
  String _filtro = 'todos';
  Map<String, dynamic>? _resumen;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    _asuntoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarResumen() async {
    try {
      final r = await ApiService.get('/promociones/destinatarios/?negocio=${widget.negocioId}&filtro=$_filtro');
      if (r.statusCode == 200 && mounted) setState(() => _resumen = json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
  }

  int get _alcance {
    final r = _resumen;
    if (r == null) return 0;
    if (_canal == 'whatsapp') return r['whatsapp'] ?? 0;
    if (_canal == 'correo') return r['correo'] ?? 0;
    return r['total'] ?? 0;
  }

  /// Lo que cuesta por WhatsApp (por correo no se cobra).
  double get _costo {
    final r = _resumen;
    if (r == null || _canal == 'correo' || r['plantilla_whatsapp'] != true) return 0;
    return ((r['whatsapp'] ?? 0) as num) * ((r['precio_mensaje'] ?? 0) as num).toDouble();
  }

  Future<void> _enviar() async {
    final texto = _textoCtrl.text.trim();
    if (texto.isEmpty) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Mandar el mensaje?"),
        content: Text(
          "Le va a llegar a $_alcance cliente${_alcance == 1 ? '' : 's'}.${_costo > 0 ? ' Costo por WhatsApp: ${formatearColones(_costo)} (se cobra a fin de mes).' : ''} No se puede deshacer.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Mandar")),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _enviando = true);
    try {
      final creada = await ApiService.post('/promociones/', {
        'negocio': widget.negocioId,
        'texto': texto,
        'asunto': _asuntoCtrl.text.trim(),
        'canal': _canal,
        'filtro': _filtro,
      });
      if (creada.statusCode != 201) throw Exception(ApiService.mensajeError(creada));
      final id = json.decode(utf8.decode(creada.bodyBytes))['id'];
      final r = await ApiService.post('/promociones/$id/enviar/', {});
      final data = json.decode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200) throw Exception(data['detail'] ?? ApiService.mensajeError(r));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Listo: ${data['enviados_whatsapp']} por WhatsApp y ${data['enviados_correo']} por correo."), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sinPlantilla = _resumen != null && _resumen!['plantilla_whatsapp'] != true;
    return AlertDialog(
      title: const Text("Nuevo mensaje a clientes"),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _textoCtrl,
                minLines: 4,
                maxLines: 8,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: "Mensaje",
                  hintText: "Ej.: ¡Esta semana 15 % de descuento en todos los productos! Le esperamos.",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text("¿Por dónde?", style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'whatsapp', label: Text("WhatsApp")),
                  ButtonSegment(value: 'correo', label: Text("Correo")),
                  ButtonSegment(value: 'ambos', label: Text("Los dos")),
                ],
                selected: {_canal},
                onSelectionChanged: (s) => setState(() => _canal = s.first),
              ),
              if (sinPlantilla && _canal != 'correo')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "El envío por WhatsApp todavía no está habilitado (falta la aprobación de Meta). Por ahora usá correo.",
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                  ),
                ),
              if (_canal != 'whatsapp') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _asuntoCtrl,
                  decoration: const InputDecoration(labelText: "Asunto del correo (opcional)", border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 12),
              const Text("¿A quién?", style: TextStyle(fontWeight: FontWeight.w700)),
              RadioGroup<String>(
                groupValue: _filtro,
                onChanged: (v) {
                  setState(() => _filtro = v!);
                  _cargarResumen();
                },
                child: const Column(
                  children: [
                    RadioListTile<String>(value: 'todos', title: Text("Todos mis clientes"), dense: true, contentPadding: EdgeInsets.zero),
                    RadioListTile<String>(value: 'con_saldo', title: Text("Los que tienen saldo pendiente"), dense: true, contentPadding: EdgeInsets.zero),
                  ],
                ),
              ),
              if (_resumen != null)
                Text(
                  "Le llegaría a $_alcance de ${_resumen!['total']} clientes "
                  "(${_resumen!['whatsapp']} con WhatsApp, ${_resumen!['correo']} con correo).",
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _enviando ? null : () => Navigator.pop(context, false), child: const Text("Cancelar")),
        ElevatedButton.icon(
          onPressed: _enviando || _alcance == 0 ? null : _enviar,
          icon: _enviando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
          label: const Text("Mandar"),
        ),
      ],
    );
  }
}
