import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'cuentas_por_cobrar_screen.dart' show abrirWhatsApp;
import 'formato.dart';
import 'formulario_compra.dart';
import 'negocio.dart';
import 'producto.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Órdenes de compra (gestion/ordenes_compra.py): lo que se le pide al
/// proveedor. No mueve inventario ni contabilidad; eso lo hace la factura
/// del proveedor, que se liga a la orden para comparar lo pedido, lo
/// recibido y lo facturado.

double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
String _cant(double c) => formatearNumero(c, decimales: c % 1 == 0 ? 0 : 3);
double? _leer(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));
String _fecha(DateTime d) => "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
String _fechaApi(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

String textoEstadoOrden(String estado) => const {
      'borrador': 'Borrador',
      'enviada': 'Enviada',
      'parcial': 'Recibida en parte',
      'recibida': 'Recibida',
      'facturada': 'Facturada',
      'cancelada': 'Cancelada',
    }[estado] ??
    estado;

Color colorEstadoOrden(String estado) => switch (estado) {
      'enviada' => Colors.blue,
      'parcial' => Colors.orange,
      'recibida' => Colors.teal,
      'facturada' => Colors.green,
      'cancelada' => Colors.red,
      _ => Colors.grey,
    };

class LineaOrden {
  final int? id;
  final int? productoId;
  final int? insumoId;
  final String nombre;
  final String unidad;
  final String descripcion;
  double cantidad;
  double precio;
  double? tarifa;
  final double recibido;
  final double facturado;

  LineaOrden({
    this.id,
    this.productoId,
    this.insumoId,
    required this.nombre,
    this.unidad = 'unid.',
    this.descripcion = '',
    required this.cantidad,
    required this.precio,
    this.tarifa,
    this.recibido = 0,
    this.facturado = 0,
  });

  factory LineaOrden.fromJson(Map<String, dynamic> j) => LineaOrden(
        id: j['id'],
        productoId: j['producto'],
        insumoId: j['insumo'],
        nombre: (j['nombre'] ?? '').toString(),
        unidad: (j['unidad'] ?? 'unid.').toString(),
        descripcion: (j['descripcion'] ?? '').toString(),
        cantidad: _num(j['cantidad']),
        precio: _num(j['precio']),
        tarifa: j['tarifa_iva'] == null ? null : _num(j['tarifa_iva']),
        recibido: _num(j['cantidad_recibida']),
        facturado: _num(j['facturado']),
      );

  bool get comparable => productoId != null || insumoId != null;
  double get subtotal => cantidad * precio;
  double get iva => subtotal * (tarifa ?? 0) / 100;

  Map<String, dynamic> toJson() => {
        if (productoId != null) 'producto': productoId,
        if (insumoId != null) 'insumo': insumoId,
        'descripcion': descripcion.isEmpty && !comparable ? nombre : descripcion,
        'cantidad': productoId != null ? cantidad.round().toString() : cantidad.toStringAsFixed(3),
        'precio': precio.toStringAsFixed(2),
        'tarifa_iva': tarifa,
      };
}

class OrdenCompra {
  final int id;
  final int proveedorId;
  final String nombreProveedor;
  final String correoProveedor;
  final String telefonoProveedor;
  final int numero;
  final DateTime? fecha;
  final DateTime? fechaEntrega;
  final String estado;
  final String notas;
  final DateTime? fechaEnvio;
  final String medioEnvio;
  final List<LineaOrden> lineas;
  final double subtotal;
  final double iva;
  final double total;
  final List<Map<String, dynamic>> compras;

  OrdenCompra({
    required this.id,
    required this.proveedorId,
    required this.nombreProveedor,
    this.correoProveedor = '',
    this.telefonoProveedor = '',
    required this.numero,
    this.fecha,
    this.fechaEntrega,
    required this.estado,
    this.notas = '',
    this.fechaEnvio,
    this.medioEnvio = '',
    required this.lineas,
    this.subtotal = 0,
    this.iva = 0,
    this.total = 0,
    this.compras = const [],
  });

  factory OrdenCompra.fromJson(Map<String, dynamic> j) => OrdenCompra(
        id: j['id'],
        proveedorId: j['proveedor'],
        nombreProveedor: (j['nombre_proveedor'] ?? '').toString(),
        correoProveedor: (j['correo_proveedor'] ?? '').toString(),
        telefonoProveedor: (j['telefono_proveedor'] ?? '').toString(),
        numero: j['numero'] ?? 0,
        fecha: DateTime.tryParse(j['fecha']?.toString() ?? '')?.toLocal(),
        fechaEntrega: DateTime.tryParse(j['fecha_entrega']?.toString() ?? ''),
        estado: (j['estado'] ?? 'borrador').toString(),
        notas: (j['notas'] ?? '').toString(),
        fechaEnvio: DateTime.tryParse(j['fecha_envio']?.toString() ?? '')?.toLocal(),
        medioEnvio: (j['medio_envio'] ?? '').toString(),
        lineas: [for (final l in (j['detalles'] as List? ?? [])) LineaOrden.fromJson(Map<String, dynamic>.from(l))],
        subtotal: _num(j['subtotal']),
        iva: _num(j['iva']),
        total: _num(j['total']),
        compras: [for (final c in (j['compras'] as List? ?? [])) Map<String, dynamic>.from(c)],
      );

  String get codigo => "OC-${numero.toString().padLeft(5, '0')}";
  bool get abierta => estado != 'facturada' && estado != 'cancelada';
  bool get editable => (estado == 'borrador' || estado == 'enviada') && compras.isEmpty;
}

/// Una diferencia entre la factura del proveedor y la orden. [alerta] es
/// lo que conviene revisar antes de aceptar ante Hacienda (cobran más o
/// facturan lo que no llegó); lo demás es informativo (entrega parcial).
class DiferenciaOrden {
  final String texto;
  final bool alerta;
  const DiferenciaOrden(this.texto, {this.alerta = true});
}

/// Compara las líneas de una factura del proveedor con lo que falta por
/// facturar de la orden, y con lo que se contó al recibir (si se registró).
List<DiferenciaOrden> compararConOrden(OrdenCompra orden, List<LineaCompra> factura) {
  final resultado = <DiferenciaOrden>[];
  final usadas = <LineaCompra>{};
  for (final l in orden.lineas.where((l) => l.comparable)) {
    final enFactura = factura
        .where((c) => l.productoId != null ? c.producto?.id == l.productoId : c.insumo?.id == l.insumoId)
        .toList();
    usadas.addAll(enFactura);
    final pendiente = math.max(0.0, l.cantidad - l.facturado);
    final facturan = enFactura.fold(0.0, (s, c) => s + c.cantidad);
    const eps = 0.0005;
    if (facturan == 0) {
      if (pendiente > eps) {
        resultado.add(DiferenciaOrden(
            "${l.nombre}: faltan ${_cant(pendiente)} ${l.unidad} por facturar (no viene en esta factura).",
            alerta: false));
      }
      continue;
    }
    if (facturan > pendiente + eps) {
      resultado.add(DiferenciaOrden(
          "${l.nombre}: facturan ${_cant(facturan)} ${l.unidad} y faltaban ${_cant(pendiente)} de la orden."));
    } else if (facturan < pendiente - eps) {
      resultado.add(DiferenciaOrden(
          "${l.nombre}: facturan ${_cant(facturan)} de ${_cant(pendiente)} ${l.unidad}; quedan ${_cant(pendiente - facturan)} pendientes.",
          alerta: false));
    }
    final recibidoSinFacturar = l.recibido - l.facturado;
    if (l.recibido > 0 && facturan > recibidoSinFacturar + eps) {
      resultado.add(DiferenciaOrden(
          "${l.nombre}: al recibir se contaron ${_cant(math.max(0.0, recibidoSinFacturar))} ${l.unidad} y facturan ${_cant(facturan)}."));
    }
    if (l.precio > 0) {
      for (final c in enFactura) {
        final dif = c.precioCosto - l.precio;
        if (dif.abs() >= 0.01) {
          final pct = dif / l.precio * 100;
          resultado.add(DiferenciaOrden(
              "${l.nombre}: precio ${formatearColones(c.precioCosto)} y se pidió a ${formatearColones(l.precio)} "
              "(${pct > 0 ? '+' : ''}${formatearNumero(pct, decimales: 1)} %).",
              alerta: dif > 0));
        }
      }
    }
  }
  for (final c in factura.where((c) => !usadas.contains(c))) {
    resultado.add(DiferenciaOrden("${c.nombre}: no estaba en la orden."));
  }
  return resultado;
}

/// Lo que falta por facturar de la orden, como líneas de compra. Las
/// líneas de solo descripción no se pueden cargar a inventario.
List<LineaCompra> lineasPendientesDeOrden(OrdenCompra orden, List<Producto> productos, List<InsumoCompra> insumos) {
  final resultado = <LineaCompra>[];
  for (final l in orden.lineas) {
    final pendiente = l.cantidad - l.facturado;
    if (pendiente <= 0.0005) continue;
    if (l.productoId != null) {
      final p = productos.where((p) => p.id == l.productoId).firstOrNull;
      if (p != null) {
        resultado.add(LineaCompra(producto: p, cantidad: pendiente.roundToDouble(), precioCosto: l.precio, tarifa: l.tarifa));
      }
    } else if (l.insumoId != null) {
      final i = insumos.where((i) => i.id == l.insumoId).firstOrNull;
      if (i != null) resultado.add(LineaCompra(insumo: i, cantidad: pendiente, precioCosto: l.precio, tarifa: l.tarifa));
    }
  }
  return resultado;
}

/// Cuadro con las diferencias, para el formulario de compra.
class PanelDiferenciasOrden extends StatelessWidget {
  final OrdenCompra orden;
  final List<DiferenciaOrden> diferencias;
  const PanelDiferenciasOrden({super.key, required this.orden, required this.diferencias});

  @override
  Widget build(BuildContext context) {
    final hayAlerta = diferencias.any((d) => d.alerta);
    final color = diferencias.isEmpty ? Colors.green : (hayAlerta ? Colors.orange : Colors.blue);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(diferencias.isEmpty ? Icons.verified_outlined : Icons.compare_arrows, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              diferencias.isEmpty
                  ? "Coincide con la orden ${orden.codigo}"
                  : "Comparada con la orden ${orden.codigo}",
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ]),
        for (final d in diferencias)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(d.alerta ? Icons.warning_amber_rounded : Icons.info_outline,
                  size: 16, color: d.alerta ? Colors.orange : Colors.blueGrey),
              const SizedBox(width: 6),
              Expanded(child: Text(d.texto, style: const TextStyle(fontSize: 12.5))),
            ]),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ lista

class OrdenesCompraTab extends StatefulWidget {
  final Negocio negocio;
  const OrdenesCompraTab({super.key, required this.negocio});

  @override
  State<OrdenesCompraTab> createState() => _OrdenesCompraTabState();
}

class _OrdenesCompraTabState extends State<OrdenesCompraTab> {
  bool _cargando = true;
  bool _soloAbiertas = true;
  List<OrdenCompra> _ordenes = [];
  int _sugerencias = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await Future.wait([
        ApiService.get('/ordenes-compra/?negocio=${widget.negocio.id}'),
        ApiService.get('/ordenes-compra/sugerencias/?negocio=${widget.negocio.id}'),
      ]);
      if (r[0].statusCode != 200) throw Exception(ApiService.mensajeError(r[0]));
      if (!mounted) return;
      setState(() {
        _ordenes = [for (final j in json.decode(utf8.decode(r[0].bodyBytes)) as List) OrdenCompra.fromJson(j)];
        _sugerencias = r[1].statusCode == 200 ? (json.decode(utf8.decode(r[1].bodyBytes)) as List).length : 0;
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiService.textoError(e);
          _cargando = false;
        });
      }
    }
  }

  Future<void> _abrir(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _soloAbiertas ? _ordenes.where((o) => o.abierta).toList() : _ordenes;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(label: const Text("Abiertas"), selected: _soloAbiertas, onSelected: (_) => setState(() => _soloAbiertas = true)),
            ChoiceChip(label: const Text("Todas"), selected: !_soloAbiertas, onSelected: (_) => setState(() => _soloAbiertas = false)),
            FilledButton.icon(
              onPressed: () => _abrir(FormularioOrdenCompra(negocio: widget.negocio)),
              icon: const Icon(Icons.add),
              label: const Text("Nueva orden"),
            ),
          ]),
          if (_sugerencias > 0) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.amber.withOpacity(0.12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.amber.withOpacity(0.5)),
              ),
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined, color: Colors.orange),
                title: Text(_sugerencias == 1
                    ? "1 producto o insumo está en su mínimo"
                    : "$_sugerencias productos o insumos están en su mínimo"),
                subtitle: const Text("Armá el pedido con lo que falta, ya agrupado por proveedor."),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _abrir(SugerenciasCompraScreen(negocio: widget.negocio)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_cargando)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text("No se pudieron cargar las órdenes: $_error"))
          else if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Icon(Icons.assignment_outlined, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 8),
                Text(
                  _soloAbiertas ? "No hay órdenes abiertas." : "Todavía no hay órdenes de compra.",
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  "Pedile al proveedor desde acá y, cuando llegue su factura, ligala a la orden para comparar.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ]),
            )
          else
            for (final o in lista)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _abrir(DetalleOrdenCompraScreen(negocio: widget.negocio, ordenId: o.id)),
                  title: Text("${o.codigo} · ${o.nombreProveedor}", style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text([
                      if (o.fecha != null) _fecha(o.fecha!),
                      "${o.lineas.length} ${o.lineas.length == 1 ? 'línea' : 'líneas'}",
                      if (o.fechaEntrega != null) "entrega ${_fecha(o.fechaEntrega!)}",
                    ].join(' · ')),
                    const SizedBox(height: 4),
                    _ChipEstado(o.estado),
                  ]),
                  trailing: Text(formatearColones(o.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
        ],
      ),
    );
  }
}

class _ChipEstado extends StatelessWidget {
  final String estado;
  const _ChipEstado(this.estado);

  @override
  Widget build(BuildContext context) {
    final color = colorEstadoOrden(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(textoEstadoOrden(estado), style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

// ------------------------------------------------------------- formulario

class FormularioOrdenCompra extends StatefulWidget {
  final Negocio negocio;
  final OrdenCompra? orden;
  const FormularioOrdenCompra({super.key, required this.negocio, this.orden});

  @override
  State<FormularioOrdenCompra> createState() => _FormularioOrdenCompraState();
}

class _FormularioOrdenCompraState extends State<FormularioOrdenCompra> {
  bool _cargando = true;
  bool _guardando = false;
  List<Proveedor> _proveedores = [];
  List<Producto> _productos = [];
  List<InsumoCompra> _insumos = [];
  int? _proveedorId;
  DateTime? _entrega;
  final _notas = TextEditingController();
  final List<LineaOrden> _lineas = [];
  // Para que los selectores de "Agregar" vuelvan a quedar vacíos.
  int _reinicio = 0;

  @override
  void initState() {
    super.initState();
    final o = widget.orden;
    if (o != null) {
      _proveedorId = o.proveedorId;
      _entrega = o.fechaEntrega;
      _notas.text = o.notas;
      _lineas.addAll(o.lineas.map((l) => LineaOrden(
            productoId: l.productoId,
            insumoId: l.insumoId,
            nombre: l.nombre,
            unidad: l.unidad,
            descripcion: l.descripcion,
            cantidad: l.cantidad,
            precio: l.precio,
            tarifa: l.tarifa,
          )));
    }
    _cargar();
  }

  Future<void> _cargar() async {
    final n = widget.negocio.id;
    try {
      final r = await Future.wait([
        ApiService.get('/proveedores/?negocio=$n'),
        ApiService.get('/productos/?negocio=$n'),
        ApiService.get('/insumos/?negocio=$n'),
      ]);
      List decodificar(int i) => r[i].statusCode == 200 ? json.decode(utf8.decode(r[i].bodyBytes)) as List : [];
      if (!mounted) return;
      setState(() {
        _proveedores = decodificar(0).map((j) => Proveedor.fromJson(j)).toList();
        _productos = decodificar(1).map((j) => Producto.fromJson(j)).where((p) => p.tipo != 'servicio').toList();
        _insumos = decodificar(2).map((j) => InsumoCompra.fromJson(j)).toList();
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Pide cantidad, precio e IVA de una línea (nueva o para editarla).
  Future<LineaOrden?> _dialogoLinea(LineaOrden base, {bool soloDescripcion = false}) {
    final nombre = TextEditingController(text: soloDescripcion ? base.nombre : '');
    final cantidad = TextEditingController(text: base.cantidad > 0 ? _cant(base.cantidad) : '');
    final precio = TextEditingController(text: base.precio > 0 ? base.precio.toStringAsFixed(2) : '');
    double? tarifa = base.tarifa;
    return showDialog<LineaOrden>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(soloDescripcion ? "Otra cosa" : base.nombre),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (soloDescripcion)
                TextField(controller: nombre, decoration: const InputDecoration(labelText: "Qué se pide")),
              TextField(
                controller: cantidad,
                autofocus: !soloDescripcion,
                decoration: InputDecoration(
                  labelText: "Cantidad (${base.unidad})",
                  helperText: base.productoId != null ? "Unidades enteras" : "Con decimales, ej. 50,5",
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: precio,
                decoration: InputDecoration(labelText: "Precio por ${base.unidad} sin IVA (₡)"),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              DropdownButtonFormField<double?>(
                value: tarifa,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "IVA"),
                items: [
                  const DropdownMenuItem<double?>(value: null, child: Text("Sin IVA / no sé")),
                  for (final t in <double>{13.0, 4.0, 2.0, 1.0, 0.5, 0.0, if (tarifa != null) tarifa!})
                    DropdownMenuItem<double?>(value: t, child: Text("${formatearNumero(t, decimales: t % 1 == 0 ? 0 : 1)} %")),
                ],
                onChanged: (v) => setD(() => tarifa = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            FilledButton(
              onPressed: () {
                final c = _leer(cantidad.text) ?? 0;
                if (c <= 0 || (soloDescripcion && nombre.text.trim().isEmpty)) return;
                if (base.productoId != null && c % 1 != 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Los productos se piden en unidades enteras.")));
                  return;
                }
                Navigator.pop(
                  ctx,
                  LineaOrden(
                    productoId: base.productoId,
                    insumoId: base.insumoId,
                    nombre: soloDescripcion ? nombre.text.trim() : base.nombre,
                    unidad: base.unidad,
                    cantidad: c,
                    precio: _leer(precio.text) ?? 0,
                    tarifa: tarifa,
                  ),
                );
              },
              child: const Text("Listo"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _agregar(LineaOrden base, {bool soloDescripcion = false}) async {
    final linea = await _dialogoLinea(base, soloDescripcion: soloDescripcion);
    setState(() {
      if (linea != null) _lineas.add(linea);
      _reinicio++;
    });
  }

  Future<void> _guardar() async {
    if (_proveedorId == null || _lineas.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Elegí el proveedor y agregá al menos una línea.")));
      return;
    }
    setState(() => _guardando = true);
    final body = {
      'negocio': widget.negocio.id,
      'proveedor': _proveedorId,
      'fecha_entrega': _entrega == null ? null : _fechaApi(_entrega!),
      'notas': _notas.text.trim(),
      'detalles': [for (final l in _lineas) l.toJson()],
    };
    try {
      final r = widget.orden == null
          ? await ApiService.post('/ordenes-compra/', body)
          : await ApiService.put('/ordenes-compra/${widget.orden!.id}/', body);
      if (r.statusCode != 200 && r.statusCode != 201) throw Exception(ApiService.mensajeError(r));
      if (mounted) Navigator.pop(context, OrdenCompra.fromJson(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("No se pudo guardar la orden: ${ApiService.textoError(e)}")));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _lineas.fold(0.0, (s, l) => s + redondear2(l.subtotal));
    final iva = _lineas.fold(0.0, (s, l) => s + redondear2(l.iva));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orden == null ? "Nueva orden de compra" : "Editar ${widget.orden!.codigo}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: const [BotonCalculadora()],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  DropdownButtonFormField<int>(
                    value: _proveedores.any((p) => p.id == _proveedorId) ? _proveedorId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: "Proveedor", border: OutlineInputBorder()),
                    items: [for (final p in _proveedores) DropdownMenuItem(value: p.id, child: Text(p.nombre))],
                    onChanged: (v) => setState(() => _proveedorId = v),
                  ),
                  if (_proveedores.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text("Primero agregá el proveedor en la pestaña Proveedores.",
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final hoy = DateTime.now();
                      final elegida = await showDatePicker(
                        context: context,
                        initialDate: _entrega ?? hoy,
                        firstDate: DateTime(hoy.year - 1),
                        lastDate: DateTime(hoy.year + 1, 12, 31),
                      );
                      if (elegida != null) setState(() => _entrega = elegida);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: "Entrega esperada (opcional)",
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.event),
                        suffixIcon: _entrega == null
                            ? null
                            : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _entrega = null)),
                      ),
                      child: Text(_entrega == null ? "Sin fecha" : _fecha(_entrega!)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text("Qué se pide", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_productos.isNotEmpty)
                    DropdownButtonFormField<Producto>(
                      key: ValueKey('producto$_reinicio'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: "Agregar producto", border: OutlineInputBorder(), prefixIcon: Icon(Icons.add_box)),
                      items: [for (final p in _productos) DropdownMenuItem(value: p, child: Text(p.nombre))],
                      onChanged: (p) {
                        if (p == null) return;
                        _agregar(LineaOrden(
                          productoId: p.id,
                          nombre: p.nombre,
                          cantidad: 0,
                          precio: p.costo,
                          tarifa: p.impuesto?.porcentaje,
                        ));
                      },
                    ),
                  if (_insumos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<InsumoCompra>(
                      key: ValueKey('insumo$_reinicio'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: "Agregar insumo", border: OutlineInputBorder(), prefixIcon: Icon(Icons.kitchen_outlined)),
                      items: [
                        for (final i in _insumos) DropdownMenuItem(value: i, child: Text("${i.nombre} (${i.unidadTexto})"))
                      ],
                      onChanged: (i) {
                        if (i == null) return;
                        _agregar(LineaOrden(
                          insumoId: i.id,
                          nombre: i.nombre,
                          unidad: i.unidadTexto,
                          cantidad: 0,
                          precio: redondear2(i.costo),
                          tarifa: 13,
                        ));
                      },
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _agregar(LineaOrden(nombre: '', cantidad: 0, precio: 0, tarifa: 13), soloDescripcion: true),
                      icon: const Icon(Icons.edit_note),
                      label: const Text("Agregar otra cosa (solo descripción)"),
                    ),
                  ),
                  for (var i = 0; i < _lineas.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(_lineas[i].nombre),
                        subtitle: Text(
                          "${_cant(_lineas[i].cantidad)} ${_lineas[i].unidad} × ${formatearColones(_lineas[i].precio)} · "
                          "${_lineas[i].tarifa == null ? 'sin IVA' : 'IVA ${formatearNumero(_lineas[i].tarifa!, decimales: _lineas[i].tarifa! % 1 == 0 ? 0 : 1)} %'}",
                        ),
                        onTap: () async {
                          final l = _lineas[i];
                          final editada = await _dialogoLinea(l, soloDescripcion: !l.comparable);
                          if (editada != null) setState(() => _lineas[i] = editada);
                        },
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(formatearColones(_lineas[i].subtotal)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _lineas.removeAt(i)),
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notas,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Notas para el proveedor (opcional)",
                      hintText: "Ej. entregar en la puerta de atrás",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ]),
              ),
              if (_lineas.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                  child: Column(children: [
                    _fila("Subtotal", subtotal),
                    _fila("IVA", iva),
                    _fila("Total", subtotal + iva, fuerte: true),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  child: _guardando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.orden == null ? "GUARDAR ORDEN" : "GUARDAR CAMBIOS"),
                ),
              ),
            ]),
    );
  }
}

Widget _fila(String texto, double monto, {bool fuerte = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(texto, style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.normal))),
        Text(formatearColones(monto), style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );

// ---------------------------------------------------------------- detalle

class DetalleOrdenCompraScreen extends StatefulWidget {
  final Negocio negocio;
  final int ordenId;
  const DetalleOrdenCompraScreen({super.key, required this.negocio, required this.ordenId});

  @override
  State<DetalleOrdenCompraScreen> createState() => _DetalleOrdenCompraScreenState();
}

class _DetalleOrdenCompraScreenState extends State<DetalleOrdenCompraScreen> {
  OrdenCompra? _orden;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/ordenes-compra/${widget.ordenId}/');
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      if (mounted) setState(() => _orden = OrdenCompra.fromJson(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  /// Llama una acción del backend y refresca con la orden que devuelve.
  Future<bool> _accion(String ruta, [Map<String, dynamic> body = const {}]) async {
    setState(() => _ocupado = true);
    try {
      final r = await ApiService.post('/ordenes-compra/${widget.ordenId}/$ruta/', body);
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      if (mounted) setState(() => _orden = OrdenCompra.fromJson(json.decode(utf8.decode(r.bodyBytes))));
      return true;
    } catch (e) {
      if (mounted) _aviso(ApiService.textoError(e));
      return false;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _verPdf() async {
    setState(() => _ocupado = true);
    try {
      final r = await ApiService.get('/ordenes-compra/${widget.ordenId}/pdf/');
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      await Printing.layoutPdf(onLayout: (_) async => r.bodyBytes, name: _orden!.codigo);
    } catch (e) {
      if (mounted) _aviso("No se pudo abrir el PDF: ${ApiService.textoError(e)}");
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _enviarCorreo() async {
    final o = _orden!;
    final ctrl = TextEditingController(text: o.correoProveedor);
    final correo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Enviar por correo"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Se le manda a ${o.nombreProveedor} la orden en PDF."),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: "Correo del proveedor"),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Enviar")),
        ],
      ),
    );
    if (correo == null || correo.isEmpty) return;
    if (await _accion('enviar', {'medio': 'correo', 'correo': correo})) _aviso("Orden enviada a $correo.");
  }

  Future<void> _enviarWhatsApp() async {
    final o = _orden!;
    var telefono = o.telefonoProveedor;
    if (telefono.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      final ctrl = TextEditingController();
      final escrito = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("WhatsApp del proveedor"),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: "Número", hintText: "8888 8888"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Seguir")),
          ],
        ),
      );
      if (escrito == null || escrito.replaceAll(RegExp(r'[^0-9]'), '').length < 8) return;
      telefono = escrito;
      // Se guarda en el proveedor para la próxima.
      try {
        await ApiService.patch('/proveedores/${o.proveedorId}/', {'telefono': telefono});
      } catch (_) {}
    }
    final lineas = [
      for (final l in o.lineas)
        "• ${_cant(l.cantidad)} ${l.unidad} de ${l.nombre}${l.precio > 0 ? ' a ${formatearColones(l.precio)}' : ''}"
    ];
    final mensaje = [
      "Hola ${o.nombreProveedor}, le enviamos la orden de compra ${o.codigo} de ${widget.negocio.nombreComercial}:",
      ...lineas,
      if (o.total > 0) "Total con IVA: ${formatearColones(o.total)}",
      if (o.fechaEntrega != null) "La necesitamos para el ${_fecha(o.fechaEntrega!)}.",
      if (o.notas.isNotEmpty) o.notas,
      "Por favor indique el número ${o.codigo} en su factura electrónica. ¡Gracias!",
    ].join('\n');
    if (!mounted) return;
    await abrirWhatsApp(context, telefono, mensaje);
    await _accion('enviar', {'medio': 'whatsapp'});
  }

  Future<void> _registrarRecepcion() async {
    final o = _orden!;
    final ctrls = {
      for (final l in o.lineas) l.id!: TextEditingController(text: _cant(l.recibido > 0 ? l.recibido : l.cantidad))
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Lo que llegó"),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Contá lo que llegó en total de cada línea. El inventario entra con la factura del proveedor.",
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final l in o.lineas)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextField(
                    controller: ctrls[l.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l.nombre,
                      helperText: "Pedido: ${_cant(l.cantidad)} ${l.unidad}",
                      suffixText: l.unidad,
                    ),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    );
    if (ok != true) return;
    await _accion('recibir', {
      'lineas': [
        for (final e in ctrls.entries) {'id': e.key, 'cantidad_recibida': (_leer(e.value.text) ?? 0).toStringAsFixed(3)}
      ],
    });
  }

  Future<void> _registrarFactura() async {
    final guardada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FormularioCompra(negocio: widget.negocio, ordenId: widget.ordenId)),
    );
    if (guardada == true) _cargar();
  }

  Future<void> _editar() async {
    final editada = await Navigator.push<OrdenCompra>(
      context,
      MaterialPageRoute(builder: (_) => FormularioOrdenCompra(negocio: widget.negocio, orden: _orden)),
    );
    if (editada != null) _cargar();
  }

  Future<bool> _confirmar(String titulo, String texto, String boton) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Volver")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(boton)),
          ],
        ),
      ) ==
      true;

  Future<void> _borrar() async {
    if (!await _confirmar("Borrar orden", "Se borra ${_orden!.codigo}. No se puede deshacer.", "Borrar")) return;
    try {
      final r = await ApiService.delete('/ordenes-compra/${widget.ordenId}/');
      if (r.statusCode != 204) throw Exception(ApiService.mensajeError(r));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _orden;
    return Scaffold(
      appBar: AppBar(
        title: Text(o?.codigo ?? "Orden de compra"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [const BotonCalculadora(), 
          if (o != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'editar') _editar();
                if (v == 'borrar') _borrar();
                if (v == 'reabrir') _accion('reabrir');
                if (v == 'cancelar' &&
                    await _confirmar("Cancelar orden",
                        "Lo que falta por recibir ya no se espera. Las facturas ya ligadas se quedan.", "Cancelar orden")) {
                  _accion('cancelar');
                }
              },
              itemBuilder: (_) => [
                if (o.editable) const PopupMenuItem(value: 'editar', child: Text("Editar")),
                if (o.abierta) const PopupMenuItem(value: 'cancelar', child: Text("Cancelar lo pendiente")),
                if (o.estado == 'cancelada') const PopupMenuItem(value: 'reabrir', child: Text("Reabrir")),
                if (o.editable) const PopupMenuItem(value: 'borrar', child: Text("Borrar")),
              ],
            ),
        ],
      ),
      body: o == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_ocupado) const LinearProgressIndicator(),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(o.nombreProveedor,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                        _ChipEstado(o.estado),
                      ]),
                      const SizedBox(height: 6),
                      Text([
                        if (o.fecha != null) "Hecha el ${_fecha(o.fecha!)}",
                        if (o.fechaEntrega != null) "entrega ${_fecha(o.fechaEntrega!)}",
                      ].join(' · '), style: TextStyle(color: AppColors.textMuted)),
                      if (o.fechaEnvio != null)
                        Text(
                          "Enviada el ${_fecha(o.fechaEnvio!)} por ${o.medioEnvio == 'whatsapp' ? 'WhatsApp' : 'correo'}",
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      if (o.notas.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(o.notas),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (o.abierta) ...[
                    FilledButton.icon(
                      onPressed: _ocupado ? null : _registrarFactura,
                      icon: const Icon(Icons.receipt_long),
                      label: const Text("Registrar factura"),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : _registrarRecepcion,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text("Lo que llegó"),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : _enviarCorreo,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text("Correo"),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : _enviarWhatsApp,
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text("WhatsApp"),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _ocupado ? null : _verPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text("PDF"),
                  ),
                ]),
                const SizedBox(height: 16),
                Text("Pedido, recibido y facturado", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final l in o.lineas) _LineaDetalle(l),
                const SizedBox(height: 8),
                _fila("Subtotal", o.subtotal),
                _fila("IVA", o.iva),
                _fila("Total", o.total, fuerte: true),
                const SizedBox(height: 16),
                Text("Facturas del proveedor", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (o.compras.isEmpty)
                  Text("Todavía no se ha ligado ninguna. Usá \"Registrar factura\" cuando llegue.",
                      style: TextStyle(color: AppColors.textMuted))
                else
                  for (final c in o.compras)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_outlined),
                      title: Text("Factura ${c['numero_factura'] ?? ''}"),
                      subtitle: Text(DateTime.tryParse(c['fecha']?.toString() ?? '') == null
                          ? ''
                          : _fecha(DateTime.parse(c['fecha'].toString()).toLocal())),
                      trailing: Text(formatearColones(_num(c['total']))),
                    ),
              ]),
            ),
    );
  }
}

class _LineaDetalle extends StatelessWidget {
  final LineaOrden l;
  const _LineaDetalle(this.l);

  @override
  Widget build(BuildContext context) {
    final completa = !l.comparable || l.facturado >= l.cantidad - 0.0005;
    final faltaRecibir = l.recibido > 0 && l.recibido < l.cantidad - 0.0005;
    Widget dato(String etiqueta, double valor, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(etiqueta, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text("${_cant(valor)} ${l.unidad}", style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ]),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(l.nombre, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text("${formatearColones(l.precio)} c/u", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            dato("Pedido", l.cantidad),
            dato("Recibido", l.recibido, color: faltaRecibir ? Colors.orange : null),
            if (l.comparable) dato("Facturado", l.facturado, color: completa ? Colors.green : null),
          ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- sugerencias

class SugerenciasCompraScreen extends StatefulWidget {
  final Negocio negocio;
  const SugerenciasCompraScreen({super.key, required this.negocio});

  @override
  State<SugerenciasCompraScreen> createState() => _SugerenciasCompraScreenState();
}

class _Sugerencia {
  final Map<String, dynamic> datos;
  bool elegida = true;
  int? proveedorId;
  final TextEditingController cantidad;
  _Sugerencia(this.datos)
      : proveedorId = datos['proveedor'],
        cantidad = TextEditingController(text: _cant(_num(datos['cantidad'])));
}

class _SugerenciasCompraScreenState extends State<SugerenciasCompraScreen> {
  bool _cargando = true;
  bool _creando = false;
  List<_Sugerencia> _items = [];
  List<Proveedor> _proveedores = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final n = widget.negocio.id;
    try {
      final r = await Future.wait([
        ApiService.get('/ordenes-compra/sugerencias/?negocio=$n'),
        ApiService.get('/proveedores/?negocio=$n'),
      ]);
      if (!mounted) return;
      setState(() {
        if (r[0].statusCode == 200) {
          _items = [for (final j in json.decode(utf8.decode(r[0].bodyBytes)) as List) _Sugerencia(Map<String, dynamic>.from(j))];
        }
        if (r[1].statusCode == 200) {
          _proveedores = [for (final j in json.decode(utf8.decode(r[1].bodyBytes)) as List) Proveedor.fromJson(j)];
        }
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _crear() async {
    final elegidas = _items.where((s) => s.elegida).toList();
    if (elegidas.isEmpty) return;
    if (elegidas.any((s) => s.proveedorId == null)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Elegí el proveedor de cada insumo marcado.")));
      return;
    }
    setState(() => _creando = true);
    try {
      final r = await ApiService.post('/ordenes-compra/desde-sugerencias/', {
        'negocio': widget.negocio.id,
        'items': [
          for (final s in elegidas)
            {
              if (s.datos['producto'] != null) 'producto': s.datos['producto'] else 'insumo': s.datos['insumo'],
              'cantidad': s.datos['producto'] != null
                  ? (_leer(s.cantidad.text) ?? 0).round().toString()
                  : (_leer(s.cantidad.text) ?? 0).toStringAsFixed(3),
              'proveedor': s.proveedorId,
              // El último precio solo sirve si es del mismo proveedor.
              'precio': s.proveedorId == s.datos['proveedor'] ? s.datos['precio'] : '0',
              'tarifa_iva': s.datos['tarifa_iva'],
            }
        ],
      });
      if (r.statusCode != 201) throw Exception(ApiService.mensajeError(r));
      final creadas = (json.decode(utf8.decode(r.bodyBytes)) as List).length;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(creadas == 1
              ? "Se creó 1 orden en borrador. Revisala y mandala al proveedor."
              : "Se crearon $creadas órdenes en borrador, una por proveedor.")));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("No se pudieron crear: ${ApiService.textoError(e)}")));
      }
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final marcadas = _items.where((s) => s.elegida).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Qué pedir"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: const [BotonCalculadora()],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text("Nada está en su mínimo."))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                    "Estos productos e insumos están en su mínimo o por debajo. La cantidad sugerida llega al doble del mínimo; "
                    "el proveedor es el de la última compra.",
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  for (final s in _items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                        child: Column(children: [
                          CheckboxListTile(
                            value: s.elegida,
                            onChanged: (v) => setState(() => s.elegida = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.datos['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                "Quedan ${_cant(_num(s.datos['stock']))} ${s.datos['unidad']} · mínimo ${_cant(_num(s.datos['minimo']))}"),
                          ),
                          if (s.elegida)
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Row(children: [
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: s.cantidad,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(labelText: "Pedir", suffixText: s.datos['unidad'], isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _proveedores.any((p) => p.id == s.proveedorId) ? s.proveedorId : null,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: "Proveedor", isDense: true),
                                    items: [
                                      for (final p in _proveedores) DropdownMenuItem(value: p.id, child: Text(p.nombre))
                                    ],
                                    onChanged: (v) => setState(() => s.proveedorId = v),
                                  ),
                                ),
                              ]),
                            ),
                        ]),
                      ),
                    ),
                ]),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _creando || marcadas == 0 ? null : _crear,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  child: _creando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text("Crear órdenes ($marcadas)"),
                ),
              ),
            ),
    );
  }
}
