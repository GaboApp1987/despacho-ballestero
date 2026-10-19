import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'cliente.dart';
import 'formato.dart';
import 'formulario_factura.dart';
import 'negocio.dart';
import 'prestamos_screen.dart' show abrirNuevoPrestamo;
import 'producto.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Inventario de vehículos (ver gestion/vehiculos.py): cada carro es una
/// unidad con su VIN, motor y placa; la cantidad de un modelo es cuántas
/// unidades de ese modelo hay. La venta sale con factura electrónica (con
/// accesorios o servicios en la misma factura) y, si es a plazo, con préstamo.
class VehiculosScreen extends StatefulWidget {
  final Negocio negocio;
  const VehiculosScreen({super.key, required this.negocio});

  @override
  State<VehiculosScreen> createState() => _VehiculosScreenState();
}

double _n(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

String _dinero(dynamic v, String moneda) =>
    moneda == 'USD' ? formatearDolares(_n(v), decimales: 0) : formatearColones(_n(v), decimales: 0);

String _fecha(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
  return "${d.day} ${meses[d.month - 1]} ${d.year}";
}

const _verde = Color(0xFF16A34A);
const _ambar = Color(0xFFD97706);
const _rojo = Color(0xFFDC2626);
const _azul = Color(0xFF2563EB);

const _estados = {
  'disponible': ('Disponible', _verde),
  'reservado': ('Reservado', _ambar),
  'taller': ('En preparación', _azul),
  'vendido': ('Vendido', Color(0xFF64748B)),
};
const _combustibles = {'gasolina': 'Gasolina', 'diesel': 'Diésel', 'hibrido': 'Híbrido', 'electrico': 'Eléctrico', 'gas': 'Gas LPG', 'otro': 'Otro'};
const _transmisiones = {'manual': 'Manual', 'automatica': 'Automática', 'cvt': 'CVT'};
const _carrocerias = ['Sedán', 'Hatchback', 'SUV', 'Pick-up', 'Microbús', 'Camión', 'Coupé', 'Moto', 'Cuadraciclo'];

String _titulo(Map v) => [v['marca'], v['modelo'], v['version'], v['anio']].where((x) => '${x ?? ''}'.isNotEmpty).join(' ');

Widget _chipEstado(String estado) {
  final e = _estados[estado] ?? (estado, AppColors.textMuted);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: e.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
    child: Text(e.$1, style: TextStyle(color: e.$2, fontWeight: FontWeight.w700, fontSize: 11.5)),
  );
}

Future<List<Cliente>> _cargarClientes(Negocio negocio) async {
  final r = ApiService.verificar(await ApiService.get('/clientes/?negocio=${negocio.id}'));
  return (json.decode(utf8.decode(r.bodyBytes)) as List).map((j) => Cliente.fromJson(j)).toList()
    ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
}

Future<List<Producto>> _cargarProductos(Negocio negocio) async {
  final r = ApiService.verificar(await ApiService.get('/productos/?negocio=${negocio.id}'));
  return (json.decode(utf8.decode(r.bodyBytes)) as List).map((j) => Producto.fromJson(j)).toList()
    ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
}

class _VehiculosScreenState extends State<VehiculosScreen> {
  bool _cargando = true;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _lista = [];
  String _estado = 'disponible,reservado,taller';
  String _busqueda = '';
  final _busquedaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final rs = await Future.wait([
        ApiService.get('/vehiculos-resumen/?negocio=${widget.negocio.id}'),
        ApiService.get('/vehiculos/?negocio=${widget.negocio.id}${_estado.isEmpty ? '' : '&estado=$_estado'}'),
      ]);
      _resumen = json.decode(utf8.decode(ApiService.verificar(rs[0]).bodyBytes)) as Map<String, dynamic>;
      _lista = (json.decode(utf8.decode(ApiService.verificar(rs[1]).bodyBytes)) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _nuevo() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _FormVehiculo(negocio: widget.negocio)));
    if (ok == true) _cargar();
  }

  Future<void> _abrir(int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _DetalleVehiculo(negocio: widget.negocio, vehiculoId: id)));
    _cargar();
  }

  Future<void> _ajustes() async {
    List<Producto> productos;
    try {
      productos = await _cargarProductos(widget.negocio);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
      return;
    }
    if (!mounted) return;
    int? elegido = _resumen['producto_defecto'] as int?;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Con qué se facturan los carros"),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                "Elegí el producto del inventario con el CABYS e IVA de vehículos (por ejemplo uno llamado \"Vehículo\"). "
                "En la factura, la línea lleva la marca, el modelo, el VIN, el motor y la placa de cada carro. "
                "Si todavía no existe, crealo en Inventario.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: productos.any((p) => p.id == elegido) ? elegido : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Producto para facturar", border: OutlineInputBorder()),
                items: [for (final p in productos) DropdownMenuItem(value: p.id, child: Text("${p.nombre} · CABYS ${p.codigoCabys}", overflow: TextOverflow.ellipsis))],
                onChanged: (v) => set(() => elegido = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: elegido == null ? null : () => Navigator.pop(ctx, true), child: const Text("Guardar")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.patch('/vehiculos-config/?negocio=${widget.negocio.id}', {'producto': elegido}));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  double _anchoTarjeta = 190;

  Widget _tarjeta(String titulo, String valor, IconData icono, Color color, {String? pie}) => Container(
        width: _anchoTarjeta,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icono, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(titulo, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
          ]),
          const SizedBox(height: 6),
          Text(valor, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          if (pie != null) Text(pie, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final porEstado = ((_resumen['por_estado'] as Map?) ?? {}).cast<String, dynamic>();
    final modelos = ((_resumen['modelos'] as List?) ?? []).cast<Map>();
    final valor = ((_resumen['valor_inventario'] as Map?) ?? {}).cast<String, dynamic>();
    final ventas = ((_resumen['ventas_mes'] as Map?) ?? {}).cast<String, dynamic>();
    // En un teléfono, dos tarjetas por renglón.
    final ancho = MediaQuery.sizeOf(context).width - 32;
    _anchoTarjeta = ancho < 420 ? (ancho - 10) / 2 : 190;
    final b = _busqueda.toLowerCase();
    final lista = _lista
        .where((v) => b.isEmpty ||
            '${_titulo(v)} ${v['color'] ?? ''} ${v['placa'] ?? ''} ${v['vin'] ?? ''} ${v['numero_motor'] ?? ''}'.toLowerCase().contains(b))
        .toList();
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      floatingActionButton: FloatingActionButton.extended(onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text("Agregar vehículo")),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Row(children: [
                    Icon(Icons.directions_car_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text("Vehículos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                    IconButton(onPressed: _ajustes, icon: const Icon(Icons.tune), tooltip: "Con qué se facturan"),
                    IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh), tooltip: "Actualizar"),
                  ]),
                  const SizedBox(height: 8),
                  if (_resumen['producto_defecto'] == null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
                      decoration: BoxDecoration(color: _ambar.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.info_outline, color: _ambar),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text("Falta elegir con qué producto se facturan los carros",
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text("El del inventario con el CABYS e IVA de vehículos. Sin eso no se puede vender desde aquí.",
                            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _ajustes, child: const Text("Elegir producto"))),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    _tarjeta("Disponibles", "${porEstado['disponible'] ?? 0}", Icons.check_circle_outline, _verde,
                        pie: "${porEstado['reservado'] ?? 0} reservados · ${porEstado['taller'] ?? 0} en preparación"),
                    for (final e in valor.entries)
                      _tarjeta("Inventario${valor.length > 1 ? (e.key == 'USD' ? ' (US\$)' : ' (₡)') : ''}", _dinero((e.value as Map)['precio'], e.key),
                          Icons.inventory_2_outlined, AppColors.primary,
                          pie: "Costo ${_dinero((e.value as Map)['costo'], e.key)} · ${(e.value as Map)['unidades']} unidades"),
                    if (ventas.isEmpty)
                      _tarjeta("Vendidos este mes", "0", Icons.sell_outlined, _verde)
                    else
                      for (final e in ventas.entries)
                        _tarjeta("Vendidos este mes", "${(e.value as Map)['unidades']}", Icons.sell_outlined, _verde,
                            pie: "Utilidad ${_dinero((e.value as Map)['utilidad'], e.key)}"),
                    _tarjeta("Días en inventario", "${_resumen['dias_promedio'] ?? 0}", Icons.schedule, (_resumen['mas_de_90_dias'] ?? 0) > 0 ? _ambar : _verde,
                        pie: (_resumen['mas_de_90_dias'] ?? 0) > 0 ? "${_resumen['mas_de_90_dias']} con más de 90 días" : "promedio"),
                    if ((_resumen['rtv_por_vencer'] ?? 0) > 0)
                      _tarjeta("RTV por vencer", "${_resumen['rtv_por_vencer']}", Icons.fact_check_outlined, _rojo, pie: "vencida o en 30 días"),
                  ]),
                  if (modelos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text("Cantidad por modelo", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final m in modelos)
                        ActionChip(
                          avatar: CircleAvatar(
                            backgroundColor: AppColors.primary,
                            child: Text("${m['disponibles']}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                          label: Text("${m['marca']} ${m['modelo']} ${m['anio']}"
                              "${(m['reservados'] ?? 0) + (m['taller'] ?? 0) > 0 ? ' (+${(m['reservados'] ?? 0) + (m['taller'] ?? 0)})' : ''}"),
                          tooltip: "${m['disponibles']} disponibles, ${m['reservados']} reservados, ${m['taller']} en preparación"
                              "${m['precio_desde'] != null ? ' · desde ${_dinero(m['precio_desde'], '${m['moneda']}')}' : ''}",
                          onPressed: () {
                            _busquedaCtrl.text = "${m['modelo']} ${m['anio']}";
                            setState(() => _busqueda = _busquedaCtrl.text);
                          },
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Text("Unidades", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong))),
                    DropdownButton<String>(
                      value: _estado,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'disponible,reservado,taller', child: Text("En inventario")),
                        DropdownMenuItem(value: 'disponible', child: Text("Disponibles")),
                        DropdownMenuItem(value: 'reservado', child: Text("Reservados")),
                        DropdownMenuItem(value: 'taller', child: Text("En preparación")),
                        DropdownMenuItem(value: 'vendido', child: Text("Vendidos")),
                        DropdownMenuItem(value: '', child: Text("Todos")),
                      ],
                      onChanged: (v) {
                        setState(() => _estado = v ?? '');
                        _cargar();
                      },
                    ),
                  ]),
                  TextField(
                    controller: _busquedaCtrl,
                    decoration: InputDecoration(
                      hintText: "Buscar por marca, modelo, placa, VIN o motor...",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _busqueda.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _busquedaCtrl.clear();
                                setState(() => _busqueda = '');
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                    ),
                    onChanged: (v) => setState(() => _busqueda = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  if (lista.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_lista.isEmpty && _estado.contains('disponible') ? "Todavía no hay vehículos. Agregá el primero." : "Nada por aquí.",
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                    ),
                  for (final v in lista) _fila(v),
                ],
              ),
            ),
    );
  }

  Widget _fila(Map<String, dynamic> v) {
    final moneda = '${v['moneda']}';
    final vin = '${v['vin'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrir(v['id'] as int),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 72,
                height: 54,
                child: v['foto'] != null
                    ? Image.network('${v['foto']}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => _sinFoto())
                    : _sinFoto(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_titulo(v), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                Text(
                  [
                    if ('${v['color'] ?? ''}'.isNotEmpty) v['color'],
                    if ('${v['placa'] ?? ''}'.isNotEmpty) "Placa ${v['placa']}",
                    if (vin.isNotEmpty) "VIN …${vin.length > 6 ? vin.substring(vin.length - 6) : vin}",
                    if (v['kilometraje'] != null) "${formatearNumero(_n(v['kilometraje']))} km",
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _chipEstado('${v['estado']}'),
                  if (v['estado'] == 'reservado' && v['cliente_nombre'] != null)
                    Text("${v['cliente_nombre']}", style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  if (v['rtv_vencida'] == true) const Text("RTV vencida", style: TextStyle(fontSize: 11.5, color: _rojo, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_dinero(v['estado'] == 'vendido' ? (v['precio_vendido'] ?? v['precio_venta']) : v['precio_venta'], moneda),
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              Text(v['condicion'] == 'nuevo' ? "Nuevo" : "Usado", style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

Widget _sinFoto() => Container(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Icon(Icons.directions_car_filled_outlined, color: AppColors.primary),
    );

// --------------------------------------------------------------------- Formulario

class _FormVehiculo extends StatefulWidget {
  final Negocio negocio;
  final Map<String, dynamic>? vehiculo;
  const _FormVehiculo({required this.negocio, this.vehiculo});

  @override
  State<_FormVehiculo> createState() => _FormVehiculoState();
}

class _FormVehiculoState extends State<_FormVehiculo> {
  static const _campos = [
    'marca', 'modelo', 'version', 'anio', 'color', 'vin', 'numero_motor', 'placa', 'carroceria', 'traccion', 'cilindrada',
    'kilometraje', 'pasajeros', 'extras', 'dua', 'costo', 'otros_costos', 'precio_venta', 'precio_minimo', 'proveedor',
    'ubicacion', 'notas',
  ];
  final Map<String, TextEditingController> _c = {for (final k in _campos) k: TextEditingController()};
  String _condicion = 'usado';
  String _moneda = 'CRC';
  String? _combustible;
  String? _transmision;
  bool _marchamo = false;
  DateTime? _rtv;
  DateTime _ingreso = DateTime.now();
  int? _producto;
  List<Producto> _productos = [];
  XFile? _foto;
  bool _guardando = false;

  bool get _editando => widget.vehiculo != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehiculo;
    if (v != null) {
      for (final k in _campos) {
        final x = v[k];
        _c[k]!.text = x == null ? '' : (x is num || double.tryParse('$x') != null) && ['costo', 'otros_costos', 'precio_venta', 'precio_minimo'].contains(k)
            ? _n(x).toStringAsFixed(_n(x) == _n(x).roundToDouble() ? 0 : 2)
            : '$x';
      }
      _condicion = '${v['condicion'] ?? 'usado'}';
      _moneda = '${v['moneda'] ?? 'CRC'}';
      _combustible = (v['combustible'] ?? '') == '' ? null : '${v['combustible']}';
      _transmision = (v['transmision'] ?? '') == '' ? null : '${v['transmision']}';
      _marchamo = v['marchamo_al_dia'] == true;
      _rtv = DateTime.tryParse('${v['rtv_vence'] ?? ''}');
      _ingreso = DateTime.tryParse('${v['fecha_ingreso'] ?? ''}') ?? DateTime.now();
      _producto = v['producto'] as int?;
    }
    for (final k in ['costo', 'otros_costos', 'precio_venta']) {
      _c[k]!.addListener(() => setState(() {}));
    }
    _traerProductos();
  }

  Future<void> _traerProductos() async {
    try {
      final p = await _cargarProductos(widget.negocio);
      if (mounted) setState(() => _productos = p);
    } catch (_) {}
  }

  double _num(String k) => double.tryParse(_c[k]!.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _elegirFoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (f != null) setState(() => _foto = f);
  }

  Future<void> _guardar() async {
    if (_c['marca']!.text.trim().isEmpty || _c['modelo']!.text.trim().isEmpty || int.tryParse(_c['anio']!.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Poné al menos la marca, el modelo y el año.")));
      return;
    }
    setState(() => _guardando = true);
    String t(String k) => _c[k]!.text.trim();
    String? numero(String k) => t(k).isEmpty ? null : t(k).replaceAll(',', '.');
    final datos = <String, dynamic>{
      'negocio': widget.negocio.id,
      'condicion': _condicion,
      'marca': t('marca'),
      'modelo': t('modelo'),
      'version': t('version'),
      'anio': int.parse(t('anio')),
      'color': t('color'),
      'vin': t('vin'),
      'numero_motor': t('numero_motor'),
      'placa': t('placa'),
      'carroceria': t('carroceria'),
      'combustible': _combustible ?? '',
      'transmision': _transmision ?? '',
      'traccion': t('traccion'),
      'cilindrada': int.tryParse(t('cilindrada').replaceAll('.', '')),
      'kilometraje': int.tryParse(t('kilometraje').replaceAll('.', '').replaceAll(',', '')),
      'pasajeros': int.tryParse(t('pasajeros')),
      'extras': t('extras'),
      'dua': t('dua'),
      'rtv_vence': _rtv?.toIso8601String().substring(0, 10),
      'marchamo_al_dia': _marchamo,
      'moneda': _moneda,
      'costo': numero('costo') ?? '0',
      'otros_costos': numero('otros_costos') ?? '0',
      'precio_venta': numero('precio_venta') ?? '0',
      'precio_minimo': numero('precio_minimo'),
      'fecha_ingreso': _ingreso.toIso8601String().substring(0, 10),
      'proveedor': t('proveedor'),
      'ubicacion': t('ubicacion'),
      'notas': t('notas'),
      'producto': _producto,
    };
    try {
      final r = _editando
          ? await ApiService.patch('/vehiculos/${widget.vehiculo!['id']}/', datos)
          : await ApiService.post('/vehiculos/', datos);
      final guardado = json.decode(utf8.decode(ApiService.verificar(r).bodyBytes)) as Map<String, dynamic>;
      if (_foto != null) {
        final bytes = await _foto!.readAsBytes();
        final nombre = _foto!.name.isEmpty ? 'foto.jpg' : _foto!.name;
        final rf = await ApiService.uploadBytes('/vehiculos/${guardado['id']}/', 'foto', bytes, nombre);
        if (rf.statusCode != 200 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Se guardó, pero la foto no: ${ApiService.mensajeError(rf)}")));
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
    if (mounted) setState(() => _guardando = false);
  }

  Widget _campo(String k, String etiqueta, {bool numero = false, bool entero = false, String? ayuda, bool mayus = false, int lineas = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[k],
          maxLines: lineas,
          textCapitalization: mayus ? TextCapitalization.characters : TextCapitalization.sentences,
          keyboardType: numero || entero ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: entero
              ? [FilteringTextInputFormatter.digitsOnly]
              : (numero ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null),
          decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  Widget _dos(Widget a, Widget b) => LayoutBuilder(
        builder: (context, c) => c.maxWidth < 460
            ? Column(children: [a, b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]),
      );

  Widget _seccion(String titulo, List<Widget> hijos) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          const SizedBox(height: 10),
          ...hijos,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final costoTotal = _num('costo') + _num('otros_costos');
    final margen = _num('precio_venta') - costoTotal;
    final prefijo = _moneda == 'USD' ? '\$ ' : '₡ ';
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(
        title: Text(_editando ? "Editar vehículo" : "Agregar vehículo"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        bottom: _guardando ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
        actions: const [BotonCalculadora()],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save_outlined),
            label: Text(_editando ? "Guardar cambios" : "Agregar al inventario"),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _seccion("Identificación", [
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'usado', label: Text("Usado")), ButtonSegment(value: 'nuevo', label: Text("Nuevo"))],
                  selected: {_condicion},
                  onSelectionChanged: (s) => setState(() => _condicion = s.first),
                ),
                const SizedBox(height: 12),
                _dos(_campo('marca', "Marca *"), _campo('modelo', "Modelo *")),
                _dos(_campo('version', "Versión o estilo", ayuda: "LE, SR 4x4, Full extras…"), _campo('anio', "Año *", entero: true)),
                _dos(_campo('color', "Color"), _campo('placa', "Placa", mayus: true)),
                _dos(_campo('vin', "VIN o número de chasis", mayus: true), _campo('numero_motor', "Número de motor", mayus: true)),
                InkWell(
                  onTap: _elegirFoto,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(_foto != null ? Icons.check_circle : Icons.add_a_photo_outlined, color: _foto != null ? _verde : AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _foto != null
                              ? "Foto lista: ${_foto!.name}"
                              : (widget.vehiculo?['foto'] != null ? "Cambiar la foto" : "Agregar una foto (opcional)"),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
              _seccion("Características", [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Autocomplete<String>(
                    initialValue: TextEditingValue(text: _c['carroceria']!.text),
                    optionsBuilder: (t) => _carrocerias.where((x) => x.toLowerCase().contains(t.text.toLowerCase())),
                    onSelected: (x) => _c['carroceria']!.text = x,
                    fieldViewBuilder: (context, ctrl, foco, enviar) => TextField(
                      controller: ctrl,
                      focusNode: foco,
                      onChanged: (x) => _c['carroceria']!.text = x,
                      decoration: const InputDecoration(labelText: "Tipo (sedán, SUV, pick-up…)", border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ),
                _dos(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<String>(
                      initialValue: _combustible,
                      decoration: const InputDecoration(labelText: "Combustible", border: OutlineInputBorder(), isDense: true),
                      items: [for (final e in _combustibles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _combustible = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<String>(
                      initialValue: _transmision,
                      decoration: const InputDecoration(labelText: "Transmisión", border: OutlineInputBorder(), isDense: true),
                      items: [for (final e in _transmisiones.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _transmision = v),
                    ),
                  ),
                ),
                _dos(_campo('traccion', "Tracción", ayuda: "4x2, 4x4, AWD"), _campo('cilindrada', "Cilindrada (cc)", entero: true)),
                _dos(_campo('kilometraje', "Kilometraje", entero: true), _campo('pasajeros', "Pasajeros", entero: true)),
                _campo('extras', "Extras y equipamiento", ayuda: "Cámara, sunroof, cuero, pantalla…", lineas: 2),
              ]),
              _seccion("Documentos", [
                _campo('dua', "DUA o póliza de importación"),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Revisión técnica (RTV) vence"),
                  subtitle: Text(_rtv == null ? "Sin dato" : _fecha(_rtv!.toIso8601String())),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_rtv != null) IconButton(onPressed: () => setState(() => _rtv = null), icon: const Icon(Icons.close)),
                    const Icon(Icons.calendar_today),
                  ]),
                  onTap: () async {
                    final f = await showDatePicker(
                        context: context, initialDate: _rtv ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(DateTime.now().year + 3));
                    if (f != null) setState(() => _rtv = f);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _marchamo,
                  onChanged: (v) => setState(() => _marchamo = v),
                  title: const Text("Marchamo al día"),
                ),
              ]),
              _seccion("Costo y precio", [
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'CRC', label: Text("Colones")), ButtonSegment(value: 'USD', label: Text("Dólares"))],
                  selected: {_moneda},
                  onSelectionChanged: (s) => setState(() => _moneda = s.first),
                ),
                const SizedBox(height: 12),
                _dos(_campoDinero('costo', "Costo de compra", prefijo), _campoDinero('otros_costos', "Otros costos", prefijo, ayuda: "Preparación, traspaso, reparaciones")),
                _dos(_campoDinero('precio_venta', "Precio de venta", prefijo), _campoDinero('precio_minimo', "Precio mínimo (interno)", prefijo)),
                if (_num('precio_venta') > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      "Costo total ${_dinero(costoTotal, _moneda)} · Ganancia ${_dinero(margen, _moneda)}"
                      "${costoTotal > 0 ? ' (${(margen / costoTotal * 100).toStringAsFixed(1)}%)' : ''}",
                      style: TextStyle(fontWeight: FontWeight.w700, color: margen >= 0 ? _verde : _rojo),
                    ),
                  ),
              ]),
              _seccion("Ingreso y facturación", [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Fecha de ingreso"),
                  subtitle: Text(_fecha(_ingreso.toIso8601String())),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final f = await showDatePicker(context: context, initialDate: _ingreso, firstDate: DateTime(2010), lastDate: DateTime.now());
                    if (f != null) setState(() => _ingreso = f);
                  },
                ),
                _dos(_campo('proveedor', "Proveedor o procedencia"), _campo('ubicacion', "Ubicación", ayuda: "Patio, sucursal…")),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<int?>(
                    initialValue: _productos.any((p) => p.id == _producto) ? _producto : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Producto con que se factura",
                      helperText: "Si lo dejás así, se usa el del módulo (botón de ajustes en Vehículos).",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text("El del módulo")),
                      for (final p in _productos) DropdownMenuItem<int?>(value: p.id, child: Text(p.nombre, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _producto = v),
                  ),
                ),
                _campo('notas', "Notas", lineas: 3),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campoDinero(String k, String etiqueta, String prefijo, {String? ayuda}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[k],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, prefixText: prefijo, border: const OutlineInputBorder(), isDense: true),
        ),
      );
}

// --------------------------------------------------------------------- Detalle

class _DetalleVehiculo extends StatefulWidget {
  final Negocio negocio;
  final int vehiculoId;
  const _DetalleVehiculo({required this.negocio, required this.vehiculoId});

  @override
  State<_DetalleVehiculo> createState() => _DetalleVehiculoState();
}

class _DetalleVehiculoState extends State<_DetalleVehiculo> {
  Map<String, dynamic>? _v;
  bool _trabajando = false;

  String get _base => '/vehiculos/${widget.vehiculoId}/';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get(_base));
      if (mounted) setState(() => _v = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } catch (e) {
      if (mounted) _aviso(ApiService.textoError(e));
    }
  }

  Future<void> _cambiarEstado(String estado) async {
    Map<String, dynamic> datos = {'estado': estado};
    if (estado == 'reservado') {
      List<Cliente> clientes;
      try {
        clientes = await _cargarClientes(widget.negocio);
      } catch (e) {
        _aviso(ApiService.textoError(e));
        return;
      }
      if (!mounted) return;
      Cliente? cliente;
      DateTime? hasta;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: const Text("Reservar vehículo"),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Autocomplete<Cliente>(
                  displayStringForOption: (c) => c.nombre,
                  optionsBuilder: (t) => clientes.where((c) => c.nombre.toLowerCase().contains(t.text.toLowerCase())).take(30),
                  onSelected: (c) => set(() => cliente = c),
                  fieldViewBuilder: (context, ctrl, foco, enviar) => TextField(
                    controller: ctrl,
                    focusNode: foco,
                    decoration: const InputDecoration(labelText: "Para qué cliente", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_search)),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Reservado hasta"),
                  subtitle: Text(hasta == null ? "Sin fecha" : _fecha(hasta!.toIso8601String())),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final f = await showDatePicker(
                        context: ctx, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
                    if (f != null) set(() => hasta = f);
                  },
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Reservar")),
            ],
          ),
        ),
      );
      if (ok != true) return;
      datos = {...datos, if (cliente != null) 'cliente': cliente!.id, if (hasta != null) 'reservado_hasta': hasta!.toIso8601String().substring(0, 10)};
    }
    setState(() => _trabajando = true);
    try {
      final r = ApiService.verificar(await ApiService.post('${_base}estado/', datos));
      setState(() => _v = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar este vehículo?"),
        content: Text("${_titulo(_v!)} sale del inventario."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Borrar", style: TextStyle(color: _rojo))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ApiService.delete(_base);
      if (r.statusCode != 204) throw Exception(ApiService.mensajeError(r));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
  }

  Future<void> _editar() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _FormVehiculo(negocio: widget.negocio, vehiculo: _v)));
    if (ok == true) _cargar();
  }

  Future<void> _vender() async {
    final v = _v!;
    if (v['producto_factura'] == null) {
      _aviso("Primero elegí con qué producto se facturan los carros (botón de ajustes en Vehículos).");
      return;
    }
    List<Producto> productos;
    try {
      productos = await _cargarProductos(widget.negocio);
    } catch (e) {
      _aviso(ApiService.textoError(e));
      return;
    }
    if (!mounted) return;
    final venta = await showDialog<_Venta>(
      context: context,
      builder: (_) => _DialogoVenta(vehiculo: v, productos: productos.where((p) => p.id != v['producto_factura']).toList()),
    );
    if (venta == null || !mounted) return;
    final moneda = '${v['moneda']}';
    final vendido = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FormularioFactura(
          negocio: widget.negocio,
          tipoDocumentoInicial: '01',
          monedaLineas: moneda,
          lineasIniciales: [
            (productoId: v['producto_factura'] as int, cantidad: 1, precio: venta.precio, descripcion: '${v['descripcion_factura']}'),
            for (final a in venta.accesorios) (productoId: a.id, cantidad: 1, precio: -1.0, descripcion: ''),
          ],
          camposExtra: {'vehiculo_unidad': v['id']},
        ),
      ),
    );
    if (vendido != true || !mounted) return;
    await _cargar();
    if (!mounted || _v?['estado'] != 'vendido') return;
    if (venta.aPlazo) {
      if (!widget.negocio.prestamosActivo) {
        _aviso("Vendido. Para registrar el plazo activá el módulo de préstamos en Ajustes.");
        return;
      }
      final creado = await abrirNuevoPrestamo(context, widget.negocio, inicial: {
        'cliente': _v!['cliente'],
        'moneda': moneda,
        'precio': venta.precio,
        'unidad': _v!['id'],
        'vehiculo': {
          'marca': _v!['marca'],
          'modelo': _v!['modelo'],
          'anio': _v!['anio'],
          'placa': _v!['placa'],
          'vin': _v!['vin'],
          'color': _v!['color'],
        },
      });
      if (creado == true) {
        await _cargar();
        if (mounted) _aviso("Vendido y con su préstamo creado.");
      }
    } else {
      _aviso("¡Vendido! El vehículo salió del inventario.");
    }
  }

  Widget _dato(String etiqueta, String? valor, {Color? color}) => (valor == null || valor.isEmpty || valor == 'null')
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 150, child: Text(etiqueta, style: TextStyle(color: AppColors.textMuted))),
            Expanded(child: SelectableText(valor, style: TextStyle(fontWeight: FontWeight.w600, color: color ?? AppColors.textStrong))),
          ]),
        );

  Widget _caja(String titulo, List<Widget> hijos) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          const SizedBox(height: 6),
          ...hijos,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final moneda = '${v['moneda']}';
    final vendido = v['estado'] == 'vendido';
    final prestamo = v['prestamo'] as Map?;
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(
        title: Text(_titulo(v), overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        bottom: _trabajando ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
        actions: [const BotonCalculadora(), 
          IconButton(onPressed: _editar, icon: const Icon(Icons.edit_outlined), tooltip: "Editar"),
          if (!vendido) IconButton(onPressed: _borrar, icon: const Icon(Icons.delete_outline), tooltip: "Borrar"),
        ],
      ),
      bottomNavigationBar: vendido
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _trabajando ? null : () => _cambiarEstado(v['estado'] == 'reservado' ? 'disponible' : 'reservado'),
                      child: Text(v['estado'] == 'reservado' ? "Quitar reserva" : "Reservar"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _trabajando ? null : () => _cambiarEstado(v['estado'] == 'taller' ? 'disponible' : 'taller'),
                      child: Text(v['estado'] == 'taller' ? "Ya está listo" : "A preparación"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _trabajando ? null : _vender,
                      icon: const Icon(Icons.sell_outlined),
                      label: const Text("Vender"),
                    ),
                  ),
                ]),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (v['foto'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network('${v['foto']}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => _sinFoto()),
                      ),
                    ),
                  ),
                Row(children: [
                  _chipEstado('${v['estado']}'),
                  const SizedBox(width: 8),
                  Text(v['condicion'] == 'nuevo' ? "Nuevo" : "Usado", style: TextStyle(color: AppColors.textMuted)),
                  const Spacer(),
                  Text(_dinero(vendido ? (v['precio_vendido'] ?? v['precio_venta']) : v['precio_venta'], moneda),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                ]),
                if (v['estado'] == 'reservado' && v['cliente_nombre'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      "Reservado para ${v['cliente_nombre']}${v['reservado_hasta'] != null ? ' hasta el ${_fecha(v['reservado_hasta'])}' : ''}",
                      style: const TextStyle(color: _ambar, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(height: 12),
                if (vendido)
                  _caja("Venta", [
                    _dato("Cliente", v['cliente_nombre']),
                    _dato("Fecha", _fecha(v['fecha_venta'])),
                    _dato("Factura", v['factura_consecutivo']),
                    _dato("Vendido en", _dinero(v['precio_vendido'] ?? v['precio_venta'], moneda)),
                    _dato("Ganancia", _dinero(v['margen'], moneda), color: _n(v['margen']) >= 0 ? _verde : _rojo),
                    if (prestamo != null) _dato("Préstamo", "#${prestamo['numero']} (${prestamo['estado']})"),
                    if (prestamo == null && widget.negocio.prestamosActivo)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.handshake_outlined),
                          label: const Text("Crear el préstamo de esta venta"),
                          onPressed: () async {
                            final creado = await abrirNuevoPrestamo(context, widget.negocio, inicial: {
                              'cliente': v['cliente'],
                              'moneda': moneda,
                              'precio': v['precio_vendido'] ?? v['precio_venta'],
                              'unidad': v['id'],
                              'vehiculo': {'marca': v['marca'], 'modelo': v['modelo'], 'anio': v['anio'], 'placa': v['placa'], 'vin': v['vin'], 'color': v['color']},
                            });
                            if (creado == true) _cargar();
                          },
                        ),
                      ),
                  ]),
                _caja("Identificación", [
                  _dato("Marca y modelo", _titulo(v)),
                  _dato("Color", v['color']),
                  _dato("Placa", v['placa']),
                  _dato("VIN / chasis", v['vin']),
                  _dato("Número de motor", v['numero_motor']),
                ]),
                _caja("Características", [
                  _dato("Tipo", v['carroceria']),
                  _dato("Combustible", _combustibles[v['combustible']]),
                  _dato("Transmisión", _transmisiones[v['transmision']]),
                  _dato("Tracción", v['traccion']),
                  _dato("Cilindrada", v['cilindrada'] == null ? null : "${formatearNumero(_n(v['cilindrada']))} cc"),
                  _dato("Kilometraje", v['kilometraje'] == null ? null : "${formatearNumero(_n(v['kilometraje']))} km"),
                  _dato("Pasajeros", v['pasajeros']?.toString()),
                  _dato("Extras", v['extras']),
                ]),
                _caja("Documentos", [
                  _dato("DUA / póliza", v['dua']),
                  _dato("RTV vence", v['rtv_vence'] == null ? 'Sin dato' : _fecha(v['rtv_vence']), color: v['rtv_vencida'] == true ? _rojo : null),
                  _dato("Marchamo", v['marchamo_al_dia'] == true ? "Al día" : "Sin confirmar"),
                ]),
                _caja("Costo y ganancia", [
                  _dato("Costo de compra", _dinero(v['costo'], moneda)),
                  _dato("Otros costos", _dinero(v['otros_costos'], moneda)),
                  _dato("Costo total", _dinero(v['costo_total'], moneda)),
                  _dato("Precio de venta", _dinero(v['precio_venta'], moneda)),
                  if (v['precio_minimo'] != null) _dato("Precio mínimo", _dinero(v['precio_minimo'], moneda)),
                  _dato(vendido ? "Ganancia" : "Ganancia esperada", _dinero(v['margen'], moneda), color: _n(v['margen']) >= 0 ? _verde : _rojo),
                ]),
                _caja("Ingreso", [
                  _dato("Fecha de ingreso", _fecha(v['fecha_ingreso'])),
                  _dato("Días en inventario", "${v['dias_en_inventario'] ?? ''}"),
                  _dato("Proveedor", v['proveedor']),
                  _dato("Ubicación", v['ubicacion']),
                  _dato("Se factura con", v['producto_nombre'] ?? "Falta elegir el producto"),
                  _dato("Notas", v['notas']),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- Venta

class _Venta {
  final double precio;
  final bool aPlazo;
  final List<Producto> accesorios;
  _Venta(this.precio, this.aPlazo, this.accesorios);
}

/// Precio final, contado o a plazo, y los accesorios o servicios que van en
/// la misma factura (racks, polarizado, mantenimientos…).
class _DialogoVenta extends StatefulWidget {
  final Map<String, dynamic> vehiculo;
  final List<Producto> productos;
  const _DialogoVenta({required this.vehiculo, required this.productos});

  @override
  State<_DialogoVenta> createState() => _DialogoVentaState();
}

class _DialogoVentaState extends State<_DialogoVenta> {
  late final TextEditingController _precio;
  bool _aPlazo = false;
  final Set<int> _elegidos = {};
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _precio = TextEditingController(text: _n(widget.vehiculo['precio_venta']).toStringAsFixed(2))..addListener(() => setState(() {}));
  }

  double get _valor => double.tryParse(_precio.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final v = widget.vehiculo;
    final moneda = '${v['moneda']}';
    final minimo = v['precio_minimo'] == null ? null : _n(v['precio_minimo']);
    final lista = widget.productos.where((p) => _busca.isEmpty || p.nombre.toLowerCase().contains(_busca.toLowerCase())).toList();
    return AlertDialog(
      title: Text("Vender ${_titulo(v)}"),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _precio,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: "Precio de venta (sin IVA)",
                prefixText: moneda == 'USD' ? '\$ ' : '₡ ',
                border: const OutlineInputBorder(),
                helperText: minimo != null && _valor < minimo ? "Está por debajo del precio mínimo (${_dinero(minimo, moneda)})" : null,
                helperStyle: const TextStyle(color: _rojo),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text("De contado"), icon: Icon(Icons.payments_outlined)),
                ButtonSegment(value: true, label: Text("A plazo"), icon: Icon(Icons.handshake_outlined)),
              ],
              selected: {_aPlazo},
              onSelectionChanged: (s) => setState(() => _aPlazo = s.first),
            ),
            if (_aPlazo)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Después de la factura se abre el préstamo con el carro, el cliente y el precio ya puestos; ahí ponés la prima, la tasa y el plazo.",
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ),
            const SizedBox(height: 14),
            Text("Accesorios y servicios en la misma factura", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            Text("Racks, polarizado, alarma, mantenimientos… (productos y servicios de tu inventario). También podés agregar más en la factura.",
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            TextField(
              decoration: const InputDecoration(hintText: "Buscar accesorio o servicio", prefixIcon: Icon(Icons.search, size: 20), isDense: true, border: OutlineInputBorder()),
              onChanged: (t) => setState(() => _busca = t.trim()),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: lista.isEmpty
                  ? Padding(padding: const EdgeInsets.all(12), child: Text("No hay productos con ese nombre.", style: TextStyle(color: AppColors.textMuted)))
                  : ListView(shrinkWrap: true, children: [
                      for (final p in lista)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _elegidos.contains(p.id),
                          onChanged: (x) => setState(() => x == true ? _elegidos.add(p.id) : _elegidos.remove(p.id)),
                          title: Text(p.nombre),
                          subtitle: Text(
                              "${p.monedaPrecio == 'USD' ? formatearDolares(p.precioUnitario) : formatearColones(p.precioUnitario, decimales: 0)}${p.tipo == 'servicio' ? ' · servicio' : ''}"),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
        FilledButton.icon(
          onPressed: _valor <= 0
              ? null
              : () => Navigator.pop(context, _Venta(_valor, _aPlazo, widget.productos.where((p) => _elegidos.contains(p.id)).toList())),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text("Seguir a la factura"),
        ),
      ],
    );
  }
}
