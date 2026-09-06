import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'negocio.dart';
import 'tarjeta_lealtad.dart';

class TarjetaLealtadScreen extends StatefulWidget {
  final Negocio negocio;
  const TarjetaLealtadScreen({super.key, required this.negocio});

  @override
  State<TarjetaLealtadScreen> createState() => _TarjetaLealtadScreenState();
}

class _TarjetaLealtadScreenState extends State<TarjetaLealtadScreen> {
  bool _cargando = true;
  List<TarjetaLealtad> _tarjetas = [];
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _busquedaCtrl.addListener(() {
      setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final response = await ApiService.get('/tarjetas-lealtad/?negocio=${widget.negocio.id}');
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as List;
        _tarjetas = data.map((j) => TarjetaLealtad.fromJson(j)).toList();
      }
    } catch (_) {
      // Si falla, simplemente se muestra la lista vacía.
    }
    if (mounted) setState(() => _cargando = false);
  }

  List<TarjetaLealtad> get _tarjetasFiltradas {
    if (_busqueda.isEmpty) return _tarjetas;
    return _tarjetas.where((t) =>
        t.clienteNombre.toLowerCase().contains(_busqueda) ||
        t.clienteCedula.toLowerCase().contains(_busqueda)).toList();
  }

  Future<void> _verMovimientos(TarjetaLealtad tarjeta) async {
    List<MovimientoLealtad> movimientos = [];
    try {
      final response = await ApiService.get('/tarjetas-lealtad/${tarjeta.id}/movimientos/');
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as List;
        movimientos = data.map((j) => MovimientoLealtad.fromJson(j)).toList();
      }
    } catch (_) {}

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Historial - ${tarjeta.clienteNombre}"),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 380, maxHeight: 320),
          child: movimientos.isEmpty
              ? const Center(child: Text("Sin movimientos todavía.", style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  itemCount: movimientos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = movimientos[i];
                    final positivo = m.puntos >= 0;
                    return ListTile(
                      dense: true,
                      title: Text(m.etiquetaTipo),
                      subtitle: Text(m.descripcion.isEmpty ? m.fecha.split('T')[0] : "${m.descripcion} · ${m.fecha.split('T')[0]}"),
                      trailing: Text(
                        "${positivo ? '+' : ''}${m.puntos}",
                        style: TextStyle(fontWeight: FontWeight.bold, color: positivo ? Colors.green : Colors.red),
                      ),
                    );
                  },
                ),
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
      ),
    );
  }

  Future<void> _ajustarPuntos(TarjetaLealtad tarjeta, {required bool canjear}) async {
    final cantidadCtrl = TextEditingController();
    final descripcionCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(canjear ? "Canjear puntos" : "Agregar puntos"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${tarjeta.clienteNombre} tiene ${tarjeta.puntos} puntos.", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: cantidadCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Cantidad de puntos", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descripcionCtrl,
              decoration: InputDecoration(
                labelText: canjear ? "Canjeado por..." : "Motivo (opcional)",
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: canjear ? Colors.red : Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(canjear ? "Canjear" : "Agregar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final cantidad = int.tryParse(cantidadCtrl.text);
    if (cantidad == null || cantidad <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingrese una cantidad válida de puntos.")));
      }
      return;
    }

    try {
      final response = await ApiService.post('/tarjetas-lealtad/${tarjeta.id}/ajustar/', {
        'puntos': canjear ? -cantidad : cantidad,
        'descripcion': descripcionCtrl.text.trim(),
      });
      if (response.statusCode == 200) {
        _cargarDatos();
      } else {
        final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? utf8.decode(response.bodyBytes);
        throw Exception(detalle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo ajustar: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSubtle,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Icon(Icons.loyalty_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                const Text("Tarjeta de Lealtad", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos, tooltip: "Actualizar"),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                hintText: "Buscar cliente por nombre o cédula...",
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _tarjetasFiltradas.isEmpty
                    ? Center(
                        child: Text(
                          _tarjetas.isEmpty ? "Todavía no hay clientes con tarjeta de lealtad." : "No se encontraron clientes con ese criterio.",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: _tarjetasFiltradas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final t = _tarjetasFiltradas[i];
                          return Container(
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                              leading: CircleAvatar(
                                backgroundColor: Colors.amber.withOpacity(0.15),
                                child: const Icon(Icons.card_giftcard, color: Colors.amber),
                              ),
                              title: Text(t.clienteNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(t.clienteCedula, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                    child: Text("${t.puntos} pts", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92700C))),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                                    onSelected: (opcion) {
                                      if (opcion == 'agregar') _ajustarPuntos(t, canjear: false);
                                      if (opcion == 'canjear') _ajustarPuntos(t, canjear: true);
                                      if (opcion == 'historial') _verMovimientos(t);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'agregar', child: ListTile(leading: Icon(Icons.add, color: Colors.green), title: Text("Agregar puntos"), contentPadding: EdgeInsets.zero)),
                                      const PopupMenuItem(value: 'canjear', child: ListTile(leading: Icon(Icons.remove, color: Colors.red), title: Text("Canjear puntos"), contentPadding: EdgeInsets.zero)),
                                      PopupMenuItem(value: 'historial', child: ListTile(leading: Icon(Icons.history, color: AppColors.primary), title: Text("Ver historial"), contentPadding: EdgeInsets.zero)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
