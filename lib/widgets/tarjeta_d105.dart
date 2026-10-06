import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../formato.dart';
import '../theme/app_theme.dart';

/// Borrador de la D-105-2 (régimen simplificado) de un trimestre: las
/// compras ya clasificadas por tarifa, listas para digitar en TRIBU-CR
/// (backend: gestion/d105.py). Los factores los pone TRIBU-CR; si el
/// negocio anotó los suyos en Ajustes, se muestra una estimación.
class TarjetaD105 extends StatefulWidget {
  final int negocioId;
  const TarjetaD105({super.key, required this.negocioId});

  @override
  State<TarjetaD105> createState() => _TarjetaD105State();
}

class _TarjetaD105State extends State<TarjetaD105> {
  late int _anio;
  late int _trimestre;
  Map<String, dynamic>? _datos;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    // Por defecto el último trimestre cerrado (el que toca declarar).
    final hoy = DateTime.now();
    final actual = (hoy.month - 1) ~/ 3 + 1;
    _anio = actual == 1 ? hoy.year - 1 : hoy.year;
    _trimestre = actual == 1 ? 4 : actual - 1;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final res = ApiService.verificar(await ApiService.get(
          '/facturas/declaracion-d105/?negocio=${widget.negocioId}&anio=$_anio&trimestre=$_trimestre'));
      if (mounted) setState(() => _datos = json.decode(utf8.decode(res.bodyBytes)));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mover(int delta) {
    var t = _trimestre + delta;
    var a = _anio;
    if (t < 1) {
      t = 4;
      a--;
    } else if (t > 4) {
      t = 1;
      a++;
    }
    setState(() {
      _trimestre = t;
      _anio = a;
    });
    _cargar();
  }

  double _n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  Widget _fila(String etiqueta, String valor, {bool fuerte = false, String? copiar}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(etiqueta, style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
            Text(valor,
                style: TextStyle(
                    color: AppColors.textStrong, fontWeight: fuerte ? FontWeight.bold : FontWeight.w500, fontSize: 13)),
            if (copiar != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: "Copiar para pegar en TRIBU-CR",
                icon: const Icon(Icons.copy, size: 15),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: copiar));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copiado: $copiar")));
                },
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _cargando ? null : () => _mover(-1)),
              Expanded(
                child: Text("Trimestre $_trimestre de $_anio",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong)),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _cargando ? null : () => _mover(1)),
            ],
          ),
          if (_cargando) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          if (d != null && !_cargando) ...[
            Text(
              "Se presenta en TRIBU-CR a más tardar el ${d['vence']} · ${d['cantidad_compras']} compra(s) en el trimestre",
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const Divider(height: 22),
            Text("D-105 Renta", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong)),
            _fila("Compras del periodo", formatearColones(_n(d['renta']['compras_periodo'])),
                copiar: d['renta']['compras_periodo'].toString()),
            if (d['renta']['impuesto_estimado'] != null)
              _fila("Impuesto estimado (factor ${d['renta']['factor']})",
                  formatearColones(_n(d['renta']['impuesto_estimado'])),
                  fuerte: true),
            const SizedBox(height: 12),
            Text("D-105 IVA", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong)),
            for (final c in (d['iva']['compras'] as List))
              _fila(
                "Compras ${c['tarifa']}% (${c['lineas']} línea${c['lineas'] == 1 ? '' : 's'}, con IVA)",
                formatearColones(_n(c['con_iva'])),
                copiar: c['con_iva'].toString(),
              ),
            if (d['iva']['impuesto_estimado'] != null)
              _fila("IVA estimado", formatearColones(_n(d['iva']['impuesto_estimado'])), fuerte: true),
            if ((d['lineas_sin_tarifa'] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "${d['lineas_sin_tarifa']} línea(s) de compra son de productos sin impuesto asignado "
                  "(${formatearColones(_n(d['base_sin_tarifa']))}): asignales la tarifa en Inventario para clasificarlas.",
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              "Los factores los asigna TRIBU-CR según tu actividad. Las estimaciones solo aparecen si anotás tus "
              "factores en Ajustes, y son de referencia: el monto oficial es el que calcula TRIBU-CR.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
