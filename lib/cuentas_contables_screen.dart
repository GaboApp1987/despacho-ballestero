import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'cuenta_contable.dart';

/// Catálogo de cuentas contables de un negocio -- base de los Asientos
/// Contables. Cada negocio tiene su propio catálogo (nunca se comparte
/// entre clientes).
class CuentasContablesScreen extends StatefulWidget {
  final int negocioId;
  final String negocioNombre;

  const CuentasContablesScreen({super.key, required this.negocioId, required this.negocioNombre});

  @override
  State<CuentasContablesScreen> createState() => _CuentasContablesScreenState();
}

class _CuentasContablesScreenState extends State<CuentasContablesScreen> {
  bool _cargando = true;
  bool _sembrando = false;
  List<CuentaContable> _cuentas = [];
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  List<CuentaContable> get _cuentasFiltradas {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return _cuentas;
    return _cuentas.where((c) {
      return c.codigo.toLowerCase().contains(q) ||
          c.nombre.toLowerCase().contains(q) ||
          (CuentaContable.tiposEtiquetas[c.tipo] ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await ApiService.get('/cuentas-contables/?negocio=${widget.negocioId}');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _cuentas = data.map((j) => CuentaContable.fromJson(j)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _sembrarCatalogo() async {
    setState(() => _sembrando = true);
    try {
      final r = await ApiService.post('/cuentas-contables/sembrar-catalogo/', {'negocio': widget.negocioId});
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes));
        if (mounted) {
          setState(() => _cuentas = (data['cuentas'] as List).map((j) => CuentaContable.fromJson(j)).toList());
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Catálogo cargado (${data['creadas']} cuentas nuevas)."), backgroundColor: Colors.green));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo cargar el catálogo.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
    if (mounted) setState(() => _sembrando = false);
  }

  Future<void> _abrirFormulario({CuentaContable? cuenta}) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => _FormularioCuentaDialog(negocioId: widget.negocioId, cuenta: cuenta, cuentasDisponibles: _cuentas),
    );
    if (resultado == true) _cargar();
  }

  Future<void> _eliminar(CuentaContable cuenta) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Eliminar cuenta?"),
        content: Text("Se eliminará la cuenta ${cuenta.codigo} - ${cuenta.nombre}."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Eliminar", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final r = await ApiService.delete('/cuentas-contables/${cuenta.id}/');
      if (r.statusCode == 204) {
        _cargar();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo eliminar: la cuenta tiene movimientos o subcuentas registradas.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte), tooltip: "Volver", onPressed: () => Navigator.pop(context)),
        title: Text("Catálogo de Cuentas", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: TemaContador.acento,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Nueva cuenta"),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _cuentas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_tree_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text("${widget.negocioNombre} todavía no tiene catálogo de cuentas.", style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _sembrando ? null : _sembrarCatalogo,
                        style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white, disabledBackgroundColor: TemaContador.acento.withOpacity(0.5), disabledForegroundColor: Colors.white),
                        icon: _sembrando ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.playlist_add_check),
                        label: const Text("Cargar catálogo estándar de Costa Rica"),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _busquedaCtrl,
                        style: const TextStyle(color: TemaContador.textoFuerte),
                        onChanged: (v) => setState(() => _busqueda = v),
                        decoration: InputDecoration(
                          hintText: "Buscar por código, nombre o tipo...",
                          hintStyle: const TextStyle(color: TemaContador.textoTenue),
                          prefixIcon: const Icon(Icons.search, color: TemaContador.textoTenue),
                          suffixIcon: _busqueda.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, color: TemaContador.textoTenue),
                                  onPressed: () => setState(() {
                                    _busquedaCtrl.clear();
                                    _busqueda = '';
                                  }),
                                ),
                          filled: true,
                          fillColor: TemaContador.superficie,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _cuentasFiltradas.isEmpty
                          ? Center(
                              child: Text("Ninguna cuenta coincide con \"$_busqueda\".", style: const TextStyle(color: Colors.grey)),
                            )
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                itemCount: _cuentasFiltradas.length,
                                itemBuilder: (context, index) {
                                  final c = _cuentasFiltradas[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    color: c.esDetalle ? TemaContador.superficie : TemaContador.fondo,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.esDetalle ? TemaContador.borde : TemaContador.acento.withOpacity(0.3))),
                                    child: ListTile(
                                      dense: !c.esDetalle,
                                      leading: Icon(c.esDetalle ? Icons.description_outlined : Icons.folder_outlined, color: c.esDetalle ? TemaContador.textoTenue : TemaContador.acento, size: 20),
                                      title: Text(
                                        "${c.codigo} · ${c.nombre}",
                                        style: TextStyle(color: TemaContador.textoFuerte, fontWeight: c.esDetalle ? FontWeight.w500 : FontWeight.w800, fontSize: c.esDetalle ? 14 : 13.5),
                                      ),
                                      subtitle: Text(
                                        "${CuentaContable.tiposEtiquetas[c.tipo] ?? c.tipo} · ${CuentaContable.naturalezaEtiquetas[c.naturaleza] ?? c.naturaleza}",
                                        style: const TextStyle(color: TemaContador.textoTenue, fontSize: 11.5),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(icon: const Icon(Icons.edit_outlined, size: 19, color: TemaContador.textoTenue), onPressed: () => _abrirFormulario(cuenta: c)),
                                          IconButton(icon: const Icon(Icons.delete_outline, size: 19, color: TemaContador.textoTenue), onPressed: () => _eliminar(c)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _FormularioCuentaDialog extends StatefulWidget {
  final int negocioId;
  final CuentaContable? cuenta;
  final List<CuentaContable> cuentasDisponibles;

  const _FormularioCuentaDialog({required this.negocioId, this.cuenta, required this.cuentasDisponibles});

  @override
  State<_FormularioCuentaDialog> createState() => _FormularioCuentaDialogState();
}

class _FormularioCuentaDialogState extends State<_FormularioCuentaDialog> {
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  String _tipo = 'activo';
  String _naturaleza = 'deudora';
  bool _esDetalle = true;
  int? _cuentaPadre;
  bool _guardando = false;

  static const Map<String, String> _naturalezaPorTipo = {
    'activo': 'deudora',
    'gasto': 'deudora',
    'costo': 'deudora',
    'pasivo': 'acreedora',
    'patrimonio': 'acreedora',
    'ingreso': 'acreedora',
  };

  @override
  void initState() {
    super.initState();
    final c = widget.cuenta;
    if (c != null) {
      _codigoCtrl.text = c.codigo;
      _nombreCtrl.text = c.nombre;
      _tipo = c.tipo;
      _naturaleza = c.naturaleza;
      _esDetalle = c.esDetalle;
      _cuentaPadre = c.cuentaPadre;
    }
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_codigoCtrl.text.trim().isEmpty || _nombreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Completá código y nombre.")));
      return;
    }
    setState(() => _guardando = true);
    final cuenta = CuentaContable(
      id: widget.cuenta?.id,
      negocio: widget.negocioId,
      codigo: _codigoCtrl.text.trim(),
      nombre: _nombreCtrl.text.trim(),
      tipo: _tipo,
      naturaleza: _naturaleza,
      cuentaPadre: _cuentaPadre,
      esDetalle: _esDetalle,
    );
    try {
      final esNuevo = widget.cuenta == null;
      final r = esNuevo
          ? await ApiService.post('/cuentas-contables/', cuenta.toJson())
          : await ApiService.patch('/cuentas-contables/${widget.cuenta!.id}/', cuenta.toJson());
      if (r.statusCode == 200 || r.statusCode == 201) {
        if (mounted) Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo guardar (HTTP ${r.statusCode}). Revisá que el código no esté repetido.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
    if (mounted) setState(() => _guardando = false);
  }

  InputDecoration _decoracion(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: TemaContador.textoTenue),
        filled: true,
        fillColor: TemaContador.superficie,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    final padres = widget.cuentasDisponibles.where((c) => !c.esDetalle && c.id != widget.cuenta?.id).toList();
    return AlertDialog(
      backgroundColor: TemaContador.fondo,
      title: Text(widget.cuenta == null ? "Nueva cuenta contable" : "Editar cuenta contable", style: const TextStyle(color: TemaContador.textoFuerte, fontSize: 17)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(controller: _codigoCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Código")),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(controller: _nombreCtrl, style: const TextStyle(color: TemaContador.textoFuerte), decoration: _decoracion("Nombre")),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: _decoracion("Tipo"),
                style: const TextStyle(color: TemaContador.textoFuerte),
                dropdownColor: TemaContador.fondo,
                items: CuentaContable.tiposEtiquetas.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: TemaContador.textoFuerte))))
                    .toList(),
                onChanged: (v) => setState(() {
                  _tipo = v ?? 'activo';
                  _naturaleza = _naturalezaPorTipo[_tipo] ?? 'deudora';
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _naturaleza,
                decoration: _decoracion("Naturaleza"),
                style: const TextStyle(color: TemaContador.textoFuerte),
                dropdownColor: TemaContador.fondo,
                items: CuentaContable.naturalezaEtiquetas.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: TemaContador.textoFuerte))))
                    .toList(),
                onChanged: (v) => setState(() => _naturaleza = v ?? 'deudora'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _cuentaPadre,
                decoration: _decoracion("Cuenta de mayor (opcional)"),
                style: const TextStyle(color: TemaContador.textoFuerte),
                dropdownColor: TemaContador.fondo,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text("Sin cuenta de mayor", style: TextStyle(color: TemaContador.textoTenue))),
                  ...padres.map((p) => DropdownMenuItem<int?>(value: p.id, child: Text("${p.codigo} - ${p.nombre}", overflow: TextOverflow.ellipsis, style: const TextStyle(color: TemaContador.textoFuerte)))),
                ],
                onChanged: (v) => setState(() => _cuentaPadre = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Es cuenta de detalle (recibe movimientos)", style: TextStyle(color: TemaContador.textoFuerte, fontSize: 13)),
                value: _esDetalle,
                activeColor: TemaContador.acento,
                onChanged: (v) => setState(() => _esDetalle = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white, disabledBackgroundColor: TemaContador.acento.withOpacity(0.5), disabledForegroundColor: Colors.white),
          onPressed: _guardando ? null : _guardar,
          child: _guardando ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Guardar"),
        ),
      ],
    );
  }
}
