import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'theme/app_theme.dart';

/// CRM de la plataforma (solo superusuario): las personas interesadas en
/// Equilibra en un embudo por etapas -- backend: crm.py (ProspectoViewSet).
/// Las fichas se arman solas desde el chat de la landing, WhatsApp y el
/// autorregistro; los correos de seguimiento de "Gabriel de Equilibra"
/// salen solos todos los días (acá se ve cuáles recibió cada uno).
class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

const _etapas = [
  ('conversando', 'Conversó', Icons.forum_outlined),
  ('registrado', 'Registrado', Icons.person_add_alt_outlined),
  ('en_prueba', 'En prueba', Icons.hourglass_top_rounded),
  ('pagando', 'Pagando', Icons.verified_outlined),
  ('perdido', 'Perdido', Icons.do_not_disturb_on_outlined),
];

/// Un color sobrio por etapa (tonos medios: se leen igual en tema claro y
/// oscuro, y se distinguen también por claridad, no solo por tono). Se usa
/// en detalles -- franja de la columna, ícono, contador, punto de la
/// tarjeta -- nunca como fondo grande.
const _colorEtapa = {
  'conversando': Color(0xFF8FA3BF), // gris azulado
  'registrado': Color(0xFFA78BFA), // violeta
  'en_prueba': Color(0xFFF2B33D), // ámbar
  'pagando': Color(0xFF34C38F), // verde
  'perdido': Color(0xFFE5737A), // rojo suave
};
Color _colorDe(String? etapa) => _colorEtapa[etapa] ?? const Color(0xFF8FA3BF);

class _CrmScreenState extends State<CrmScreen> {
  List<Map<String, dynamic>> _prospectos = [];
  Map<String, dynamic> _resumen = {};
  bool _cargando = true;
  String? _error;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await ApiService.get('/crm/prospectos/');
      if (!mounted) return;
      if (r.statusCode != 200) {
        setState(() => _error = "No se pudo cargar el CRM: ${ApiService.mensajeError(r)}");
        return;
      }
      final datos = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _prospectos = (datos['prospectos'] as List).cast<Map<String, dynamic>>();
        _resumen = (datos['resumen'] as Map?)?.cast<String, dynamic>() ?? {};
      });
    } catch (e) {
      if (mounted) setState(() => _error = "No se pudo cargar el CRM: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> _deEtapa(String etapa) {
    final q = _busqueda.trim().toLowerCase();
    return _prospectos.where((p) {
      if (p['etapa'] != etapa) return false;
      if (q.isEmpty) return true;
      return [p['nombre'], p['correo'], p['telefono'], p['canal']].any((v) => (v ?? '').toString().toLowerCase().contains(q));
    }).toList();
  }

  // ---------------------------------------------------------------- piezas

  String _haceCuanto(String? iso) {
    final fecha = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (fecha == null) return '';
    final dif = DateTime.now().difference(fecha);
    if (dif.inMinutes < 60) return 'hace ${dif.inMinutes.clamp(1, 59)} min';
    if (dif.inHours < 24) return 'hace ${dif.inHours} h';
    if (dif.inDays == 1) return 'ayer';
    if (dif.inDays < 30) return 'hace ${dif.inDays} días';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  Widget _numero(String titulo, String valor, {String? detalle}) {
    return Container(
      width: 168,
      height: 104,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(color: AppColors.textStrong, fontSize: 24, fontWeight: FontWeight.w800),
          ),
          if (detalle != null)
            Text(
              detalle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
        ],
      ),
    );
  }

  Widget _numeros() {
    final porEtapa = (_resumen['por_etapa'] as Map?) ?? {};
    final conversion = _resumen['conversion_90_dias'];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _numero("Nuevos (7 días)", "${_resumen['nuevos_7_dias'] ?? 0}"),
        _numero("En prueba", "${porEtapa['en_prueba'] ?? 0}"),
        _numero("Pagando", "${porEtapa['pagando'] ?? 0}"),
        _numero("Conversión", conversion == null ? "—" : "$conversion%", detalle: "de los últimos 90 días"),
        _numero("Correos de Gabriel", "${_resumen['correos_7_dias'] ?? 0}", detalle: "últimos 7 días"),
      ],
    );
  }

  /// Qué conexiones del CRM están activas (las que faltan se configuran con
  /// variables en Railway, ver crm.py).
  Widget _conexiones() {
    Widget conexion(String nombre, bool activa, String comoActivar) => Tooltip(
      message: activa ? "$nombre: activo" : "$nombre: apagado. $comoActivar",
      child: Chip(
        avatar: Icon(activa ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: activa ? Colors.green : AppColors.textMuted),
        label: Text(nombre, style: TextStyle(fontSize: 12, color: activa ? AppColors.textStrong : AppColors.textMuted)),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: AppColors.border),
        backgroundColor: AppColors.surface,
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          "Conexiones:",
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        conexion("Correos de Gabriel", true, ""),
        conexion("WhatsApp", _resumen['whatsapp_activo'] == true, "Falta aprobar las plantillas en Meta (WHATSAPP_PLANTILLAS_CRM)."),
        conexion("Formularios de anuncios", _resumen['entrada_anuncios_activa'] == true, "Falta CRM_TOKEN_ENTRADA y conectar Zapier o Make."),
        conexion("Conversiones a Meta", _resumen['meta_activo'] == true, "Falta META_PIXEL_ID y META_CAPI_TOKEN."),
      ],
    );
  }

  Future<void> _agregarProspecto() async {
    final campos = {
      for (final k in ['nombre', 'correo', 'telefono', 'canal', 'notas']) k: TextEditingController(),
    };
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Agregar prospecto", style: TextStyle(color: AppColors.textStrong)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (clave, etiqueta, tipo) in [
                ('nombre', "Nombre o negocio", TextInputType.name),
                ('correo', "Correo", TextInputType.emailAddress),
                ('telefono', "Teléfono / WhatsApp", TextInputType.phone),
                ('canal', "¿De dónde salió? (feria, referido...)", TextInputType.text),
                ('notas', "Notas", TextInputType.multiline),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: campos[clave],
                    keyboardType: tipo,
                    maxLines: clave == 'notas' ? 3 : 1,
                    decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder(), isDense: true),
                  ),
                ),
              Text("No le salen correos automáticos: es para tu seguimiento a mano.", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Agregar")),
        ],
      ),
    );
    if (guardar != true) return;
    try {
      final r = await ApiService.post('/crm/prospectos/', {for (final e in campos.entries) e.key: e.value.text.trim()});
      if (r.statusCode != 201) throw Exception(ApiService.mensajeError(r));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo agregar: $e")));
    }
  }

  Widget _chip(String texto, {Color? color}) {
    final c = color ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(
        texto,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _tituloEtapa(String clave) => _etapas.firstWhere((e) => e.$1 == clave, orElse: () => (clave, clave, Icons.circle)).$2;

  /// Pasa la tarjeta a otra etapa (arrastrándola o con "Mover a…"): se ve
  /// al instante, se guarda fijada a mano y ofrece deshacer.
  Future<void> _moverA(Map<String, dynamic> p, String etapa, {bool deshaciendo = false}) async {
    final anterior = p['etapa'] as String;
    final anteriorFijada = p['etapa_fijada'] == true;
    if (anterior == etapa && !deshaciendo) return;
    void aplicar(String nueva, bool fijada) {
      final porEtapa = (_resumen['por_etapa'] as Map?)?.cast<String, dynamic>();
      if (porEtapa != null && p['etapa'] != nueva) {
        porEtapa[p['etapa']] = ((porEtapa[p['etapa']] as num?) ?? 1) - 1;
        porEtapa[nueva] = ((porEtapa[nueva] as num?) ?? 0) + 1;
      }
      p['etapa'] = nueva;
      p['etapa_texto'] = _tituloEtapa(nueva);
      p['etapa_fijada'] = fijada;
    }

    setState(() => aplicar(etapa, true));
    try {
      final r = await ApiService.patch('/crm/prospectos/${p['id']}/', {'etapa': etapa});
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
    } catch (e) {
      if (!mounted) return;
      setState(() => aplicar(anterior, anteriorFijada));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo mover: $e")));
      return;
    }
    if (!mounted || deshaciendo) return;
    final nombre = (p['nombre'] ?? '').toString().trim();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text("${nombre.isNotEmpty ? nombre : 'Prospecto'} → ${_tituloEtapa(etapa)}"),
          action: SnackBarAction(
            label: "Deshacer",
            onPressed: () async {
              if (anteriorFijada) {
                await _moverA(p, anterior, deshaciendo: true);
              } else {
                // Estaba en automática: se devuelve a automática (el servidor la recalcula).
                setState(() => aplicar(anterior, false));
                final r = await ApiService.patch('/crm/prospectos/${p['id']}/', {'etapa': 'auto'});
                if (r.statusCode == 200) _cargar();
              }
            },
          ),
        ),
      );
  }

  Future<void> _menuMover(Map<String, dynamic> p) async {
    final etapa = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Mover a…",
                  style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            for (final (clave, titulo, icono) in _etapas)
              ListTile(
                leading: Icon(icono, color: _colorDe(clave)),
                title: Text(titulo, style: TextStyle(color: AppColors.textStrong)),
                trailing: clave == p['etapa'] ? Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(ctx, clave),
              ),
          ],
        ),
      ),
    );
    if (etapa != null) _moverA(p, etapa);
  }

  /// En el tablero de escritorio la tarjeta se arrastra a otra columna.
  Widget _tarjetaArrastrable(Map<String, dynamic> p, double ancho) {
    return Draggable<Map<String, dynamic>>(
      data: p,
      feedback: Material(
        color: Colors.transparent,
        elevation: 10,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: ancho,
          child: Transform.rotate(angle: -0.02, child: _tarjeta(p)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _tarjeta(p)),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: _tarjeta(p)),
    );
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final nombre = (p['nombre'] ?? '').toString().trim();
    final contacto = (p['correo'] ?? '').toString().isNotEmpty ? p['correo'].toString() : (p['telefono'] ?? '').toString();
    final dias = p['dias_restantes_prueba'];
    final seguimientos = (p['seguimientos'] as List?)?.length ?? 0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirFicha(p['id'] as int),
        // En celular (pestañas) no se arrastra entre columnas: "Mover a…".
        onLongPress: () => _menuMover(p),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Tooltip(
                    message: _tituloEtapa(p['etapa'] as String),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: _colorDe(p['etapa'] as String?), shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      nombre.isNotEmpty ? nombre : contacto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (nombre.isNotEmpty && contacto.isNotEmpty)
                Text(
                  contacto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(p['origen_texto']?.toString() ?? ''),
                  if ((p['canal'] ?? '').toString().isNotEmpty) _chip(p['canal'].toString()),
                  if ((p['tipo_cuenta'] ?? '').toString().isNotEmpty) _chip(p['tipo_cuenta'].toString()),
                  if (dias != null) _chip(dias == 0 ? "Vence hoy" : "Vence en $dias días", color: (dias as int) <= 2 ? Colors.orange : AppColors.primary),
                  if (p['no_contactar'] == true) _chip("No contactar", color: Colors.redAccent),
                  if (p['etapa_fijada'] == true) _chip("Etapa a mano"),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(_haceCuanto(p['ultima_actividad_en'] ?? p['creado_en']), style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                  ),
                  if (seguimientos > 0) ...[
                    Icon(Icons.mail_outline, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text("$seguimientos", style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _columna(String etapa, String titulo, IconData icono, {double? ancho}) {
    final lista = _deEtapa(etapa);
    final contenido = lista.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text("Nadie en esta etapa", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => ancho == null ? _tarjeta(lista[i]) : _tarjetaArrastrable(lista[i], ancho - 20),
          );
    if (ancho == null) return Padding(padding: const EdgeInsets.all(12), child: contenido);
    // Columna del tablero: recibe las tarjetas que se sueltan encima.
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) => d.data['etapa'] != etapa,
      onAcceptWithDetails: (d) => _moverA(d.data, etapa),
      builder: (context, candidatas, _) {
        final color = _colorDe(etapa);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: ancho,
          margin: const EdgeInsets.only(right: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: candidatas.isNotEmpty ? color.withOpacity(0.10) : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: candidatas.isNotEmpty ? color : Colors.transparent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Franja fina con el color de la etapa.
              Container(height: 3, color: color),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    Icon(icono, size: 17, color: color),
                    const SizedBox(width: 6),
                    Text(
                      titulo,
                      style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 6),
                    _chip("${lista.length}", color: color),
                  ],
                ),
              ),
              Expanded(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: contenido),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- ficha

  Future<void> _abrirFicha(int id) async {
    final r = await ApiService.get('/crm/prospectos/$id/');
    if (!mounted) return;
    if (r.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir la ficha: ${ApiService.mensajeError(r)}")));
      return;
    }
    final p = (json.decode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
    final cambio = await showDialog<bool>(
      context: context,
      builder: (_) => _FichaProspecto(prospecto: p),
    );
    if (cambio == true) _cargar();
  }

  // ---------------------------------------------------------------- pantalla

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final cabecera = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _numeros(),
          const SizedBox(height: 12),
          _conexiones(),
          const SizedBox(height: 12),
          SizedBox(
            width: 420,
            child: TextField(
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: "Buscar por nombre, correo, teléfono o canal",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );

    Widget cuerpo;
    if (_cargando && _prospectos.isEmpty) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      cuerpo = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    } else if (ancho >= 1000) {
      cuerpo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cabecera,
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 16),
              children: [for (final (clave, titulo, icono) in _etapas) _columna(clave, titulo, icono, ancho: 280)],
            ),
          ),
        ],
      );
    } else {
      cuerpo = DefaultTabController(
        length: _etapas.length,
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(child: cabecera),
            SliverToBoxAdapter(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final (clave, titulo, icono) in _etapas)
                    Tab(
                      icon: Icon(icono, size: 18, color: _colorDe(clave)),
                      iconMargin: const EdgeInsets.only(bottom: 2),
                      text: "$titulo (${_deEtapa(clave).length})",
                    ),
                ],
              ),
            ),
          ],
          body: TabBarView(children: [for (final (clave, titulo, icono) in _etapas) _columna(clave, titulo, icono)]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Clientes potenciales"),
        actions: [IconButton(tooltip: "Recargar", icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      body: cuerpo,
      floatingActionButton: FloatingActionButton.extended(onPressed: _agregarProspecto, icon: const Icon(Icons.person_add_alt_1), label: const Text("Agregar prospecto")),
    );
  }
}

/// Ficha de un prospecto: datos, conversación, correos que recibió, etapa a
/// mano, notas y "no contactar". Devuelve true si guardó algo.
class _FichaProspecto extends StatefulWidget {
  final Map<String, dynamic> prospecto;
  const _FichaProspecto({required this.prospecto});

  @override
  State<_FichaProspecto> createState() => _FichaProspectoState();
}

class _FichaProspectoState extends State<_FichaProspecto> {
  late final TextEditingController _notas = TextEditingController(text: (widget.prospecto['notas'] ?? '').toString());
  late String _etapa = widget.prospecto['etapa_fijada'] == true ? widget.prospecto['etapa'] as String : 'auto';
  late bool _noContactar = widget.prospecto['no_contactar'] == true;
  bool _guardando = false;

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  Map<String, dynamic> get p => widget.prospecto;

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final r = await ApiService.patch('/crm/prospectos/${p['id']}/', {'notas': _notas.text, 'no_contactar': _noContactar, 'etapa': _etapa});
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo guardar: $e")));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _abrir(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo abrir.")));
    }
  }

  Widget _dato(String etiqueta, String? valor) {
    if (valor == null || valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(etiqueta, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(valor, style: TextStyle(color: AppColors.textStrong, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _fecha(String? iso) {
    final f = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return f == null ? '' : '${f.day}/${f.month}/${f.year}';
  }

  @override
  Widget build(BuildContext context) {
    final telefono = (p['telefono'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    // Solo con código de país (el que sea): un número de 8 dígitos puede ser
    // de Costa Rica, Panamá, Nicaragua... y no se adivina.
    final whatsapp = telefono.length > 8 ? telefono : null;
    final correo = (p['correo'] ?? '').toString();
    final seguimientos = (p['seguimientos'] as List?)?.cast<Map>() ?? [];
    final conversacion = (p['conversacion'] ?? '').toString();
    return AlertDialog(
      // Mismo fondo que la pantalla: los textos usan AppColors (tema claro u oscuro).
      backgroundColor: AppColors.surface,
      title: Text((p['nombre'] ?? '').toString().trim().isNotEmpty ? p['nombre'] : (correo.isNotEmpty ? correo : telefono), style: TextStyle(color: AppColors.textStrong)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (whatsapp != null)
                    FilledButton.icon(
                      onPressed: () => _abrir(Uri.parse('https://wa.me/$whatsapp')),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1DA851)),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text("WhatsApp"),
                    ),
                  if (correo.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _abrir(Uri(scheme: 'mailto', path: correo)),
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: const Text("Correo"),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _dato("Correo", correo),
              _dato("Teléfono", p['telefono']?.toString()),
              _dato("Origen", p['origen_texto']?.toString()),
              _dato("Canal", p['canal']?.toString()),
              _dato("Tipo de cuenta", p['tipo_cuenta']?.toString()),
              _dato("Cuenta creada", _fecha(p['cuenta_creada_en'])),
              if (p['cuenta_creada_en'] != null) _dato("Correo confirmado", p['correo_confirmado'] == true ? "Sí" : "No"),
              _dato("Prueba", p['prueba_vence'] == null ? null : "${p['prueba_inicio'] ?? ''} → ${p['prueba_vence']}"),
              _dato("Primera pregunta", p['primera_pregunta']?.toString()),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _etapa,
                decoration: const InputDecoration(labelText: "Etapa", border: OutlineInputBorder()),
                items: [
                  DropdownMenuItem(value: 'auto', child: Text("Automática (ahora: ${p['etapa_texto']})")),
                  for (final (clave, titulo, _) in _etapas) DropdownMenuItem(value: clave, child: Text("$titulo (fijada a mano)")),
                ],
                onChanged: (v) => setState(() => _etapa = v ?? 'auto'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notas,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: "Notas", border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _noContactar,
                onChanged: (v) => setState(() => _noContactar = v),
                title: const Text("No contactar"),
                subtitle: const Text("No le salen más correos automáticos."),
              ),
              const SizedBox(height: 8),
              Text(
                "Correos de Gabriel",
                style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (seguimientos.isEmpty)
                Text("Todavía ninguno.", style: TextStyle(color: AppColors.textMuted, fontSize: 13))
              else
                for (final s in seguimientos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text("• ${s['asunto']} — ${_fecha(s['enviado_en']?.toString())}", style: TextStyle(color: AppColors.textStrong, fontSize: 13)),
                  ),
              if (conversacion.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  "Conversación",
                  style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(10)),
                  child: SingleChildScrollView(
                    child: SelectableText(conversacion, style: TextStyle(color: AppColors.textStrong, fontSize: 12.5)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cerrar")),
        FilledButton(onPressed: _guardando ? null : _guardar, child: const Text("Guardar")),
      ],
    );
  }
}
