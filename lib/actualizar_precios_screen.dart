import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'formato.dart';
import 'producto.dart';

enum _EstadoFila { inactivo, guardando, guardado, error }

class _FilaPrecio {
  final Producto producto;
  final TextEditingController controller;
  _EstadoFila estado = _EstadoFila.inactivo;
  String? error;

  _FilaPrecio(this.producto)
      : controller = TextEditingController(
          text: producto.precioUnitario.toStringAsFixed(2),
        );

  bool get modificado {
    final nuevo = double.tryParse(controller.text.replaceAll(',', '.').trim());
    if (nuevo == null) return false;
    return redondear2(nuevo) != redondear2(producto.precioUnitario);
  }

  void dispose() => controller.dispose();
}

/// Pantalla de actualización rápida de precios: permite editar el precio de
/// varios productos a la vez y guardarlos todos con un solo botón.
class PantallaActualizarPrecios extends StatefulWidget {
  final List<Producto> productos;
  const PantallaActualizarPrecios({super.key, required this.productos});

  @override
  State<PantallaActualizarPrecios> createState() => _PantallaActualizarPreciosState();
}

class _PantallaActualizarPreciosState extends State<PantallaActualizarPrecios> {
  late List<_FilaPrecio> _filas;
  bool _guardandoTodo = false;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _filas = widget.productos.map((p) => _FilaPrecio(p)).toList();
  }

  @override
  void dispose() {
    for (final fila in _filas) {
      fila.dispose();
    }
    super.dispose();
  }

  List<_FilaPrecio> get _filasFiltradas {
    if (_busqueda.trim().isEmpty) return _filas;
    final q = _busqueda.toLowerCase();
    return _filas.where((f) => f.producto.nombre.toLowerCase().contains(q)).toList();
  }

  Future<bool> _guardarFila(_FilaPrecio fila) async {
    final nuevoPrecio = double.tryParse(fila.controller.text.replaceAll(',', '.').trim());
    if (nuevoPrecio == null || nuevoPrecio < 0) {
      setState(() {
        fila.estado = _EstadoFila.error;
        fila.error = 'Precio inválido';
      });
      return false;
    }

    setState(() {
      fila.estado = _EstadoFila.guardando;
      fila.error = null;
    });

    try {
      final resp = await ApiService.patch(
        '/productos/${fila.producto.id}/',
        {'precio_unitario': redondear2(nuevoPrecio)},
      );
      if (resp.statusCode == 200) {
        setState(() => fila.estado = _EstadoFila.guardado);
        return true;
      } else {
        setState(() {
          fila.estado = _EstadoFila.error;
          fila.error = 'Error del servidor (${resp.statusCode})';
        });
        return false;
      }
    } catch (e) {
      setState(() {
        fila.estado = _EstadoFila.error;
        fila.error = 'Sin conexión';
      });
      return false;
    }
  }

  Future<void> _guardarTodos() async {
    final pendientes = _filas.where((f) => f.modificado).toList();
    if (pendientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios pendientes')),
      );
      return;
    }

    setState(() => _guardandoTodo = true);
    int exitos = 0;
    for (final fila in pendientes) {
      final ok = await _guardarFila(fila);
      if (ok) exitos++;
    }
    setState(() => _guardandoTodo = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$exitos de ${pendientes.length} precios actualizados'),
          backgroundColor: exitos == pendientes.length ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Widget _iconoEstado(_FilaPrecio fila) {
    switch (fila.estado) {
      case _EstadoFila.guardando:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _EstadoFila.guardado:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _EstadoFila.error:
        return Tooltip(
          message: fila.error ?? 'Error',
          child: const Icon(Icons.error, color: Colors.red),
        );
      case _EstadoFila.inactivo:
        return fila.modificado
            ? const Icon(Icons.edit, color: Colors.orange)
            : const SizedBox(width: 18, height: 18);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filasFiltradas;
    final hayPendientes = _filas.any((f) => f.modificado);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Actualizar Precios'),
        backgroundColor: AppColors.surface,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surfaceSubtle,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
          Expanded(
            child: filas.isEmpty
                ? const Center(child: Text('No se encontraron productos'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final fila = filas[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fila.producto.nombre,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Actual: ${formatearColones(fila.producto.precioUnitario)}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: fila.controller,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  prefixText: '₡',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (_) => setState(() {
                                  if (fila.estado != _EstadoFila.guardando) {
                                    fila.estado = _EstadoFila.inactivo;
                                  }
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.save_outlined, color: AppColors.primary),
                              tooltip: 'Guardar este precio',
                              onPressed: fila.estado == _EstadoFila.guardando
                                  ? null
                                  : () => _guardarFila(fila),
                            ),
                            SizedBox(width: 24, child: _iconoEstado(fila)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_guardandoTodo || !hayPendientes) ? null : _guardarTodos,
                icon: _guardandoTodo
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardandoTodo ? 'Guardando...' : 'Guardar Todos los Cambios'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
