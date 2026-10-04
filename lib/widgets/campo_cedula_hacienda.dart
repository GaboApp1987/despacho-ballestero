import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api_service.dart';

/// Campo de cédula que busca solo en Hacienda (GET /consultar-cedula/, ver
/// hacienda_cedula.py en el backend) al terminar de escribirla, o con la
/// lupa: llena [nombreController] (sin pisar lo que la persona escribió a
/// mano) y avisa a [onEncontrado] con todos los datos (tipo de cédula,
/// régimen, actividades) para que cada formulario use lo que necesite.
/// Debajo muestra cómo aparece en Hacienda, o un aviso si no la encontró.
/// Lo usan los formularios de proveedor y de negocio nuevo (el de cliente
/// tiene su propia versión con las actividades para elegir).
class CampoCedulaHacienda extends StatefulWidget {
  final TextEditingController controller;
  final TextEditingController? nombreController;
  final void Function(Map<String, dynamic> datos)? onEncontrado;
  final String labelText;
  final String? Function(String?)? validator;

  const CampoCedulaHacienda({
    super.key,
    required this.controller,
    this.nombreController,
    this.onEncontrado,
    this.labelText = "Cédula",
    this.validator,
  });

  @override
  State<CampoCedulaHacienda> createState() => _CampoCedulaHaciendaState();
}

class _CampoCedulaHaciendaState extends State<CampoCedulaHacienda> {
  Timer? _espera;
  bool _buscando = false;
  String? _consultada;
  Map<String, dynamic>? _datos;
  String? _aviso;
  String? _nombreCargado;

  String get _digitos => widget.controller.text.replaceAll(RegExp(r'\D'), '');

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  void _alCambiar(String _) {
    _espera?.cancel();
    final d = _digitos;
    if (d.length < 9 || d.length > 12 || d == _consultada) return;
    _espera = Timer(const Duration(milliseconds: 700), _buscar);
  }

  Future<void> _buscar() async {
    final d = _digitos;
    if (d.length < 9 || d.length > 12) {
      setState(() => _aviso = "La cédula debe tener entre 9 y 12 dígitos.");
      return;
    }
    setState(() {
      _buscando = true;
      _aviso = null;
      _consultada = d;
    });
    try {
      final r = await ApiService.get('/consultar-cedula/?cedula=$d');
      final data = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (!mounted || d != _digitos) return;
      if (r.statusCode != 200 || data['encontrado'] != true) {
        setState(() {
          _datos = null;
          _aviso = r.statusCode == 200
              ? "Hacienda no tiene registrada esa cédula. Podés escribir el nombre a mano."
              : (data['detail']?.toString() ?? "No se pudo consultar Hacienda.");
        });
        return;
      }
      setState(() {
        _datos = data;
        final nombre = (data['nombre'] ?? '').toString();
        final ctrl = widget.nombreController;
        if (ctrl != null && nombre.isNotEmpty && (ctrl.text.trim().isEmpty || ctrl.text.trim() == _nombreCargado)) {
          ctrl.text = nombre;
          _nombreCargado = nombre;
        }
      });
      widget.onEncontrado?.call(data);
    } catch (e) {
      if (mounted) setState(() => _aviso = "No se pudo consultar Hacienda.");
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detalles = _datos == null
        ? ''
        : [_datos!['tipo_texto'], _datos!['estado'], _datos!['regimen']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.controller,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          keyboardType: TextInputType.number,
          onChanged: _alCambiar,
          onFieldSubmitted: (_) => _buscar(),
          validator: widget.validator,
          decoration: InputDecoration(
            labelText: widget.labelText,
            helperText: "Al escribirla se busca el nombre en Hacienda",
            border: const OutlineInputBorder(),
            suffixIcon: _buscando
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(icon: const Icon(Icons.search), tooltip: "Buscar en Hacienda", onPressed: _buscar),
          ),
        ),
        if (_datos != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "${_datos!['nombre']}${detalles.isEmpty ? '' : '  ·  $detalles'}",
                    style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else if (_aviso != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_aviso!, style: const TextStyle(fontSize: 12, color: Colors.orange))),
              ],
            ),
          ),
      ],
    );
  }
}
