import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'package:file_picker/file_picker.dart';

import 'api_service.dart';
import 'catalogo_cuentas_util.dart';
import 'cuenta_contable.dart';
import 'export_service.dart';
import 'negocio.dart';

/// Catálogo de cuentas contables de un negocio -- base de los Asientos
/// Contables. Cada negocio tiene su propio catálogo. Se muestra como árbol
/// (cuentas de mayor plegables, sangría por nivel) y desde el menú se puede
/// cargar el estándar de CR, copiar el de otro cliente o la plantilla del
/// contador, guardarlo como plantilla e importar/exportar Excel (backend:
/// gestion/catalogo.py).
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
  // Cuentas de mayor plegadas (sus subcuentas no se muestran).
  final Set<int> _plegadas = {};
  bool _procesando = false;

  /// Lo que se ve: con búsqueda, todas las que coinciden; sin búsqueda, el
  /// árbol sin las descendientes de una cuenta plegada.
  List<CuentaContable> get _visibles {
    if (_busqueda.trim().isNotEmpty) return _cuentasFiltradas;
    final porId = {for (final c in _cuentas) if (c.id != null) c.id!: c};
    bool oculta(CuentaContable c) {
      var padre = c.cuentaPadre;
      var guardia = 0;
      while (padre != null && guardia++ < 12) {
        if (_plegadas.contains(padre)) return true;
        padre = porId[padre]?.cuentaPadre;
      }
      return false;
    }

    return _cuentas.where((c) => !oculta(c)).toList();
  }

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

  Future<void> _abrirFormulario({CuentaContable? cuenta, CuentaContable? padre}) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => _FormularioCuentaDialog(
        negocioId: widget.negocioId,
        cuenta: cuenta,
        padreInicial: padre,
        cuentasDisponibles: _cuentas,
      ),
    );
    if (resultado == true) _cargar();
  }

  void _avisar(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), backgroundColor: error ? Colors.red : null));
  }

  /// Muestra el resultado de importar/copiar: cuántas se crearon o, si hubo
  /// errores, la lista para corregir el archivo (no se guardó nada).
  Future<void> _mostrarResultado(Map data, String accion) async {
    final errores = (data['errores'] as List?) ?? [];
    if (errores.isEmpty) {
      _avisar("$accion: ${data['creadas']} cuenta(s) nueva(s)"
          "${(data['actualizadas'] ?? 0) > 0 ? ', ${data['actualizadas']} actualizada(s)' : ''}"
          "${(data['omitidas'] ?? 0) > 0 ? ', ${data['omitidas']} ya existían' : ''}.");
      await _cargar();
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("No se importó nada: hay errores"),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: errores
                .map((e) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      title: Text(e['error'].toString()),
                      subtitle: e['fila'] != null ? Text("Fila ${e['fila']} de las cuentas") : null,
                    ))
                .toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendido"))],
      ),
    );
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() => _procesando = true);
    try {
      await accion();
    } catch (e) {
      _avisar(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _importarExcel() => _ejecutar(() async {
        final archivo = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
        final bytes = archivo?.files.single.bytes;
        if (bytes == null) return;
        final filas = leerCatalogoExcel(bytes);
        if (!mounted) return;
        var actualizar = false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setStateDialog) => AlertDialog(
              title: Text("Importar ${filas.length} cuenta(s)"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Se agregarán al catálogo de ${widget.negocioNombre}. Las cuentas de mayor se enlazan por código."),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: actualizar,
                    onChanged: (v) => setStateDialog(() => actualizar = v ?? false),
                    title: const Text("Actualizar las cuentas que ya existen con el mismo código"),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Importar")),
              ],
            ),
          ),
        );
        if (ok != true) return;
        final res = await ApiService.post('/cuentas-contables/importar/', {
          'negocio': widget.negocioId,
          'filas': filas,
          'actualizar': actualizar,
        });
        if (res.statusCode != 200 && res.statusCode != 400) throw Exception(ApiService.mensajeError(res));
        await _mostrarResultado(json.decode(utf8.decode(res.bodyBytes)), "Importación");
      });

  Future<void> _exportarExcel() =>
      _ejecutar(() => ExportService.exportCatalogoCuentasToExcel(_cuentas, widget.negocioNombre));

  Future<void> _copiarDesdeCliente() => _ejecutar(() async {
        final res = ApiService.verificar(await ApiService.get('/negocios/'));
        final otros = (json.decode(utf8.decode(res.bodyBytes)) as List)
            .map((j) => Negocio.fromJson(j))
            .where((n) => n.id != widget.negocioId)
            .toList();
        if (otros.isEmpty) throw Exception("No tenés otros clientes de donde copiar.");
        if (!mounted) return;
        final origen = await showDialog<Negocio>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text("¿De qué cliente copiar el catálogo?"),
            children: otros.map((n) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, n), child: Text(n.nombreComercial))).toList(),
          ),
        );
        if (origen == null) return;
        final r = await ApiService.post('/cuentas-contables/copiar/', {'negocio': widget.negocioId, 'origen': origen.id});
        if (r.statusCode != 200 && !(r.statusCode == 400 && utf8.decode(r.bodyBytes).contains('errores'))) {
          throw Exception(ApiService.mensajeError(r));
        }
        await _mostrarResultado(json.decode(utf8.decode(r.bodyBytes)), "Copiado de ${origen.nombreComercial}");
      });

  Future<void> _copiarDesdePlantilla() => _ejecutar(() async {
        final r = await ApiService.post('/cuentas-contables/copiar/', {'negocio': widget.negocioId, 'origen': 'plantilla'});
        if (r.statusCode != 200 && !(r.statusCode == 400 && utf8.decode(r.bodyBytes).contains('errores'))) {
          throw Exception(ApiService.mensajeError(r));
        }
        await _mostrarResultado(json.decode(utf8.decode(r.bodyBytes)), "Copiado de tu plantilla");
      });

  Future<void> _guardarComoPlantilla() => _ejecutar(() async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Guardar como mi plantilla"),
            content: Text("Tu plantilla de cuentas se reemplaza por el catálogo de ${widget.negocioNombre} "
                "(${_cuentas.length} cuentas). Después la podés copiar a cualquier cliente."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
            ],
          ),
        );
        if (ok != true) return;
        final r = ApiService.verificar(await ApiService.post('/cuentas-contables/plantilla/', {'negocio': widget.negocioId}));
        _avisar("Plantilla guardada con ${json.decode(utf8.decode(r.bodyBytes))['guardadas']} cuentas.");
      });

  Widget _menuAcciones() => PopupMenuButton<String>(
        icon: _procesando
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.more_vert, color: TemaContador.textoFuerte),
        enabled: !_procesando,
        tooltip: "Más acciones",
        onSelected: (v) {
          switch (v) {
            case 'estandar':
              _sembrarCatalogo();
            case 'cliente':
              _copiarDesdeCliente();
            case 'plantilla':
              _copiarDesdePlantilla();
            case 'guardar_plantilla':
              _guardarComoPlantilla();
            case 'importar':
              _importarExcel();
            case 'exportar':
              _exportarExcel();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'estandar', child: ListTile(leading: Icon(Icons.playlist_add_check), title: Text("Cargar catálogo estándar de CR"))),
          const PopupMenuItem(value: 'plantilla', child: ListTile(leading: Icon(Icons.bookmark_added_outlined), title: Text("Copiar desde mi plantilla"))),
          const PopupMenuItem(value: 'cliente', child: ListTile(leading: Icon(Icons.copy_all_outlined), title: Text("Copiar desde otro cliente"))),
          if (_cuentas.isNotEmpty)
            const PopupMenuItem(value: 'guardar_plantilla', child: ListTile(leading: Icon(Icons.bookmark_add_outlined), title: Text("Guardar como mi plantilla"))),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'importar', child: ListTile(leading: Icon(Icons.upload_file), title: Text("Importar desde Excel"))),
          PopupMenuItem(
            value: 'exportar',
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(_cuentas.isEmpty ? "Descargar formato de Excel" : "Exportar a Excel"),
            ),
          ),
        ],
      );

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
        actions: [_menuAcciones()],
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton.icon(onPressed: _procesando ? null : _copiarDesdePlantilla, icon: const Icon(Icons.bookmark_added_outlined), label: const Text("Desde mi plantilla")),
                          OutlinedButton.icon(onPressed: _procesando ? null : _copiarDesdeCliente, icon: const Icon(Icons.copy_all_outlined), label: const Text("Desde otro cliente")),
                          OutlinedButton.icon(onPressed: _procesando ? null : _importarExcel, icon: const Icon(Icons.upload_file), label: const Text("Importar Excel")),
                        ],
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
                      child: _visibles.isEmpty
                          ? Center(
                              child: Text("Ninguna cuenta coincide con \"$_busqueda\".", style: const TextStyle(color: Colors.grey)),
                            )
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: Builder(builder: (context) {
                                // Una sola vez por construcción, no por fila.
                                final visibles = _visibles;
                                final niveles = nivelesCatalogo(_cuentas);
                                final conHijas = {for (final h in _cuentas) if (h.cuentaPadre != null) h.cuentaPadre!};
                                return ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                itemCount: visibles.length,
                                itemBuilder: (context, index) {
                                  final c = visibles[index];
                                  final nivel = niveles[c.id] ?? 0;
                                  final tieneHijas = conHijas.contains(c.id);
                                  final plegada = _plegadas.contains(c.id);
                                  return Card(
                                    margin: EdgeInsets.only(bottom: 6, left: 18.0 * nivel),
                                    color: c.esDetalle ? TemaContador.superficie : TemaContador.fondo,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.esDetalle ? TemaContador.borde : TemaContador.acento.withOpacity(0.3))),
                                    child: ListTile(
                                      dense: !c.esDetalle,
                                      leading: tieneHijas
                                          ? IconButton(
                                              visualDensity: VisualDensity.compact,
                                              tooltip: plegada ? "Mostrar subcuentas" : "Ocultar subcuentas",
                                              icon: Icon(plegada ? Icons.chevron_right : Icons.expand_more, color: TemaContador.acento),
                                              onPressed: () => setState(() => plegada ? _plegadas.remove(c.id) : _plegadas.add(c.id!)),
                                            )
                                          : Icon(c.esDetalle ? Icons.description_outlined : Icons.folder_outlined, color: c.esDetalle ? TemaContador.textoTenue : TemaContador.acento, size: 20),
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
                                          if (!c.esDetalle)
                                            IconButton(
                                              tooltip: "Agregar subcuenta",
                                              icon: const Icon(Icons.add_circle_outline, size: 19, color: TemaContador.acento),
                                              onPressed: () => _abrirFormulario(padre: c),
                                            ),
                                          IconButton(icon: const Icon(Icons.edit_outlined, size: 19, color: TemaContador.textoTenue), onPressed: () => _abrirFormulario(cuenta: c)),
                                          IconButton(icon: const Icon(Icons.delete_outline, size: 19, color: TemaContador.textoTenue), onPressed: () => _eliminar(c)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                              }),
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
  final CuentaContable? padreInicial;
  final List<CuentaContable> cuentasDisponibles;

  const _FormularioCuentaDialog({required this.negocioId, this.cuenta, this.padreInicial, required this.cuentasDisponibles});

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
    } else if (widget.padreInicial != null) {
      _aplicarPadre(widget.padreInicial);
    }
  }

  /// Subcuenta nueva: hereda tipo y naturaleza de su cuenta de mayor y se
  /// le propone el siguiente código libre (se puede cambiar).
  void _aplicarPadre(CuentaContable? padre) {
    _cuentaPadre = padre?.id;
    if (widget.cuenta != null || padre == null) return;
    _tipo = padre.tipo;
    _naturaleza = padre.naturaleza;
    _codigoCtrl.text = siguienteCodigo(padre, widget.cuentasDisponibles);
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
                onChanged: (v) => setState(() => _aplicarPadre(
                      v == null ? null : widget.cuentasDisponibles.firstWhere((c) => c.id == v),
                    )),
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
