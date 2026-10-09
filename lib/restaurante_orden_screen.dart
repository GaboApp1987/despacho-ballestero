import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api_service.dart';
import 'formato.dart';
import 'formulario_factura.dart';
import 'negocio.dart';
import 'producto.dart';
import 'theme/app_theme.dart';

/// Cuenta de una mesa (o pedido para llevar): menú a un lado y la orden al
/// otro en tablet; en celular la orden ocupa la pantalla y el menú se abre
/// con "Agregar platos". Lo nuevo queda "por enviar" hasta tocar "Enviar a
/// cocina"; "Cobrar" abre el tiquete con todo lo pedido.
class RestauranteOrdenScreen extends StatefulWidget {
  final Negocio negocio;
  final int ordenId;
  const RestauranteOrdenScreen({super.key, required this.negocio, required this.ordenId});

  @override
  State<RestauranteOrdenScreen> createState() => _RestauranteOrdenScreenState();
}

class _Borrador {
  final Producto producto;
  int cantidad;
  String nota;
  _Borrador(this.producto, {this.nota = ''}) : cantidad = 1;
}

const _estados = {
  'en_cocina': ('En cocina', Color(0xFF3B82F6)),
  'listo': ('Listo', Color(0xFF16A34A)),
  'entregado': ('Entregado', Color(0xFF94A3B8)),
  'anulado': ('Anulado', Color(0xFFDC2626)),
};

double _conIva(Producto p, double precio) => precio * (1 + (p.impuesto?.porcentaje ?? 0) / 100);

class _RestauranteOrdenScreenState extends State<RestauranteOrdenScreen> {
  Map<String, dynamic>? _orden;
  List<Producto> _productos = [];
  final List<_Borrador> _nuevos = [];
  String _busqueda = '';
  int? _categoria;
  bool _enviando = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _cargarOrden());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _cargarTodo() async {
    try {
      final r = await ApiService.get('/productos/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200) {
        _productos = (json.decode(utf8.decode(r.bodyBytes)) as List).map((j) => Producto.fromJson(j)).toList()
          ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      }
    } catch (_) {}
    await _cargarOrden();
  }

  Future<void> _cargarOrden() async {
    try {
      final r = await ApiService.get('/restaurante/ordenes/${widget.ordenId}/');
      if (r.statusCode == 200 && mounted) setState(() => _orden = json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
  }

  void _usarRespuesta(dynamic datos) {
    if (datos is Map<String, dynamic> && mounted) setState(() => _orden = datos);
  }

  String get _titulo {
    final o = _orden;
    if (o == null) return "Orden";
    final donde = o['mesa_nombre'] ?? ((o['nombre'] ?? '').toString().isNotEmpty ? "Llevar · ${o['nombre']}" : "Para llevar");
    return "$donde · #${o['numero']}";
  }

  List<Map<String, dynamic>> get _items => ((_orden?['items'] as List?) ?? []).cast<Map<String, dynamic>>();

  double get _totalNuevos => _nuevos.fold(0.0, (s, b) => s + _conIva(b.producto, b.producto.precioUnitario) * b.cantidad);

  // ---------------------------------------------------------- Borrador

  void _agregar(Producto p, {String nota = ''}) {
    setState(() {
      final igual = _nuevos.where((b) => b.producto.id == p.id && b.nota == nota).firstOrNull;
      if (igual != null) {
        igual.cantidad++;
      } else {
        _nuevos.add(_Borrador(p, nota: nota));
      }
    });
  }

  Future<String?> _pedirNota(String titulo, {String inicial = ''}) {
    final ctrl = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(hintText: "Ej: sin cebolla, término medio", border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in ["Sin cebolla", "Sin hielo", "Término medio", "Bien cocido", "Para llevar", "Aparte"])
              ActionChip(label: Text(s), onPressed: () {
                final actual = ctrl.text.trim();
                ctrl.text = actual.isEmpty ? s.toLowerCase() : "$actual, ${s.toLowerCase()}";
              }),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Listo")),
        ],
      ),
    );
  }

  Future<void> _agregarConNota(Producto p) async {
    final nota = await _pedirNota(p.nombre);
    if (nota != null) _agregar(p, nota: nota);
  }

  // ---------------------------------------------------------- Acciones

  Future<bool> _subirNuevos() async {
    if (_nuevos.isEmpty) return true;
    final r = await ApiService.post('/restaurante/ordenes/${widget.ordenId}/agregar/', {
      'items': [for (final b in _nuevos) {'producto': b.producto.id, 'cantidad': b.cantidad, 'nota': b.nota}],
    });
    if (r.statusCode != 201) {
      _aviso("No se pudieron agregar: ${ApiService.mensajeError(r)}");
      return false;
    }
    _nuevos.clear();
    _usarRespuesta(json.decode(utf8.decode(r.bodyBytes)));
    return true;
  }

  Future<void> _enviarCocina() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      if (await _subirNuevos()) {
        final r = await ApiService.post('/restaurante/ordenes/${widget.ordenId}/enviar/', {});
        final datos = json.decode(utf8.decode(r.bodyBytes));
        if (r.statusCode == 200) {
          _usarRespuesta(datos['orden']);
          _aviso("Enviado a cocina.");
          if (datos['imprimir'] == true) await imprimirComanda(Map<String, dynamic>.from(datos['comanda']), widget.negocio.nombreComercial);
        } else {
          _aviso(ApiService.mensajeError(r));
        }
      }
    } catch (e) {
      _aviso("No se pudo enviar: $e");
    }
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _accionItem(Map<String, dynamic> item, Map<String, dynamic> datos) async {
    final r = await ApiService.post('/restaurante/ordenes/${widget.ordenId}/items/${item['id']}/', datos);
    if (r.statusCode == 200) {
      _usarRespuesta(json.decode(utf8.decode(r.bodyBytes)));
    } else {
      _aviso(ApiService.mensajeError(r));
    }
  }

  Future<void> _anularItem(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Anular plato"),
        content: Text("¿Anular ${item['cantidad']} × ${item['nombre']}? La cocina va a ver que se anuló."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No")),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("Anular")),
        ],
      ),
    );
    if (ok == true) _accionItem(item, {'estado': 'anulado'});
  }

  Future<void> _patchOrden(Map<String, dynamic> datos) async {
    final r = await ApiService.patch('/restaurante/ordenes/${widget.ordenId}/', datos);
    if (r.statusCode == 200) {
      _usarRespuesta(json.decode(utf8.decode(r.bodyBytes)));
    } else {
      _aviso(ApiService.mensajeError(r));
    }
  }

  Future<void> _moverMesa() async {
    final r = await ApiService.get('/restaurante/salon/?negocio=${widget.negocio.id}');
    if (r.statusCode != 200 || !mounted) return;
    final libres = (json.decode(utf8.decode(r.bodyBytes))['mesas'] as List).cast<Map<String, dynamic>>().where((m) => m['orden'] == null).toList();
    if (libres.isEmpty) {
      _aviso("No hay mesas libres.");
      return;
    }
    final mesa = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text("Mover a…", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textStrong)),
          ),
          for (final m in libres)
            ListTile(
              leading: const Icon(Icons.table_restaurant_outlined),
              title: Text(m['nombre'], style: TextStyle(color: AppColors.textStrong)),
              subtitle: (m['zona'] ?? '').toString().isEmpty ? null : Text(m['zona']),
              onTap: () => Navigator.pop(ctx, m['id'] as int),
            ),
        ]),
      ),
    );
    if (mesa != null) _patchOrden({'mesa': mesa});
  }

  Future<void> _anularCuenta() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Anular la cuenta"),
        content: const Text("Se cierra sin cobrar y la mesa queda libre."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No")),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("Anular")),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ApiService.post('/restaurante/ordenes/${widget.ordenId}/anular/', {});
    if (!mounted) return;
    if (r.statusCode == 200) {
      Navigator.pop(context);
    } else {
      _aviso(ApiService.mensajeError(r));
    }
  }

  Future<void> _cobrar() async {
    if (_nuevos.isNotEmpty) {
      final agregar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Hay platos sin enviar"),
          content: const Text("¿Los agrego a la cuenta antes de cobrar?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Descartarlos")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Agregarlos")),
          ],
        ),
      );
      if (agregar == null) return;
      if (agregar) {
        if (!await _subirNuevos()) return;
      } else {
        setState(_nuevos.clear);
      }
    }
    // Mismo producto y precio = una sola línea en el tiquete.
    final lineas = <String, ({int productoId, int cantidad, double precio})>{};
    for (final i in _items) {
      if (i['estado'] == 'anulado' || i['producto'] == null) continue;
      final precio = double.tryParse('${i['precio_unitario']}') ?? 0;
      final clave = "${i['producto']}|$precio";
      final previa = lineas[clave];
      lineas[clave] = (productoId: i['producto'] as int, cantidad: (previa?.cantidad ?? 0) + (i['cantidad'] as int), precio: precio);
    }
    if (lineas.isEmpty) {
      _aviso("La cuenta no tiene platos.");
      return;
    }
    if (!mounted) return;
    final cobrado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FormularioFactura(
          negocio: widget.negocio,
          lineasIniciales: lineas.values.toList(),
          camposExtra: {'orden_restaurante': widget.ordenId},
        ),
      ),
    );
    if (cobrado == true && mounted) {
      _aviso("Cuenta cobrada. La mesa quedó libre.");
      Navigator.pop(context);
    }
  }

  Future<bool> _confirmarSalida() async {
    if (_nuevos.isEmpty) return true;
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Platos sin enviar"),
        content: Text("Tenés ${_nuevos.length} ${_nuevos.length == 1 ? 'plato' : 'platos'} sin enviar a cocina."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Salir sin enviar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Quedarme")),
        ],
      ),
    );
    return salir == true;
  }

  // ---------------------------------------------------------- Menú

  Widget _menu({required bool compacto, VoidCallback? alCambiar}) {
    final categorias = <int, String>{};
    for (final p in _productos) {
      if (p.categoriaId != null) categorias[p.categoriaId!] = p.nombreCategoria ?? 'Categoría';
    }
    final b = _busqueda.toLowerCase();
    final lista = _productos.where((p) => (_categoria == null || p.categoriaId == _categoria) && (b.isEmpty || p.nombre.toLowerCase().contains(b))).toList();
    return StatefulBuilder(builder: (context, setLocal) {
      void refrescar(VoidCallback f) {
        setState(f);
        setLocal(() {});
        alCambiar?.call();
      }

      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              hintText: "Buscar plato o bebida...",
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            ),
            onChanged: (v) => refrescar(() => _busqueda = v.trim()),
          ),
        ),
        if (categorias.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: const Text("Todo"), selected: _categoria == null, onSelected: (_) => refrescar(() => _categoria = null)),
                ),
                for (final c in categorias.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(c.value), selected: _categoria == c.key, onSelected: (_) => refrescar(() => _categoria = c.key)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: lista.isEmpty
              ? Center(child: Text("No hay productos.", style: TextStyle(color: AppColors.textMuted)))
              : GridView.extent(
                  maxCrossAxisExtent: compacto ? 170 : 190,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.45,
                  children: [
                    for (final p in lista)
                      Builder(builder: (_) {
                        final pedidos = _nuevos.where((x) => x.producto.id == p.id).fold(0, (s, x) => s + x.cantidad);
                        return Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => refrescar(() => _agregar(p)),
                            onLongPress: () async {
                              await _agregarConNota(p);
                              setLocal(() {});
                              alCambiar?.call();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: pedidos > 0 ? AppColors.primary : AppColors.border, width: pedidos > 0 ? 2 : 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(p.nombre, maxLines: 3, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong, fontSize: 13.5)),
                                  ),
                                  Row(children: [
                                    Expanded(
                                      child: Text(formatearColones(_conIva(p, p.precioUnitario), decimales: 0),
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                                    ),
                                    if (pedidos > 0)
                                      CircleAvatar(
                                        radius: 11,
                                        backgroundColor: AppColors.primary,
                                        child: Text("$pedidos", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                                      ),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text("Tocá para agregar · mantené presionado para agregar con nota",
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
        ),
      ]);
    });
  }

  Future<void> _abrirMenuCelular() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceSubtle,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.9,
          child: Column(children: [
            Expanded(child: _menu(compacto: true, alCambiar: () => setSheet(() {}))),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(_nuevos.isEmpty ? "Cerrar" : "Listo · ${_nuevos.fold(0, (s, b) => s + b.cantidad)} por enviar"),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    setState(() {});
  }

  // ---------------------------------------------------------- Orden

  Widget _filaBorrador(_Borrador b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.producto.nombre, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
            InkWell(
              onTap: () async {
                final nota = await _pedirNota(b.producto.nombre, inicial: b.nota);
                if (nota != null) setState(() => b.nota = nota);
              },
              child: Text(b.nota.isEmpty ? "+ nota" : "→ ${b.nota}",
                  style: TextStyle(color: b.nota.isEmpty ? AppColors.primary : const Color(0xFFB45309), fontSize: 12.5)),
            ),
          ]),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(b.cantidad == 1 ? Icons.delete_outline : Icons.remove),
          onPressed: () => setState(() => b.cantidad == 1 ? _nuevos.remove(b) : b.cantidad--),
        ),
        Text("${b.cantidad}", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add), onPressed: () => setState(() => b.cantidad++)),
      ]),
    );
  }

  Widget _filaItem(Map<String, dynamic> i) {
    final (texto, color) = _estados[i['estado']] ?? ('Sin enviar', AppColors.textMuted);
    final anulado = i['estado'] == 'anulado';
    final precio = double.tryParse('${i['precio_unitario']}') ?? 0;
    final iva = (i['producto_iva'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 28,
          child: Text("${i['cantidad']}×", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i['nombre'],
                style: TextStyle(
                  color: anulado ? AppColors.textMuted : AppColors.textStrong,
                  decoration: anulado ? TextDecoration.lineThrough : null,
                  fontWeight: FontWeight.w600,
                )),
            if ((i['nota'] ?? '').toString().isNotEmpty)
              Text("→ ${i['nota']}", style: const TextStyle(color: Color(0xFFB45309), fontSize: 12.5)),
            const SizedBox(height: 3),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
                child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              if (i['estado'] == 'listo') ...[
                InkWell(
                  onTap: () => _accionItem(i, {'estado': 'entregado'}),
                  child: Text("Marcar entregado", style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ]),
        ),
        Text(formatearColones(anulado ? 0 : precio * (1 + iva / 100) * (i['cantidad'] as int), decimales: 0),
            style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600)),
        if (!anulado && i['estado'] != 'entregado')
          SizedBox(
            width: 32,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
              onSelected: (v) => v == 'anular' ? _anularItem(i) : _accionItem(i, {'estado': 'entregado'}),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'entregado', child: Text("Marcar entregado")),
                PopupMenuItem(value: 'anular', child: Text("Anular")),
              ],
            ),
          )
        else
          const SizedBox(width: 32),
      ]),
    );
  }

  Widget _panelOrden({required bool celular}) {
    final o = _orden!;
    final porRonda = <int, List<Map<String, dynamic>>>{};
    for (final i in _items) {
      porRonda.putIfAbsent(i['ronda'] as int? ?? 0, () => []).add(i);
    }
    final rondas = porRonda.keys.toList()..sort((a, b) => b.compareTo(a));
    final total = ((o['total'] as num?)?.toDouble() ?? 0) + _totalNuevos;
    final porEnviar = _nuevos.fold(0, (s, b) => s + b.cantidad);
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          children: [
            Row(children: [
              Icon(Icons.people_outline, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 4),
              DropdownButton<int>(
                value: (o['personas'] as int? ?? 1).clamp(1, 30),
                underline: const SizedBox.shrink(),
                isDense: true,
                items: [for (var n = 1; n <= 30; n++) DropdownMenuItem(value: n, child: Text("$n"))],
                onChanged: (n) => n == null ? null : _patchOrden({'personas': n}),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text("${o['mesero_nombre'] ?? ''}", maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ),
              if (o['cuenta_pedida'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Text("Pidió la cuenta", style: TextStyle(color: Color(0xFFB45309), fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
            ]),
            if (_nuevos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text("POR ENVIAR", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: AppColors.primary)),
              const SizedBox(height: 6),
              for (final b in _nuevos) _filaBorrador(b),
            ],
            if (_items.isEmpty && _nuevos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  Icon(Icons.restaurant_menu, size: 44, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  Text(celular ? "Tocá \"Agregar platos\" para empezar." : "Escogé los platos del menú.",
                      style: TextStyle(color: AppColors.textMuted)),
                ]),
              ),
            for (final r in rondas) ...[
              const SizedBox(height: 12),
              Text(r == 0 ? "SIN ENVIAR" : "RONDA $r",
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: AppColors.textMuted)),
              const Divider(height: 10),
              for (final i in porRonda[r]!) _filaItem(i),
            ],
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text("Total", style: TextStyle(color: AppColors.textMuted)),
              const Spacer(),
              Text(formatearColones(total, decimales: 0), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            ]),
            const SizedBox(height: 10),
            if (celular) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(onPressed: _abrirMenuCelular, icon: const Icon(Icons.add), label: const Text("Agregar platos")),
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: porEnviar == 0 || _enviando ? null : _enviarCocina,
                  icon: _enviando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 18),
                  label: Text(porEnviar == 0 ? "Enviar a cocina" : "Enviar ($porEnviar)"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                  onPressed: _items.isEmpty && _nuevos.isEmpty ? null : _cobrar,
                  icon: const Icon(Icons.point_of_sale, size: 18),
                  label: const Text("Cobrar"),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _nuevos.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navegador = Navigator.of(context);
        if (await _confirmarSalida() && mounted) {
          setState(_nuevos.clear);
          navegador.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceSubtle,
        appBar: AppBar(
          title: Text(_titulo),
          actions: [
            if (_orden != null)
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'cuenta': _patchOrden({'cuenta_pedida': !(_orden!['cuenta_pedida'] == true)});
                    case 'mover': _moverMesa();
                    case 'anular': _anularCuenta();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'cuenta', child: Text(_orden!['cuenta_pedida'] == true ? "Quitar \"pidió la cuenta\"" : "Pidió la cuenta")),
                  const PopupMenuItem(value: 'mover', child: Text("Mover de mesa")),
                  const PopupMenuItem(value: 'anular', child: Text("Anular cuenta")),
                ],
              ),
          ],
        ),
        body: _orden == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (context, c) {
                if (c.maxWidth >= 840) {
                  return Row(children: [
                    Expanded(child: _menu(compacto: false)),
                    VerticalDivider(width: 1, color: AppColors.border),
                    SizedBox(width: c.maxWidth >= 1200 ? 440 : 380, child: Container(color: AppColors.surface, child: _panelOrden(celular: false))),
                  ]);
                }
                return _panelOrden(celular: true);
              }),
      ),
    );
  }
}

/// Comanda para la impresora de tickets (80 mm): grande y sin precios.
Future<void> imprimirComanda(Map<String, dynamic> c, String negocio) async {
  final doc = pw.Document();
  final donde = (c['mesa'] ?? '').toString().isNotEmpty ? c['mesa'] : "PARA LLEVAR ${(c['nombre'] ?? '').toString().toUpperCase()}";
  final items = (c['items'] as List).cast<Map>();
  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(negocio, style: const pw.TextStyle(fontSize: 9)),
        pw.Text("$donde", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text("Orden #${c['numero']} · Ronda ${c['ronda']} · ${c['hora']}", style: const pw.TextStyle(fontSize: 11)),
        if ((c['mesero'] ?? '').toString().isNotEmpty) pw.Text("Mesero: ${c['mesero']}", style: const pw.TextStyle(fontSize: 10)),
        pw.Divider(),
        for (final i in items) ...[
          pw.Text("${i['cantidad']} x ${i['nombre']}", style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if ((i['nota'] ?? '').toString().isNotEmpty) pw.Text("   -> ${i['nota']}", style: pw.TextStyle(fontSize: 13, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 4),
        ],
        pw.Divider(),
      ],
    ),
  ));
  await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'Comanda_${c['numero']}_${c['ronda']}');
}
