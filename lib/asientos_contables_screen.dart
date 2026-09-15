import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'asiento_contable.dart';
import 'cuenta_contable.dart';
import 'cuentas_contables_screen.dart';
import 'estados_financieros_screen.dart';
import 'negocio.dart';

/// Punto de entrada de "Asientos Contables" en la sidebar del contador:
/// elegís el negocio (cliente) cuyos libros vas a llevar y de ahí entrás
/// al libro diario y al catálogo de cuentas de ESE negocio -- los asientos
/// nunca se mezclan entre negocios, cada uno tiene su propia contabilidad.
class AsientosContablesScreen extends StatefulWidget {
  const AsientosContablesScreen({super.key});

  @override
  State<AsientosContablesScreen> createState() => _AsientosContablesScreenState();
}

class _AsientosContablesScreenState extends State<AsientosContablesScreen> {
  bool _cargandoNegocios = true;
  List<Negocio> _negocios = [];
  Negocio? _negocioSeleccionado;

  @override
  void initState() {
    super.initState();
    _cargarNegocios();
  }

  Future<void> _cargarNegocios() async {
    try {
      final r = await ApiService.get('/negocios/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        final negocios = data.map((j) => Negocio.fromJson(j)).toList();
        if (mounted) {
          setState(() {
            _negocios = negocios;
            if (negocios.isNotEmpty) _negocioSeleccionado = negocios.first;
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _cargandoNegocios = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: const Text("Asientos Contables", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      body: _cargandoNegocios
          ? const Center(child: CircularProgressIndicator())
          : _negocios.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text("No tenés negocios registrados todavía. Creá un negocio primero para poder llevar su contabilidad.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_outlined, color: TemaContador.acento, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<Negocio>(
                              initialValue: _negocioSeleccionado,
                              decoration: InputDecoration(
                                labelText: "Cliente / negocio",
                                labelStyle: const TextStyle(color: TemaContador.textoTenue),
                                filled: true,
                                fillColor: TemaContador.superficie,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
                              ),
                              style: const TextStyle(color: TemaContador.textoFuerte),
                              dropdownColor: TemaContador.fondo,
                              items: _negocios
                                  .map((n) => DropdownMenuItem(value: n, child: Text(n.nombreComercial, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TemaContador.textoFuerte))))
                                  .toList(),
                              onChanged: (n) => setState(() => _negocioSeleccionado = n),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_negocioSeleccionado != null)
                      Expanded(
                        child: _LibroDiario(
                          key: ValueKey(_negocioSeleccionado!.id),
                          negocio: _negocioSeleccionado!,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _LibroDiario extends StatefulWidget {
  final Negocio negocio;
  const _LibroDiario({super.key, required this.negocio});

  @override
  State<_LibroDiario> createState() => _LibroDiarioState();
}

class _LibroDiarioState extends State<_LibroDiario> {
  bool _cargando = true;
  List<AsientoContable> _asientos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await ApiService.get('/asientos-contables/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _asientos = data.map((j) => AsientoContable.fromJson(j)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _nuevoAsiento() async {
    final creado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => AsientoContableFormScreen(negocioId: widget.negocio.id, negocioNombre: widget.negocio.nombreComercial)),
    );
    if (creado == true) _cargar();
  }

  Future<void> _editarAsiento(AsientoContable a) async {
    final editado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => AsientoContableFormScreen(negocioId: widget.negocio.id, negocioNombre: widget.negocio.nombreComercial, asiento: a)),
    );
    if (editado == true) _cargar();
  }

  Future<void> _generarAutomaticos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaContador.fondo,
        title: const Text("Generar asientos automáticos", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 16)),
        content: const Text(
          "Va a crear un asiento por cada Factura, Compra y Gasto Operativo de este negocio que todavía no tenga uno, usando el catálogo de cuentas estándar. No duplica los que ya se generaron antes.",
          style: TextStyle(color: TemaContador.textoTenue),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Generar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: TemaContador.fondo,
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text("Generando asientos...", style: TextStyle(color: TemaContador.textoFuerte))),
          ],
        ),
      ),
    );

    try {
      final r = await ApiService.post('/asientos-contables/generar-automaticos/?negocio=${widget.negocio.id}', {});
      if (mounted) Navigator.pop(context); // cierra el diálogo de "Generando..."
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes));
        final creados = data['creados'] ?? 0;
        final omitidos = (data['omitidos'] as List?) ?? [];
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: TemaContador.fondo,
              title: Text(creados > 0 ? "¡Listo!" : "Nada para generar", style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 16)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      creados > 0 ? "Se crearon $creados asiento(s) nuevo(s)." : "No había documentos pendientes de convertir en asiento.",
                      style: const TextStyle(color: TemaContador.textoFuerte),
                    ),
                    if (omitidos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text("Se omitieron ${omitidos.length}:", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: omitidos
                                .map((o) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        "${o['tipo']} #${o['id']}${o['referencia'] != null && o['referencia'].toString().isNotEmpty ? ' (${o['referencia']})' : ''}: ${o['motivo']}",
                                        style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar"))],
            ),
          );
          if (creados > 0) _cargar();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo generar los asientos.")));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _eliminar(AsientoContable a) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Eliminar asiento?"),
        content: Text("Se eliminará el asiento #${a.numero} (${a.concepto})."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Eliminar", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final r = await ApiService.delete('/asientos-contables/${a.id}/');
      if (r.statusCode == 204) {
        _cargar();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo eliminar el asiento.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'catalogo',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CuentasContablesScreen(negocioId: widget.negocio.id, negocioNombre: widget.negocio.nombreComercial))),
            backgroundColor: TemaContador.textoFuerte,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text("Catálogo de cuentas"),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'estados-financieros',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EstadosFinancierosScreen(negocioId: widget.negocio.id, negocioNombre: widget.negocio.nombreComercial))),
            backgroundColor: TemaContador.textoFuerte,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.bar_chart_outlined),
            label: const Text("Estados financieros"),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'generar-automaticos',
            onPressed: _generarAutomaticos,
            backgroundColor: TemaContador.textoFuerte,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text("Generar automáticos"),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'nuevo-asiento',
            onPressed: _nuevoAsiento,
            backgroundColor: TemaContador.acento,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text("Nuevo asiento"),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _asientos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("Todavía no hay asientos contables para este negocio.", style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text("Usá \"Catálogo de cuentas\" para revisar las cuentas y \"Nuevo asiento\" para el primer registro.", style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 150),
                    itemCount: _asientos.length,
                    itemBuilder: (context, index) {
                      final a = _asientos[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: TemaContador.superficie,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: TemaContador.borde)),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: const Color(0x1A1D4ED8), child: Text("#${a.numero}", style: const TextStyle(color: TemaContador.acento, fontSize: 11, fontWeight: FontWeight.bold))),
                          title: Text(a.concepto, style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte)),
                          subtitle: Text(
                            "${a.fecha.day}/${a.fecha.month}/${a.fecha.year} · Debe ₡${a.totalDebe.toStringAsFixed(2)} / Haber ₡${a.totalHaber.toStringAsFixed(2)}",
                            style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12),
                          ),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: TemaContador.textoTenue), onPressed: () => _eliminar(a)),
                          onTap: () => _editarAsiento(a),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class AsientoContableFormScreen extends StatefulWidget {
  final int negocioId;
  final String negocioNombre;
  final AsientoContable? asiento;

  const AsientoContableFormScreen({super.key, required this.negocioId, required this.negocioNombre, this.asiento});

  @override
  State<AsientoContableFormScreen> createState() => _AsientoContableFormScreenState();
}

class _AsientoContableFormScreenState extends State<AsientoContableFormScreen> {
  late AsientoContable _asiento;
  final _conceptoCtrl = TextEditingController();
  final _referenciaCtrl = TextEditingController();
  bool _cargandoCuentas = true;
  bool _guardando = false;
  List<CuentaContable> _cuentas = [];

  final List<TextEditingController> _detalleCtrls = [];
  final List<TextEditingController> _debeCtrls = [];
  final List<TextEditingController> _haberCtrls = [];

  @override
  void initState() {
    super.initState();
    _asiento = widget.asiento ?? AsientoContable(negocio: widget.negocioId);
    _conceptoCtrl.text = _asiento.concepto;
    _referenciaCtrl.text = _asiento.referencia;
    if (_asiento.detalles.isEmpty) {
      _asiento.detalles = [DetalleAsientoContable(), DetalleAsientoContable()];
    }
    for (final d in _asiento.detalles) {
      _detalleCtrls.add(TextEditingController(text: d.detalle));
      _debeCtrls.add(TextEditingController(text: d.debe == 0 ? '' : d.debe.toStringAsFixed(2)));
      _haberCtrls.add(TextEditingController(text: d.haber == 0 ? '' : d.haber.toStringAsFixed(2)));
    }
    _cargarCuentas();
  }

  @override
  void dispose() {
    _conceptoCtrl.dispose();
    _referenciaCtrl.dispose();
    for (final c in _detalleCtrls) {
      c.dispose();
    }
    for (final c in _debeCtrls) {
      c.dispose();
    }
    for (final c in _haberCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarCuentas() async {
    try {
      final r = await ApiService.get('/cuentas-contables/?negocio=${widget.negocioId}');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) {
          setState(() => _cuentas = data.map((j) => CuentaContable.fromJson(j)).where((c) => c.esDetalle && c.activa).toList());
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _cargandoCuentas = false);
  }

  double get _totalDebe => _debeCtrls.fold(0.0, (s, c) => s + (double.tryParse(c.text.replaceAll(',', '')) ?? 0));
  double get _totalHaber => _haberCtrls.fold(0.0, (s, c) => s + (double.tryParse(c.text.replaceAll(',', '')) ?? 0));
  bool get _cuadrado => (_totalDebe - _totalHaber).abs() < 0.005 && _totalDebe > 0;

  void _agregarLinea() {
    setState(() {
      _asiento.detalles.add(DetalleAsientoContable());
      _detalleCtrls.add(TextEditingController());
      _debeCtrls.add(TextEditingController());
      _haberCtrls.add(TextEditingController());
    });
  }

  void _quitarLinea(int i) {
    setState(() {
      _asiento.detalles.removeAt(i);
      _detalleCtrls.removeAt(i).dispose();
      _debeCtrls.removeAt(i).dispose();
      _haberCtrls.removeAt(i).dispose();
    });
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(context: context, initialDate: _asiento.fecha, firstDate: DateTime(2015), lastDate: DateTime(DateTime.now().year + 1));
    if (elegida != null) setState(() => _asiento.fecha = elegida);
  }

  Future<void> _guardar() async {
    if (_conceptoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresá el concepto del asiento.")));
      return;
    }
    for (int i = 0; i < _asiento.detalles.length; i++) {
      if (_asiento.detalles[i].cuenta == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Elegí la cuenta contable de la línea ${i + 1}.")));
        return;
      }
    }
    if (!_cuadrado) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("El asiento no cuadra: débito ₡${_totalDebe.toStringAsFixed(2)} vs. crédito ₡${_totalHaber.toStringAsFixed(2)}.")));
      return;
    }

    setState(() => _guardando = true);
    _asiento.concepto = _conceptoCtrl.text.trim();
    _asiento.referencia = _referenciaCtrl.text.trim();
    for (int i = 0; i < _asiento.detalles.length; i++) {
      _asiento.detalles[i].detalle = _detalleCtrls[i].text.trim();
      _asiento.detalles[i].debe = double.tryParse(_debeCtrls[i].text.replaceAll(',', '')) ?? 0;
      _asiento.detalles[i].haber = double.tryParse(_haberCtrls[i].text.replaceAll(',', '')) ?? 0;
    }
    final lineas = _asiento.detalles.where((d) => d.debe != 0 || d.haber != 0).toList();

    try {
      final body = {..._asiento.toJson(), 'detalles': lineas.map((d) => d.toJson()).toList()};
      final esNuevo = _asiento.id == null;
      final r = esNuevo ? await ApiService.post('/asientos-contables/', body) : await ApiService.patch('/asientos-contables/${_asiento.id}/', body);
      if (r.statusCode == 200 || r.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Asiento guardado"), backgroundColor: Colors.green));
          Navigator.pop(context, true);
        }
      } else {
        final texto = utf8.decode(r.bodyBytes);
        throw Exception(texto);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  InputDecoration _decoracion(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: TemaContador.textoTenue),
        filled: true,
        fillColor: TemaContador.fondo,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: Text(_asiento.id == null ? "Nuevo asiento contable" : "Editar asiento #${_asiento.numero}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      body: _cargandoCuentas
          ? const Center(child: CircularProgressIndicator())
          : _cuentas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                      const SizedBox(height: 12),
                      Text("${widget.negocioNombre} todavía no tiene cuentas contables de detalle.", textAlign: TextAlign.center, style: const TextStyle(color: TemaContador.textoFuerte)),
                      const SizedBox(height: 8),
                      const Text("Volvé y cargá el catálogo de cuentas primero.", style: TextStyle(color: TemaContador.textoTenue)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(14), border: Border.all(color: TemaContador.borde)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _elegirFecha,
                                  child: InputDecorator(
                                    decoration: _decoracion("Fecha"),
                                    child: Text("${_asiento.fecha.day}/${_asiento.fecha.month}/${_asiento.fecha.year}", style: const TextStyle(color: TemaContador.textoFuerte)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: TextField(controller: _referenciaCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Referencia (opcional)"))),
                            ]),
                            const SizedBox(height: 10),
                            TextField(controller: _conceptoCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Concepto del asiento *")),
                          ],
                        ),
                      ),
                      const Text("Líneas (debe / haber)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: TemaContador.textoFuerte)),
                      const SizedBox(height: 8),
                      ..._asiento.detalles.asMap().entries.map((entry) {
                        final i = entry.key;
                        final d = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: TemaContador.superficie, borderRadius: BorderRadius.circular(10), border: Border.all(color: TemaContador.borde)),
                          child: Column(
                            children: [
                              Row(children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    initialValue: d.cuenta,
                                    isExpanded: true,
                                    decoration: _decoracion("Cuenta"),
                                    style: const TextStyle(color: TemaContador.textoFuerte),
                                    dropdownColor: TemaContador.fondo,
                                    items: _cuentas.map((c) => DropdownMenuItem(value: c.id, child: Text("${c.codigo} - ${c.nombre}", overflow: TextOverflow.ellipsis, style: const TextStyle(color: TemaContador.textoFuerte)))).toList(),
                                    onChanged: (v) => setState(() => d.cuenta = v),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: TemaContador.textoTenue),
                                  onPressed: _asiento.detalles.length <= 2 ? null : () => _quitarLinea(i),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              TextField(controller: _detalleCtrls[i], style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Glosa de la línea (opcional)")),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: TextField(
                                    controller: _debeCtrls[i],
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: TemaContador.textoFuerte),
                                    decoration: _decoracion("Debe"),
                                    onChanged: (v) {
                                      if (v.isNotEmpty) _haberCtrls[i].clear();
                                      setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _haberCtrls[i],
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: TemaContador.textoFuerte),
                                    decoration: _decoracion("Haber"),
                                    onChanged: (v) {
                                      if (v.isNotEmpty) _debeCtrls[i].clear();
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: _agregarLinea,
                        style: TextButton.styleFrom(foregroundColor: TemaContador.acento),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("Agregar línea"),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _cuadrado ? Colors.green.withOpacity(0.08) : Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _cuadrado ? Colors.green : Colors.red),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Debe: ₡${_totalDebe.toStringAsFixed(2)}", style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w700)),
                            Text("Haber: ₡${_totalHaber.toStringAsFixed(2)}", style: const TextStyle(color: TemaContador.textoFuerte, fontWeight: FontWeight.w700)),
                            Icon(_cuadrado ? Icons.check_circle : Icons.error_outline, color: _cuadrado ? Colors.green : Colors.red),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaContador.acento,
              foregroundColor: Colors.white,
              disabledBackgroundColor: TemaContador.acento.withOpacity(0.5),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: (_guardando || _cargandoCuentas || _cuentas.isEmpty) ? null : _guardar,
            child: _guardando ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Guardar asiento"),
          ),
        ),
      ),
    );
  }
}
