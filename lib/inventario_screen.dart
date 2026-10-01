import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'crear_producto.dart';
import 'movimientos_producto.dart';
import 'negocio.dart';
import 'producto.dart';
import 'formato.dart';
import 'actualizar_precios_screen.dart' show PantallaActualizarPrecios;
import 'importar_externo_dialog.dart';

class InventarioScreen extends StatefulWidget {
  final Negocio negocio;
  const InventarioScreen({super.key, required this.negocio});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> with SingleTickerProviderStateMixin {
  bool _cargando = true;
  String? _error;
  List<Producto> _productos = [];
  List<Categoria> _categorias = [];

  // Controlador para el buscador
  final TextEditingController _searchCtrl = TextEditingController();
  String _filtro = "";

  // Antes "Crear Nuevo Producto"/"Actualizar Precios"/"Cargar Productos
  // Masivamente"/"Crear Nueva Categoría" eran botones enteros apilados
  // arriba de la lista -- con eso, en una pantalla angosta la lista de
  // productos quedaba casi sin espacio (había que scrollear adentro de un
  // area chiquita para ver algo). Ahora "Crear..." es un FAB (que cambia
  // segun la pestaña activa) y las acciones secundarias pasan al AppBar,
  // dejando practicamente toda la pantalla para la lista.
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
    // Escuchar cambios en el buscador para filtrar en tiempo real
    _searchCtrl.addListener(() {
      setState(() {
        _filtro = _searchCtrl.text.toLowerCase().trim();
      });
    });
    _cargarDatos();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final resProd = await ApiService.get('/productos/?negocio=${widget.negocio.id}');
      final resCat = await ApiService.get('/categorias/?negocio=${widget.negocio.id}');

      if (resProd.statusCode == 200 && resCat.statusCode == 200) {
        final List productosData = json.decode(utf8.decode(resProd.bodyBytes));
        final List categoriasData = json.decode(utf8.decode(resCat.bodyBytes));

        if (!mounted) return;
        setState(() {
          _productos = productosData.map((j) => Producto.fromJson(j)).toList();
          _categorias = categoriasData.map((j) => Categoria.fromJson(j)).toList();
          _cargando = false;
        });
      } else {
        throw Exception('Error del servidor (Prod: ${resProd.statusCode}, Cat: ${resCat.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  void _abrirActualizarPrecios() {
    Future.microtask(() async {
      if (!mounted || _productos.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PantallaActualizarPrecios(productos: _productos),
        ),
      );
      if (mounted) _cargarDatos();
    });
  }

  void _abrirCrearProducto() {
    Future.microtask(() async {
      if (!mounted) return;
      final bool? refresh = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CrearProductoScreen(negocio: widget.negocio),
        ),
      );

      if (mounted && refresh == true) {
        _cargarDatos();
      }
    });
  }

  void _abrirEditarProducto(Producto producto) {
    Future.microtask(() async {
      if (!mounted) return;
      final bool? refresh = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CrearProductoScreen(negocio: widget.negocio, productoAEditar: producto),
        ),
      );

      if (mounted && refresh == true) {
        _cargarDatos();
      }
    });
  }

  void _mostrarDialogoEditarStock(Producto producto) {
    Future.microtask(() async {
      if (!mounted) return;
      final controller = TextEditingController(text: producto.stock.toString());

      final bool? actualizado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text("Editar stock: ${producto.nombre}"),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Unidades disponibles",
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.numbers),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancelar"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () async {
                  final nuevoStock = int.tryParse(controller.text);
                  if (nuevoStock == null) return;

                  Map<String, dynamic> datosActualizados = {
                    'id': producto.id,
                    'nombre': producto.nombre,
                    'codigo_cabys': producto.codigoCabys,
                    'precio_unitario': producto.precioUnitario,
                    'stock': nuevoStock,
                    'negocio': widget.negocio.id,
                    if (producto.categoriaId != null) 'categoria': producto.categoriaId,
                    if (producto.impuesto != null) 'impuesto': producto.impuesto!.id,
                  };

                  final response = await ApiService.put(
                    '/productos/${producto.id}/',
                    datosActualizados,
                  );

                  if (response.statusCode == 200 || response.statusCode == 204) {
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } else {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text("Error al actualizar: ${response.statusCode}")),
                      );
                    }
                  }
                },
                child: const Text("Guardar", style: TextStyle(color: Colors.black)),
              ),
            ],
          );
        },
      );

      if (mounted && actualizado == true) {
        _cargarDatos();
      }
    });
  }

  void _eliminarProducto(Producto producto) {
    Future.microtask(() async {
      if (!mounted) return;
      final bool? confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("Eliminar producto"),
          content: Text("¿Seguro que querés eliminar \"${producto.nombre}\"? Esta acción no se puede deshacer."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmar != true || !mounted) return;

      try {
        final response = await ApiService.delete('/productos/${producto.id}/');
        if (response.statusCode == 204 || response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("\"${producto.nombre}\" eliminado"), backgroundColor: Colors.green),
            );
            _cargarDatos();
          }
        } else {
          String mensaje = "No se pudo eliminar el producto.";
          try {
            final data = json.decode(utf8.decode(response.bodyBytes));
            if (data is Map && data['detail'] != null) mensaje = data['detail'];
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error al eliminar: $e"), backgroundColor: Colors.red),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool enProductos = _tabController.index == 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestión de Inventario"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          IconButton(
            tooltip: "Actualizar Precios",
            icon: const Icon(Icons.price_change_outlined),
            onPressed: _productos.isEmpty ? null : _abrirActualizarPrecios,
          ),
          IconButton(
            tooltip: "Cargar Productos Masivamente",
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => importarProductosMasivo(
              context: context,
              negocio: widget.negocio,
              onImportado: _cargarDatos,
            ),
          ),
        ],
        bottom: PreferredSize(
          // Antes cada Tab tenia icono arriba + texto abajo (mas alto, mas
          // "gritado") y el indicador ocupaba todo el ancho de la pestaña
          // -- version mas chica y discreta: solo texto, subrayado fino
          // debajo de la palabra en vez de toda la pestaña.
          preferredSize: const Size.fromHeight(38),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.textStrong,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.normal),
            tabs: const [
              Tab(height: 38, text: "Productos"),
              Tab(height: 38, text: "Categorías"),
            ],
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 10),
              Text(
                "Error al cargar inventario:\n$_error",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: _cargarDatos,
                child: const Text("Reintentar"),
              )
            ],
          ),
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          _buildVistaProductos(),
          _buildListaCategorias(),
        ],
      ),
      floatingActionButton: (_cargando || _error != null)
          ? null
          : FloatingActionButton.extended(
              heroTag: 'crear-inventario',
              onPressed: enProductos ? _abrirCrearProducto : () => _mostrarFormularioCategoria(),
              icon: const Icon(Icons.add),
              label: Text(enProductos ? "Nuevo Producto" : "Nueva Categoría"),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
            ),
    );
  }

  Widget _buildVistaProductos() {
    // 1. Filtrar productos por nombre
    final List<Producto> filtrados = _productos.where((p) {
      return p.nombre.toLowerCase().contains(_filtro);
    }).toList();

    // 2. Ordenar alfabéticamente
    filtrados.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: "Buscar producto por nombre...",
                    prefixIcon: Icon(Icons.search, color: AppColors.primary),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${filtrados.length}",
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtrados.isEmpty
              ? Center(
                  child: Text(_filtro.isEmpty 
                    ? "No hay productos registrados." 
                    : "No se encontraron productos con '$_filtro'"))
              // Antes cada fila era una Card con 3 lineas de subtitulo + 3
              // botones de accion separados (~110px de alto cada una) --
              // con un catalogo de decenas/cientos de productos (como el
              // que ahora se puede cargar masivamente) eso obligaba a
              // scrollear muchisimo para ver algo. Una fila delgada de una
              // sola linea de subtitulo + un solo menu de acciones deja
              // ver varias veces mas productos por pantalla sin scrollear.
              : ListView.separated(
            itemCount: filtrados.length,
            padding: const EdgeInsets.symmetric(vertical: 4),
            separatorBuilder: (context, i) => Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
            itemBuilder: (context, i) {
              final p = filtrados[i];
              final bool tieneImagen = p.imagenUrl != null && p.imagenUrl!.isNotEmpty;
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 40,
                    height: 40,
                    color: AppColors.primary.withOpacity(0.12),
                    child: tieneImagen
                        ? Image.network(
                            p.imagenUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
                          )
                        : Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
                  ),
                ),
                title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  "${p.monedaPrecio == 'USD' ? formatearDolares(p.precioUnitario) : formatearColones(p.precioUnitario)} · ${p.nombreCategoria ?? 'Sin Categoría'}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                onTap: () => _abrirEditarProducto(p),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (p.stock > 0 ? AppColors.primary : Colors.red.shade400).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${formatearNumero(p.stock, decimales: 0)} ${p.unidadMedida}",
                        style: TextStyle(
                          color: p.stock > 0 ? AppColors.primary : Colors.red.shade400,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: AppColors.textMuted),
                      onSelected: (valor) {
                        if (valor == 'editar') {
                          _abrirEditarProducto(p);
                        } else if (valor == 'stock') {
                          _mostrarDialogoEditarStock(p);
                        } else if (valor == 'movimientos') {
                          Future.microtask(() {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => MovimientosProductoScreen(producto: p)),
                            );
                          });
                        } else if (valor == 'eliminar') {
                          _eliminarProducto(p);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'editar', child: Text("Editar producto")),
                        PopupMenuItem(value: 'stock', child: Text("Editar solo stock")),
                        PopupMenuItem(value: 'movimientos', child: Text("Movimientos")),
                        PopupMenuItem(value: 'eliminar', child: Text("Eliminar")),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _mostrarFormularioCategoria({Categoria? categoria}) {
    final nombreCtrl = TextEditingController(text: categoria?.nombre ?? '');
    bool guardando = false;

    Future.microtask(() async {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setStateDialog) => AlertDialog(
            title: Text(categoria == null ? "Nueva Categoría" : "Editar Categoría"),
            content: TextField(
              controller: nombreCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Nombre *", border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(
                onPressed: guardando ? null : () => Navigator.pop(dialogContext),
                child: const Text("Cancelar"),
              ),
              ElevatedButton(
                onPressed: guardando
                    ? null
                    : () async {
                        final nombre = nombreCtrl.text.trim();
                        if (nombre.isEmpty) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text("El nombre es obligatorio")),
                          );
                          return;
                        }
                        setStateDialog(() => guardando = true);
                        try {
                          final body = {'negocio': widget.negocio.id, 'nombre': nombre};
                          final response = categoria == null
                              ? await ApiService.post('/categorias/', body)
                              : await ApiService.put('/categorias/${categoria.id}/', body);
                          if (response.statusCode == 200 || response.statusCode == 201) {
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (mounted) _cargarDatos();
                          } else {
                            throw Exception(utf8.decode(response.bodyBytes));
                          }
                        } catch (e) {
                          setStateDialog(() => guardando = false);
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text("Error: $e")),
                            );
                          }
                        }
                      },
                child: guardando
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text("Guardar"),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _eliminarCategoria(Categoria categoria) {
    Future.microtask(() async {
      if (!mounted) return;
      final bool? confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("Eliminar categoría"),
          content: Text(
            "¿Seguro que querés eliminar \"${categoria.nombre}\"? "
            "Los productos que la usan quedarán sin categoría.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancelar")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmar != true || !mounted) return;

      try {
        final response = await ApiService.delete('/categorias/${categoria.id}/');
        if (response.statusCode == 204 || response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("\"${categoria.nombre}\" eliminada"), backgroundColor: Colors.green),
            );
            _cargarDatos();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No se pudo eliminar la categoría."), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error al eliminar: $e"), backgroundColor: Colors.red),
          );
        }
      }
    });
  }

  Widget _buildListaCategorias() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: _categorias.isEmpty
              ? const Center(child: Text("No hay categorías registradas."))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _categorias.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final cat = _categorias[i];
                    return ListTile(
                      leading: const Icon(Icons.folder, color: Colors.orange),
                      title: Text(cat.nombre),
                      onTap: () => _mostrarFormularioCategoria(categoria: cat),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit_outlined, color: AppColors.primary),
                            tooltip: "Editar",
                            onPressed: () => _mostrarFormularioCategoria(categoria: cat),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: "Eliminar",
                            onPressed: () => _eliminarCategoria(cat),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}