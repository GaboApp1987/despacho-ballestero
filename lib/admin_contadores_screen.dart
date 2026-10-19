import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Panel del administrador: todos los contadores de la plataforma, también
/// los independientes (sin despacho), que antes no aparecían en ninguna
/// parte del panel. Backend: gestion/admin_contadores.py.
class AdminContadoresScreen extends StatefulWidget {
  const AdminContadoresScreen({super.key});

  @override
  State<AdminContadoresScreen> createState() => _AdminContadoresScreenState();
}

String _fecha(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  return "${d.day}/${d.month}/${d.year}";
}

class _AdminContadoresScreenState extends State<AdminContadoresScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _contadores = [];
  List<Map<String, dynamic>> _despachos = [];
  int _independientes = 0;
  bool _soloIndependientes = false;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = ApiService.verificar(await ApiService.get('/admin/contadores/'));
      final datos = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      _contadores = (datos['contadores'] as List).cast<Map<String, dynamic>>();
      _despachos = (datos['despachos'] as List).cast<Map<String, dynamic>>();
      _independientes = datos['independientes'] as int? ?? 0;
    } catch (e) {
      if (mounted) _aviso(ApiService.textoError(e));
    }
    if (mounted) setState(() => _cargando = false);
  }

  List<Map<String, dynamic>> get _filtrados {
    final b = _busqueda.toLowerCase();
    return _contadores.where((c) {
      if (_soloIndependientes && c['despacho'] != null) return false;
      if (b.isEmpty) return true;
      final negocios = (c['negocios'] as List).map((n) => '${n['nombre']} ${n['cedula']}').join(' ');
      return '${c['nombre']} ${c['email']} ${c['usuario'] ?? ''} $negocios'.toLowerCase().contains(b);
    }).toList();
  }

  void _reemplazar(Map<String, dynamic> nuevo) {
    final i = _contadores.indexWhere((c) => c['id'] == nuevo['id']);
    if (i >= 0) setState(() => _contadores[i] = nuevo);
  }

  Future<void> _abrir(Map<String, dynamic> c) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _Detalle(
        contador: c,
        despachos: _despachos,
        alCambiar: (nuevo) {
          _reemplazar(nuevo);
          c = nuevo;
        },
      ),
    );
    _cargar();
  }

  Widget _chip(String texto, Color color, {IconData? icono}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icono != null) ...[Icon(icono, size: 12, color: color), const SizedBox(width: 4)],
          Text(texto, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(
        title: const Text("Contadores"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [const BotonCalculadora(), IconButton(tooltip: "Actualizar", icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Buscar por nombre, usuario, correo o negocio...",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                    ),
                    onChanged: (v) => setState(() => _busqueda = v.trim()),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      label: Text("Todos (${_contadores.length})"),
                      selected: !_soloIndependientes,
                      onSelected: (_) => setState(() => _soloIndependientes = false),
                    ),
                    ChoiceChip(
                      label: Text("Independientes ($_independientes)"),
                      selected: _soloIndependientes,
                      onSelected: (_) => setState(() => _soloIndependientes = true),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  if (lista.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text("Ningún contador coincide.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                    ),
                  for (final c in lista)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: AppColors.surface,
                      child: ListTile(
                        onTap: () => _abrir(c),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                          child: Text('${c['nombre']}'.isEmpty ? '?' : '${c['nombre']}'[0].toUpperCase(),
                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                        ),
                        title: Text('${c['nombre']}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text("${c['usuario'] != null ? '@${c['usuario']} · ' : ''}${c['email']}",
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            c['despacho'] == null
                                ? _chip("Independiente", const Color(0xFF7C3AED), icono: Icons.person_outline)
                                : _chip('${c['despacho_nombre']}', const Color(0xFF2563EB), icono: Icons.account_balance_outlined),
                            _chip("${(c['negocios'] as List).length} negocio${(c['negocios'] as List).length == 1 ? '' : 's'}", AppColors.textMuted),
                            if (c['activo'] != true) _chip("Acceso desactivado", const Color(0xFFDC2626)),
                            c['ultimo_ingreso'] == null
                                ? _chip("Nunca ha entrado", const Color(0xFFD97706))
                                : _chip("Entró ${_fecha(c['ultimo_ingreso'])}", const Color(0xFF16A34A)),
                          ]),
                        ]),
                        isThreeLine: true,
                        trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Detalle extends StatefulWidget {
  final Map<String, dynamic> contador;
  final List<Map<String, dynamic>> despachos;
  final void Function(Map<String, dynamic>) alCambiar;
  const _Detalle({required this.contador, required this.despachos, required this.alCambiar});

  @override
  State<_Detalle> createState() => _DetalleState();
}

class _DetalleState extends State<_Detalle> {
  late Map<String, dynamic> c = widget.contador;
  bool _trabajando = false;

  String get _base => '/admin/contadores/${c['id']}/';

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _guardar(Map<String, dynamic> datos, String listo) async {
    setState(() => _trabajando = true);
    try {
      final r = ApiService.verificar(await ApiService.patch(_base, datos));
      final nuevo = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      setState(() => c = nuevo);
      widget.alCambiar(nuevo);
      _aviso(listo);
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _editar() async {
    final nombre = TextEditingController(text: '${c['nombre']}');
    final correo = TextEditingController(text: '${c['email']}');
    final telefono = TextEditingController(text: '${c['telefono'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Editar contador"),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nombre, decoration: const InputDecoration(labelText: "Nombre")),
            TextField(controller: correo, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "Correo")),
            TextField(controller: telefono, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Teléfono")),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    );
    if (ok == true) {
      await _guardar({'nombre': nombre.text.trim(), 'email': correo.text.trim(), 'telefono': telefono.text.trim()}, "Datos guardados.");
    }
  }

  Future<void> _cambiarDespacho() async {
    final elegido = await showDialog<(bool, int?)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("¿Dónde trabaja este contador?"),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, (true, null)),
            child: const ListTile(leading: Icon(Icons.person_outline), title: Text("Independiente (sin despacho)")),
          ),
          for (final d in widget.despachos)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (true, d['id'] as int)),
              child: ListTile(leading: const Icon(Icons.account_balance_outlined), title: Text('${d['nombre']}')),
            ),
        ],
      ),
    );
    if (elegido == null) return;
    await _guardar({'despacho': elegido.$2}, elegido.$2 == null ? "Quedó como independiente." : "Pasó al despacho.");
  }

  Future<void> _restablecerClave() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Restablecer la contraseña?"),
        content: Text("Se genera una contraseña temporal para @${c['usuario']}. La contraseña actual deja de servir."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Restablecer")),
        ],
      ),
    );
    if (seguro != true) return;
    setState(() => _trabajando = true);
    try {
      final r = ApiService.verificar(await ApiService.post('${_base}clave/', {}));
      final datos = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Contraseña temporal"),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Usuario: ${datos['usuario']}"),
            const SizedBox(height: 8),
            SelectableText('${datos['clave_temporal']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text("Pasásela al contador; se muestra una sola vez.", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ]),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: "Usuario: ${datos['usuario']}\nContraseña: ${datos['clave_temporal']}")),
              child: const Text("Copiar"),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("Listo")),
          ],
        ),
      );
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _alternarAcceso() async {
    final activar = c['activo'] != true;
    setState(() => _trabajando = true);
    try {
      final r = ApiService.verificar(await ApiService.post('${_base}acceso/', {'activo': activar}));
      final nuevo = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      setState(() => c = nuevo);
      widget.alCambiar(nuevo);
      _aviso(activar ? "Acceso activado." : "Acceso desactivado: ya no puede entrar.");
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Widget _dato(IconData icono, String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icono, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(etiqueta, style: TextStyle(color: AppColors.textMuted))),
          Expanded(child: SelectableText(valor.isEmpty ? '—' : valor, style: TextStyle(color: AppColors.textStrong))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final negocios = (c['negocios'] as List).cast<Map>();
    final tieneUsuario = c['usuario'] != null;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text('${c['nombre']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          if (_trabajando) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          const SizedBox(height: 10),
          _dato(Icons.alternate_email, "Usuario", tieneUsuario ? '${c['usuario']}' : 'Sin usuario'),
          _dato(Icons.email_outlined, "Correo", '${c['email']}'),
          _dato(Icons.phone_outlined, "Teléfono", '${c['telefono'] ?? ''}'),
          _dato(Icons.account_balance_outlined, "Despacho", c['despacho'] == null ? 'Independiente' : '${c['despacho_nombre']}'),
          _dato(Icons.workspace_premium_outlined, "Plan", '${c['plan_nombre'] ?? ''}'),
          _dato(Icons.login, "Último ingreso", c['ultimo_ingreso'] == null ? 'Nunca ha entrado' : _fecha(c['ultimo_ingreso'])),
          _dato(Icons.event_outlined, "Creado", _fecha(c['creado'])),
          _dato(Icons.lock_outline, "Acceso", c['activo'] == true ? 'Activo' : 'Desactivado'),
          const SizedBox(height: 12),
          Text("Negocios a cargo (${negocios.length})", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          const SizedBox(height: 4),
          if (negocios.isEmpty) Text("Ninguno todavía.", style: TextStyle(color: AppColors.textMuted)),
          for (final n in negocios)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined, size: 20),
              title: Text('${n['nombre']}', style: TextStyle(color: AppColors.textStrong)),
              subtitle: Text('${n['cedula']}', style: TextStyle(color: AppColors.textMuted)),
            ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _trabajando ? null : _editar, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text("Editar datos")),
            OutlinedButton.icon(
                onPressed: _trabajando ? null : _cambiarDespacho, icon: const Icon(Icons.swap_horiz, size: 18), label: const Text("Cambiar despacho")),
            if (tieneUsuario)
              OutlinedButton.icon(
                  onPressed: _trabajando ? null : _restablecerClave, icon: const Icon(Icons.key_outlined, size: 18), label: const Text("Restablecer contraseña")),
            if (tieneUsuario)
              OutlinedButton.icon(
                onPressed: _trabajando ? null : _alternarAcceso,
                icon: Icon(c['activo'] == true ? Icons.block : Icons.check_circle_outline, size: 18),
                label: Text(c['activo'] == true ? "Desactivar acceso" : "Activar acceso"),
                style: OutlinedButton.styleFrom(foregroundColor: c['activo'] == true ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
              ),
          ]),
        ]),
      ),
    );
  }
}
