import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'cabys_picker.dart';
import 'impuesto.dart';
import 'negocio.dart';
import 'producto.dart';

class CrearProductoScreen extends StatefulWidget {
  final Negocio negocio;
  final Producto? productoAEditar;

  const CrearProductoScreen({
    super.key,
    required this.negocio,
    this.productoAEditar,
  });

  @override
  State<CrearProductoScreen> createState() => _CrearProductoScreenState();
}

class _CrearProductoScreenState extends State<CrearProductoScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreCtrl;
  late TextEditingController _cabysCtrl;
  String _cabysDescripcion = '';
  late TextEditingController _costoCtrl;
  late TextEditingController _margenCtrl;
  late TextEditingController _precioCtrl;
  late TextEditingController _stockCtrl;

  List<Categoria> _categorias = [];
  List<Impuesto> _impuestos = [];

  int? _categoriaSeleccionada;
  Impuesto? _impuestoSeleccionado;
  String _unidadSeleccionada = 'Unid';
  String _tipoSeleccionado = 'mercancia';
  bool _cargandoInicial = true;
  bool _guardando = false;

  Uint8List? _imagenBytes;
  String? _imagenNombre;
  String? _imagenUrlActual;

  List<PresentacionProducto> _presentaciones = [];

  @override
  void initState() {
    super.initState();
    final p = widget.productoAEditar;
    _nombreCtrl = TextEditingController(text: p?.nombre ?? '');
    _cabysCtrl = TextEditingController(text: p?.codigoCabys ?? '');
    _costoCtrl = TextEditingController(text: p != null ? p.costo.toStringAsFixed(2) : '');
    _margenCtrl = TextEditingController(text: (p?.margenGanancia ?? 30).toStringAsFixed(0));
    _precioCtrl = TextEditingController(text: p != null ? p.precioUnitario.toString() : '');
    _stockCtrl = TextEditingController(text: p != null ? p.stock.toString() : '0');
    _categoriaSeleccionada = p?.categoriaId;
    _unidadSeleccionada = unidadesMedidaHacienda.containsKey(p?.unidadMedida) ? p!.unidadMedida : 'Unid';
    _tipoSeleccionado = tiposProducto.containsKey(p?.tipo) ? p!.tipo : 'mercancia';
    _imagenUrlActual = p?.imagenUrl;
    _presentaciones = List.of(p?.presentaciones ?? []);

    _costoCtrl.addListener(_recalcularPrecioDesdeMargen);
    _margenCtrl.addListener(_recalcularPrecioDesdeMargen);
    _precioCtrl.addListener(_recalcularMargenDesdePrecio);

    _cargarCatalogos();
    if (_cabysCtrl.text.trim().isNotEmpty) {
      _buscarDescripcionCabysExistente(_cabysCtrl.text.trim());
    }
  }

  /// Al editar un producto ya guardado, solo tenemos el código -- buscamos
  /// su descripción en el catálogo para mostrarla (si el código es viejo e
  /// inválido, simplemente no aparece y se queda mostrando el código solo).
  Future<void> _buscarDescripcionCabysExistente(String codigo) async {
    try {
      final resultados = await buscarCabys(codigo);
      final coincidencias = resultados.where((r) => r.codigo == codigo);
      if (coincidencias.isNotEmpty && mounted) {
        setState(() => _cabysDescripcion = coincidencias.first.descripcion);
      }
    } catch (_) {
      // Sin conexion: se queda mostrando el código solo, no es bloqueante.
    }
  }

  Future<void> _abrirBuscadorCabys() async {
    final seleccionado = await mostrarBuscadorCabys(context);
    if (seleccionado != null) {
      setState(() {
        _cabysCtrl.text = seleccionado.codigo;
        _cabysDescripcion = seleccionado.descripcion;
      });
    }
  }

  // Evita que un cambio programático (hecho por estos mismos métodos) vuelva
  // a disparar el listener del otro campo y se genere un ciclo infinito.
  bool _sincronizando = false;

  /// Precio = Costo + (Costo × Margen%). Se usa cuando cambia el costo o el
  /// porcentaje de ganancia (el margen se conserva, el precio se ajusta).
  void _recalcularPrecioDesdeMargen() {
    if (_sincronizando) return;
    final costo = double.tryParse(_costoCtrl.text.replaceAll(',', '.').trim());
    final margen = double.tryParse(_margenCtrl.text.replaceAll(',', '.').trim());
    if (costo == null || margen == null) return;
    final nuevoPrecio = costo * (1 + margen / 100);
    _sincronizando = true;
    _precioCtrl.text = nuevoPrecio.toStringAsFixed(2);
    _sincronizando = false;
  }

  /// Margen% = (Precio / Costo - 1) × 100. Se usa cuando el precio se edita
  /// directamente a mano (el costo se conserva, el margen se ajusta).
  void _recalcularMargenDesdePrecio() {
    if (_sincronizando) return;
    final costo = double.tryParse(_costoCtrl.text.replaceAll(',', '.').trim());
    final precio = double.tryParse(_precioCtrl.text.replaceAll(',', '.').trim());
    if (costo == null || precio == null || costo <= 0) return;
    final nuevoMargen = ((precio / costo) - 1) * 100;
    _sincronizando = true;
    _margenCtrl.text = nuevoMargen.toStringAsFixed(2);
    _sincronizando = false;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cabysCtrl.dispose();
    _costoCtrl.dispose();
    _margenCtrl.dispose();
    _precioCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogos() async {
    try {
      final respImp = await ApiService.get('/impuestos/');
      final respCat = await ApiService.get('/categorias/?negocio=${widget.negocio.id}');

      List<Impuesto> impuestosCargados = [];
      List<Categoria> categoriasCargadas = [];

      if (respImp.statusCode == 200) {
        List dataImp = json.decode(utf8.decode(respImp.bodyBytes));
        impuestosCargados = dataImp.map((x) => Impuesto.fromJson(x)).toList();
      }

      if (respCat.statusCode == 200) {
        List dataCat = json.decode(utf8.decode(respCat.bodyBytes));
        categoriasCargadas = dataCat.map((x) => Categoria.fromJson(x)).toList();
      }

      setState(() {
        _impuestos = impuestosCargados;
        _categorias = categoriasCargadas;

        if (widget.productoAEditar?.impuesto != null) {
          _impuestoSeleccionado = _impuestos.firstWhere(
                (imp) => imp.id == widget.productoAEditar!.impuesto!.id,
            orElse: () => _impuestos.first,
          );
        } else if (_impuestos.isNotEmpty) {
          _impuestoSeleccionado = _impuestos.first;
        }

        _cargandoInicial = false;
      });
    } catch (e) {
      setState(() => _cargandoInicial = false);
    }
  }

  Future<void> _agregarPresentacion() async {
    final nombreCtrl = TextEditingController();
    final equivalenciaCtrl = TextEditingController();
    final formKeyDialog = GlobalKey<FormState>();

    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva presentación'),
        content: Form(
          key: formKeyDialog,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre (ej. Caja, Docena, Saco)',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: equivalenciaCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Trae cuántos $_unidadSeleccionada',
                  helperText: 'Ej. 20 si una Caja trae 20 $_unidadSeleccionada',
                ),
                validator: (v) => double.tryParse((v ?? '').replaceAll(',', '.')) == null ? 'Número inválido' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKeyDialog.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (resultado != true) return;

    try {
      final response = await ApiService.post('/presentaciones-producto/', {
        'producto': widget.productoAEditar!.id,
        'nombre': nombreCtrl.text.trim(),
        'equivalencia': double.parse(equivalenciaCtrl.text.replaceAll(',', '.').trim()),
      });
      if (response.statusCode == 201) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() => _presentaciones.add(PresentacionProducto.fromJson(data)));
      } else {
        throw Exception('Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la presentación: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _eliminarPresentacion(PresentacionProducto p) async {
    try {
      final response = await ApiService.delete('/presentaciones-producto/${p.id}/');
      if (response.statusCode == 204) {
        setState(() => _presentaciones.removeWhere((x) => x.id == p.id));
      } else {
        throw Exception('Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _elegirImagen() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
    );
    if (resultado != null && resultado.files.single.bytes != null) {
      setState(() {
        _imagenBytes = resultado.files.single.bytes;
        _imagenNombre = resultado.files.single.name;
      });
    }
  }

  /// Busca fotos de referencia en internet (Openverse, con licencia que
  /// permite uso comercial) y deja elegir una entre varias opciones -- la
  /// descarga la trae el backend (ver DescargarImagenExternaView, evita
  /// depender de si el navegador puede leer los bytes de un origen
  /// externo) y queda en _imagenBytes exactamente igual que si se hubiera
  /// elegido con el selector de archivos de siempre.
  Future<void> _buscarImagenEnInternet() async {
    final urlElegida = await showDialog<String>(
      context: context,
      builder: (ctx) => _DialogoBuscarImagen(consultaInicial: _nombreCtrl.text.trim()),
    );
    if (urlElegida == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text("Descargando imagen..."))]),
      ),
    );
    try {
      final resp = await ApiService.post('/productos/descargar-imagen-externa/', {'url': urlElegida});
      if (mounted) Navigator.pop(context); // cierra "Descargando..."
      if (resp.statusCode != 200) {
        final detalle = jsonDecode(utf8.decode(resp.bodyBytes))['detail'] ?? 'No se pudo descargar la imagen.';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detalle)));
        return;
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      setState(() {
        _imagenBytes = base64Decode(data['bytes_base64']);
        _imagenNombre = data['nombre_archivo'];
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _guardarProducto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    // 📌 Pasamos el Map directamente a ApiService sin usar jsonEncode
    final Map<String, dynamic> datos = {
      'negocio': widget.negocio.id,
      'nombre': _nombreCtrl.text.trim(),
      'codigo_cabys': _cabysCtrl.text.trim(),
      'unidad_medida': _unidadSeleccionada,
      'tipo': _tipoSeleccionado,
      'precio_unitario': double.parse(_precioCtrl.text.trim()),
      'costo': double.tryParse(_costoCtrl.text.replaceAll(',', '.').trim()) ?? 0,
      'margen_ganancia': double.tryParse(_margenCtrl.text.replaceAll(',', '.').trim()) ?? 30,
      'stock': int.tryParse(_stockCtrl.text.trim()) ?? 0,
      'categoria': _categoriaSeleccionada,
      'impuesto': _impuestoSeleccionado?.id,
    };

    try {
      bool esEdicion = widget.productoAEditar != null;
      final response = esEdicion
          ? await ApiService.put('/productos/${widget.productoAEditar!.id}/', datos)
          : await ApiService.post('/productos/', datos);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (_imagenBytes != null) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          final int productoId = data['id'];
          final imgResponse = await ApiService.uploadBytes(
            '/productos/$productoId/',
            'imagen',
            _imagenBytes!,
            _imagenNombre ?? 'producto.jpg',
          );
          if (imgResponse.statusCode != 200) {
            throw Exception("El producto se guardó, pero la imagen no se pudo subir (${imgResponse.statusCode})");
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(esEdicion ? "Producto actualizado correctamente" : "Producto guardado con éxito"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception("Error ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _buildSeccionPresentaciones(bool esEdicion) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Presentaciones / Empaques', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (esEdicion)
                TextButton.icon(
                  onPressed: _agregarPresentacion,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
            ],
          ),
          if (!esEdicion)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Guardá el producto primero para poder agregar presentaciones (ej. Caja, Docena, Saco).',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else if (_presentaciones.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Sin presentaciones registradas. Se usan para interpretar notas escritas a mano (ej. "1 caja") con la unidad real del inventario.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presentaciones.map((p) {
                  return Chip(
                    label: Text('${p.nombre} = ${p.equivalencia} $_unidadSeleccionada'),
                    onDeleted: () => _eliminarPresentacion(p),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool esEdicion = widget.productoAEditar != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? "Editar Producto" : "Nuevo Producto"),
      ),
      body: _cargandoInicial
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _imagenBytes != null
                          ? Image.memory(_imagenBytes!, fit: BoxFit.cover)
                          : (_imagenUrlActual != null && _imagenUrlActual!.isNotEmpty)
                              ? Image.network(
                                  _imagenUrlActual!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.image_outlined, size: 56, color: Colors.grey),
                                )
                              : const Icon(Icons.image_outlined, size: 56, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _elegirImagen,
                          icon: const Icon(Icons.upload_outlined),
                          label: Text(_imagenBytes == null && (_imagenUrlActual == null || _imagenUrlActual!.isEmpty)
                              ? "Agregar imagen"
                              : "Cambiar imagen"),
                        ),
                        OutlinedButton.icon(
                          onPressed: _buscarImagenEnInternet,
                          icon: const Icon(Icons.travel_explore_outlined),
                          label: const Text("Buscar en internet"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: "Nombre del Producto *",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? "El nombre es obligatorio" : null,
              ),
              const SizedBox(height: 16),
              FormField<String>(
                initialValue: _cabysCtrl.text,
                validator: (val) => _cabysCtrl.text.trim().isEmpty ? "Elegí un código CABYS" : null,
                builder: (field) => InkWell(
                  onTap: _abrirBuscadorCabys,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: "Código CABYS *",
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.qr_code_2),
                      suffixIcon: const Icon(Icons.search),
                      errorText: field.errorText,
                      helperText: _cabysCtrl.text.trim().isEmpty
                          ? "Tocá para buscar en el catálogo de Hacienda"
                          : null,
                    ),
                    child: Text(
                      _cabysCtrl.text.trim().isEmpty
                          ? "Buscar código CABYS..."
                          : (_cabysDescripcion.isNotEmpty ? _cabysDescripcion : _cabysCtrl.text),
                      style: _cabysCtrl.text.trim().isEmpty
                          ? TextStyle(color: Theme.of(context).hintColor)
                          : null,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _unidadSeleccionada,
                decoration: const InputDecoration(
                  labelText: "Unidad de Medida *",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.straighten_outlined),
                ),
                items: unidadesMedidaHacienda.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text("${e.key} - ${e.value}")))
                    .toList(),
                onChanged: (val) => setState(() => _unidadSeleccionada = val!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _tipoSeleccionado,
                decoration: const InputDecoration(
                  labelText: "Tipo *",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                  helperText: "Hacienda lo reporta distinto en la factura según sea bien o servicio",
                ),
                items: tiposProducto.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (val) => setState(() => _tipoSeleccionado = val!),
              ),
              const SizedBox(height: 16),
              _buildSeccionPresentaciones(esEdicion),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costoCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Costo (₡)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.point_of_sale_outlined),
                        helperText: "Lo que te cuesta",
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _margenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "% Ganancia",
                        suffixText: "%",
                        border: OutlineInputBorder(),
                        helperText: "30% por defecto",
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _precioCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Precio Unitario (₡) *",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                        helperText: "Se calcula solo; edítalo si quieres otro precio",
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return "Ingrese el precio";
                        if (double.tryParse(val) == null) return "Número inválido";
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Stock Inicial",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Dropdown de Impuestos usando .toString() dinámico de la clase Impuesto
              DropdownButtonFormField<Impuesto>(
                value: _impuestoSeleccionado,
                decoration: const InputDecoration(
                  labelText: "Tarifa / Impuesto IVA *",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
                items: _impuestos.map((imp) {
                  return DropdownMenuItem<Impuesto>(
                    value: imp,
                    child: Text(imp.toString()), // Muestra la representación de Impuesto definida en el modelo
                  );
                }).toList(),
                onChanged: (val) => setState(() => _impuestoSeleccionado = val),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _categoriaSeleccionada,
                decoration: const InputDecoration(
                  labelText: "Categoría (Opcional)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categorias.map((cat) {
                  return DropdownMenuItem<int>(
                    value: cat.id,
                    child: Text(cat.nombre),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _categoriaSeleccionada = val),
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarProducto,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _guardando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(
                  _guardando ? "Guardando..." : (esEdicion ? "ACTUALIZAR PRODUCTO" : "GUARDAR PRODUCTO"),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialogo de busqueda: texto + grilla de miniaturas para elegir. Devuelve
/// (via Navigator.pop) la URL completa de la imagen elegida, o null si se
/// cancela -- quien llama (_buscarImagenEnInternet) es quien realmente la
/// descarga.
class _DialogoBuscarImagen extends StatefulWidget {
  final String consultaInicial;
  const _DialogoBuscarImagen({required this.consultaInicial});

  @override
  State<_DialogoBuscarImagen> createState() => _DialogoBuscarImagenState();
}

class _DialogoBuscarImagenState extends State<_DialogoBuscarImagen> {
  late final TextEditingController _consultaCtrl;
  bool _buscando = false;
  String? _error;
  List<Map<String, dynamic>> _resultados = [];

  @override
  void initState() {
    super.initState();
    _consultaCtrl = TextEditingController(text: widget.consultaInicial);
    if (widget.consultaInicial.isNotEmpty) _buscar();
  }

  @override
  void dispose() {
    _consultaCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final q = _consultaCtrl.text.trim();
    if (q.length < 2) return;
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      final resp = await ApiService.get('/productos/buscar-imagen/?q=${Uri.encodeQueryComponent(q)}');
      if (!mounted) return;
      if (resp.statusCode != 200) {
        final detalle = jsonDecode(utf8.decode(resp.bodyBytes))['detail'] ?? 'No se pudo buscar.';
        setState(() {
          _error = detalle;
          _resultados = [];
        });
        return;
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      setState(() {
        _resultados = List<Map<String, dynamic>>.from(data['resultados'] ?? []);
        if (_resultados.isEmpty) _error = "No se encontraron imágenes para \"$q\".";
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Error: $e");
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Buscar imagen en internet"),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _consultaCtrl,
                    decoration: const InputDecoration(
                      hintText: "Ej: canela en polvo",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _buscando ? null : _buscar,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Fotos con licencia de uso comercial (Openverse).",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buscando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)))
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _resultados.length,
                          itemBuilder: (context, i) {
                            final r = _resultados[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => Navigator.pop(context, r['url'] as String),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  (r['miniatura'] ?? r['url']) as String,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(color: Colors.grey.shade200, child: const Icon(Icons.broken_image_outlined, color: Colors.grey)),
                                  loadingBuilder: (context, child, progreso) =>
                                      progreso == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))],
    );
  }
}