import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'theme/app_theme.dart';

/// Rubros frecuentes para buscar con un toque (lo que se le pide a Google).
const _rubros = [
  ('Sodas y restaurantes', 'sodas y restaurantes'),
  ('Ferreterías', 'ferreterías'),
  ('Salones de belleza', 'salones de belleza y barberías'),
  ('Talleres mecánicos', 'talleres mecánicos'),
  ('Farmacias', 'farmacias'),
  ('Minisúper y pulperías', 'minisúper y pulperías'),
  ('Tiendas de ropa', 'tiendas de ropa'),
  ('Veterinarias', 'veterinarias'),
  ('Clínicas dentales', 'clínicas dentales'),
  ('Abogados', 'abogados y notarios'),
  ('Contadores', 'contadores y despachos contables'),
  ('Constructoras', 'constructoras'),
  ('Panaderías', 'panaderías'),
  ('Gimnasios', 'gimnasios'),
];

/// Zonas de Costa Rica: provincias y cantones con más comercio.
const _zonas = [
  'San José',
  'Escazú',
  'Santa Ana',
  'Desamparados',
  'Curridabat',
  'Moravia',
  'Tibás',
  'Goicoechea',
  'Pérez Zeledón',
  'Alajuela',
  'San Ramón',
  'Grecia',
  'Naranjo',
  'Atenas',
  'San Carlos',
  'Cartago',
  'Paraíso',
  'La Unión',
  'Turrialba',
  'Heredia',
  'Belén',
  'Santo Domingo',
  'San Pablo',
  'Barva',
  'Guanacaste',
  'Liberia',
  'Nicoya',
  'Santa Cruz',
  'Puntarenas',
  'Esparza',
  'Quepos',
  'Limón',
  'Guápiles',
  'Siquirres',
];

/// Buscar negocios en Google Maps y meterlos al CRM como prospectos
/// (backend: crm_maps.py). Se busca por rubro y zona (o texto libre), se
/// filtra y ordena, y al agregarlos se les escribe con un mensaje que la IA
/// arma según el rubro.
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
  String? _rubro;
  String? _zona;
  bool _buscando = false;
  bool _agregando = false;

  // Filtros y orden (sobre lo que ya trajo Google: no gastan búsquedas).
  bool _soloCelular = true;
  bool _ocultarEnCrm = true;
  bool _soloSinWeb = false;
  int _minResenas = 0;
  String _orden = 'resenas';

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  String get _consulta {
    final libre = _textoCtrl.text.trim();
    if (libre.isNotEmpty) return libre;
    if (_rubro == null) return '';
    return "$_rubro en ${_zona ?? 'Costa Rica'}${_zona != null ? ', Costa Rica' : ''}";
  }

  List<Map<String, dynamic>> get _visibles {
    final lista = _lugares.where((l) {
      if (_soloCelular && l['celular'] != true) return false;
      if (_ocultarEnCrm && l['ya_en_crm'] == true) return false;
      if (_soloSinWeb && (l['sitio_web'] ?? '').toString().isNotEmpty) return false;
      if (((l['resenas'] ?? 0) as num) < _minResenas) return false;
      return true;
    }).toList();
    num valor(Map<String, dynamic> l) => _orden == 'calificacion' ? ((l['calificacion'] ?? 0) as num) : ((l['resenas'] ?? 0) as num);
    if (_orden != 'google') lista.sort((a, b) => valor(b).compareTo(valor(a)));
    return lista;
  }

  Future<void> _buscar({bool mas = false}) async {
    final texto = mas ? _busqueda : _consulta;
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Escogé un rubro o escribí qué buscar.")));
      return;
    }
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
      final elegidos = _visibles.where((l) => _elegidos.contains(l['place_id'])).toList();
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
              if (ids.isNotEmpty) "¿Les querés escribir por WhatsApp ahora a los ${ids.length} con celular? La IA te propone un mensaje según el rubro.",
            ].join(' '),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ids.isEmpty ? "Listo" : "Después")),
            if (ids.isNotEmpty) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Escribirles")),
          ],
        ),
      );
      if (escribir == true && mounted) {
        final categoria = elegidos.map((l) => (l['categoria'] ?? '').toString()).firstWhere((c) => c.isNotEmpty, orElse: () => '');
        await enviarWhatsAppProspectos(context, ids, categoria: categoria.isNotEmpty ? categoria : _rubro);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    } finally {
      if (mounted) setState(() => _agregando = false);
    }
  }

  Widget _filtro(String etiqueta, bool valor, ValueChanged<bool> cambiar) =>
      FilterChip(label: Text(etiqueta), selected: valor, onSelected: (v) => setState(() => cambiar(v)));

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final elegidosVisibles = visibles.where((l) => _elegidos.contains(l['place_id'])).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Buscar prospectos en Google Maps")),
      bottomNavigationBar: elegidosVisibles == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _agregando ? null : _agregar,
                  icon: _agregando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.person_add_alt_1),
                  label: Text("Agregar $elegidosVisibles al CRM"),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            "Rubro",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (etiqueta, consulta) in _rubros)
                ChoiceChip(
                  label: Text(etiqueta),
                  selected: _rubro == consulta,
                  onSelected: (v) => setState(() {
                    _rubro = v ? consulta : null;
                    if (v) _textoCtrl.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _zona,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Zona", border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text("Todo Costa Rica")),
                    for (final z in _zonas) DropdownMenuItem(value: z, child: Text(z)),
                  ],
                  onChanged: (v) => setState(() => _zona = v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _buscando ? null : () => _buscar(), icon: const Icon(Icons.search), label: const Text("Buscar")),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textoCtrl,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              if (v.trim().isNotEmpty && _rubro != null) setState(() => _rubro = null);
            },
            onSubmitted: (_) => _buscar(),
            decoration: const InputDecoration(
              hintText: "O escribí la búsqueda: ej. distribuidoras de abarrotes en Cartago",
              prefixIcon: Icon(Icons.travel_explore),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_lugares.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filtro("Solo celulares", _soloCelular, (v) => _soloCelular = v),
                _filtro("Ocultar los del CRM", _ocultarEnCrm, (v) => _ocultarEnCrm = v),
                _filtro("Sin sitio web", _soloSinWeb, (v) => _soloSinWeb = v),
                DropdownButton<int>(
                  value: _minResenas,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text("Cualquier cantidad de reseñas")),
                    DropdownMenuItem(value: 10, child: Text("10+ reseñas")),
                    DropdownMenuItem(value: 50, child: Text("50+ reseñas")),
                    DropdownMenuItem(value: 200, child: Text("200+ reseñas")),
                  ],
                  onChanged: (v) => setState(() => _minResenas = v ?? 0),
                ),
                DropdownButton<String>(
                  value: _orden,
                  items: const [
                    DropdownMenuItem(value: 'resenas', child: Text("Más reseñas primero")),
                    DropdownMenuItem(value: 'calificacion', child: Text("Mejor calificación")),
                    DropdownMenuItem(value: 'google', child: Text("Orden de Google")),
                  ],
                  onChanged: (v) => setState(() => _orden = v ?? 'resenas'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${visibles.length} de ${_lugares.length} con estos filtros · $elegidosVisibles marcados",
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    final ids = visibles.where((l) => l['ya_en_crm'] != true).map((l) => l['place_id'] as String).toSet();
                    _elegidos.containsAll(ids) ? _elegidos.removeAll(ids) : _elegidos.addAll(ids);
                  }),
                  child: const Text("Marcar / desmarcar todos"),
                ),
              ],
            ),
          ],
          if (_lugares.isEmpty && _buscando)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final l in visibles)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _elegidos.contains(l['place_id']),
              onChanged: l['ya_en_crm'] == true ? null : (v) => setState(() => v == true ? _elegidos.add(l['place_id']) : _elegidos.remove(l['place_id'])),
              title: Text(
                l['nombre'] ?? '',
                style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      l['categoria'],
                      if (l['calificacion'] != null) "⭐ ${l['calificacion']} (${l['resenas']} reseñas)",
                      l['direccion'],
                    ].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  Row(
                    children: [
                      Icon(l['celular'] == true ? Icons.phone_android : Icons.phone, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          (l['telefono'] ?? '').toString().isEmpty ? "Sin teléfono" : l['telefono'],
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                      if ((l['sitio_web'] ?? '').toString().isEmpty) ...[
                        const SizedBox(width: 8),
                        Text("Sin web", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
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
          if (_lugares.isNotEmpty && visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Ninguno cumple los filtros. Quitá alguno o cargá más resultados.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          if (_siguiente != null)
            Center(
              child: TextButton(
                onPressed: _buscando ? null : () => _buscar(mas: true),
                child: Text(_buscando ? "Buscando..." : "Cargar 20 más (cuenta como otra búsqueda)"),
              ),
            ),
        ],
      ),
    );
  }
}

/// Escribirle por WhatsApp a uno o varios prospectos (backend:
/// crm/prospectos/enviar_whatsapp/). El mensaje lo propone la IA según el
/// rubro (`categoria`, o el de los prospectos) y se puede editar. Devuelve
/// true si salió alguno.
Future<bool> enviarWhatsAppProspectos(BuildContext context, List<int> ids, {String? nombre, String? categoria}) async {
  final mensaje = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoMensajeProspectos(ids: ids, nombre: nombre, categoria: categoria),
  );
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

class _DialogoMensajeProspectos extends StatefulWidget {
  final List<int> ids;
  final String? nombre;
  final String? categoria;
  const _DialogoMensajeProspectos({required this.ids, this.nombre, this.categoria});

  @override
  State<_DialogoMensajeProspectos> createState() => _DialogoMensajeProspectosState();
}

class _DialogoMensajeProspectosState extends State<_DialogoMensajeProspectos> {
  final _ctrl = TextEditingController();
  bool _sugiriendo = false;
  String? _rubro;

  @override
  void initState() {
    super.initState();
    _sugerir();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _sugerir() async {
    setState(() => _sugiriendo = true);
    try {
      final r = await ApiService.post('/crm/prospectos/sugerir_mensaje/', {
        'ids': widget.ids,
        if ((widget.categoria ?? '').isNotEmpty) 'categoria': widget.categoria,
      });
      final d = json.decode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200) throw Exception(d['detail'] ?? ApiService.mensajeError(r));
      if (!mounted) return;
      setState(() {
        _ctrl.text = d['mensaje'] ?? '';
        _rubro = (d['categoria'] ?? '').toString();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    } finally {
      if (mounted) setState(() => _sugiriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.ids;
    final saludo = widget.nombre ?? '{nombre del negocio}';
    return AlertDialog(
      title: Text(widget.nombre != null ? "WhatsApp a ${widget.nombre}" : "WhatsApp a ${ids.length} prospecto${ids.length == 1 ? '' : 's'}"),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ctrl,
                minLines: 3,
                maxLines: 6,
                maxLength: 900,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: "Tu mensaje",
                  hintText: _sugiriendo ? "La IA está escribiendo un mensaje según el rubro..." : "Escribí el mensaje",
                  border: const OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _sugiriendo ? null : _sugerir,
                    icon: _sugiriendo
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_sugiriendo ? "Escribiendo..." : "Sugerir con IA"),
                  ),
                  if ((_rubro ?? '').isNotEmpty)
                    Flexible(
                      child: Text("según el rubro: $_rubro", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text("Así le llega (si no te escribió en las últimas 24 h):", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF25D366).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  "¡Hola $saludo! Le escribimos de Equilibra. ${_ctrl.text.trim().isEmpty ? '…' : _ctrl.text.trim()} Si le interesa, respóndanos por aquí.",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              Text("Las respuestas llegan a la bandeja de WhatsApp y las atiende la IA.", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
        FilledButton.icon(
          onPressed: _ctrl.text.trim().isEmpty ? null : () => Navigator.pop(context, _ctrl.text.trim()),
          icon: const Icon(Icons.send),
          label: const Text("Mandar"),
        ),
      ],
    );
  }
}
