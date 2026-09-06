import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'api_service.dart';

class CabysResultado {
  final String codigo;
  final String descripcion;

  CabysResultado({required this.codigo, required this.descripcion});

  factory CabysResultado.fromJson(Map<String, dynamic> json) => CabysResultado(
        codigo: json['codigo'] ?? '',
        descripcion: json['descripcion'] ?? '',
      );
}

/// Busca en el catalogo CABYS real de Hacienda (cacheado en el backend desde
/// Alanube). Reemplaza el texto libre de antes -- un codigo CABYS invalido
/// hace que Hacienda rechace la factura entera.
Future<List<CabysResultado>> buscarCabys(String texto) async {
  if (texto.trim().length < 2) return [];
  final resp = await ApiService.get('/cabys/?q=${Uri.encodeQueryComponent(texto.trim())}');
  if (resp.statusCode != 200) return [];
  final List data = json.decode(utf8.decode(resp.bodyBytes));
  return data.map((e) => CabysResultado.fromJson(e)).toList();
}

Future<CabysResultado?> mostrarBuscadorCabys(BuildContext context) {
  return showDialog<CabysResultado>(
    context: context,
    builder: (context) => const _CabysBuscarDialog(),
  );
}

class _CabysBuscarDialog extends StatefulWidget {
  const _CabysBuscarDialog();

  @override
  State<_CabysBuscarDialog> createState() => _CabysBuscarDialogState();
}

class _CabysBuscarDialogState extends State<_CabysBuscarDialog> {
  final _queryCtrl = TextEditingController();
  Timer? _debounce;
  List<CabysResultado> _resultados = [];
  bool _buscando = false;

  void _onChanged(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _buscar(texto));
  }

  Future<void> _buscar(String texto) async {
    setState(() => _buscando = true);
    try {
      final resultados = await buscarCabys(texto);
      if (mounted) setState(() => _resultados = resultados);
    } catch (_) {
      // Sin conexion o error del servidor: se deja la lista como estaba.
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Buscar código CABYS", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _queryCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "Nombre del producto o código",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscando
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
                onChanged: _onChanged,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _resultados.isEmpty
                    ? Center(
                        child: Text(
                          _queryCtrl.text.trim().length < 2 ? "Escribí al menos 2 letras" : "Sin resultados",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _resultados.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _resultados[i];
                          return ListTile(
                            title: Text(r.descripcion),
                            subtitle: Text(r.codigo),
                            onTap: () => Navigator.pop(context, r),
                          );
                        },
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
