import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';

/// Facturas y consultas de IA de cortesía: el administrador de la
/// plataforma le regala a un negocio la cantidad que quiera, sin cobro
/// (POST /suscripciones-negocio/cortesia/). No vencen, se usan cuando se
/// acaba el cupo del plan y, mientras queden, el negocio puede facturar
/// aunque no esté pagando. Devuelve true si cambió el saldo.
Future<bool> abrirCortesia(BuildContext context, Negocio negocio) async {
  final cambio = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoCortesia(negocio: negocio),
  );
  return cambio == true;
}

String _fecha(String iso) {
  final d = DateTime.parse(iso).toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return "${dos(d.day)}/${dos(d.month)}/${d.year}";
}

class _DialogoCortesia extends StatefulWidget {
  final Negocio negocio;
  const _DialogoCortesia({required this.negocio});

  @override
  State<_DialogoCortesia> createState() => _DialogoCortesiaState();
}

class _DialogoCortesiaState extends State<_DialogoCortesia> {
  final _cantidadCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  Map<String, dynamic>? _datos;
  String? _error;
  bool _guardando = false;
  bool _cambio = false;
  bool _ia = false; // false: facturas, true: consultas de IA

  String get _unidad => _ia ? "consultas de IA" : "facturas";

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/suscripciones-negocio/cortesia/?negocio=${widget.negocio.id}');
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      if (mounted) setState(() => _datos = jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _guardar({required bool quitar}) async {
    final cantidad = int.tryParse(_cantidadCtrl.text.trim()) ?? 0;
    if (cantidad <= 0) {
      setState(() => _error = "Escribí cuántas $_unidad.");
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final r = await ApiService.post('/suscripciones-negocio/cortesia/', {
        'negocio': widget.negocio.id,
        'tipo': _ia ? 'ia' : 'documentos',
        'cantidad': quitar ? -cantidad : cantidad,
        'nota': _notaCtrl.text.trim(),
      });
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      _cambio = true;
      _cantidadCtrl.clear();
      _notaCtrl.clear();
      setState(() => _datos = jsonDecode(utf8.decode(r.bodyBytes)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(quitar
              ? "Se quitaron $cantidad $_unidad de cortesía a ${widget.negocio.nombreComercial}"
              : "Le regalaste $cantidad $_unidad a ${widget.negocio.nombreComercial}"),
        ));
      }
    } catch (e) {
      setState(() => _error = ApiService.textoError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    final saldo = (datos?[_ia ? 'saldo_ia' : 'saldo'] as num?)?.toInt() ?? 0;
    final historial = [
      for (final h in (datos?['historial'] as List? ?? []))
        if ((h['tipo'] == 'ia') == _ia) h,
    ];
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.card_giftcard, color: Colors.pink.shade400),
        const SizedBox(width: 10),
        const Expanded(child: Text("Regalar a un negocio")),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: datos == null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.negocio.nombreComercial, style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, icon: Icon(Icons.receipt_long_outlined), label: Text("Facturas")),
                          ButtonSegment(value: true, icon: Icon(Icons.auto_awesome_outlined), label: Text("Consultas de IA")),
                        ],
                        selected: {_ia},
                        onSelectionChanged: (v) => setState(() {
                          _ia = v.first;
                          _error = null;
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.pink.withOpacity(0.07), borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Le quedan", style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        Text(_ia ? "$saldo ${saldo == 1 ? 'consulta' : 'consultas'} de IA de cortesía" : "$saldo ${saldo == 1 ? 'factura' : 'facturas'} de cortesía",
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.pink.shade700)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _ia
                          ? (datos['ia_ilimitada'] == true
                              ? "Su plan ${datos['plan'] == null ? '(ninguno)' : datos['plan']} no tiene límite de consultas de IA: la cortesía no se va a usar mientras siga en ese plan."
                              : "Se usan cuando se le acaben las consultas de IA del mes de su plan ${datos['plan']}. No vencen.")
                          : datos['pagando'] == true
                          ? (datos['plan_ilimitado'] == true
                              ? "Su plan ${datos['plan'] == null ? '(ninguno)' : datos['plan']} no tiene límite de documentos: la cortesía solo se usará si deja de pagar."
                              : "Se usan cuando se le acabe el cupo del plan ${datos['plan']}. No vencen.")
                          : "No está pagando el plan: mientras le queden facturas de cortesía puede entrar y facturar.",
                      style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final n in const [5, 10, 25, 50, 100])
                        ActionChip(label: Text("$n"), onPressed: () => setState(() => _cantidadCtrl.text = "$n")),
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _cantidadCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: "Cantidad de $_unidad", border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notaCtrl,
                      maxLength: 200,
                      decoration: const InputDecoration(
                          labelText: "Motivo (opcional)", hintText: "Ej: para que lo pruebe", border: OutlineInputBorder()),
                    ),
                    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                    if (historial.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text("Regaladas antes", style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final h in historial.take(8))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              width: 52,
                              child: Text("+${h['cantidad']}", style: TextStyle(fontWeight: FontWeight.w700, color: Colors.pink.shade700)),
                            ),
                            Expanded(
                              child: Text(
                                [
                                  _fecha(h['fecha']),
                                  if ((h['nota'] ?? '').toString().isNotEmpty) h['nota'],
                                ].join(' · '),
                                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, _cambio), child: const Text("Cerrar")),
        if (datos != null && saldo > 0)
          TextButton(
            onPressed: _guardando ? null : () => _guardar(quitar: true),
            child: const Text("Quitar"),
          ),
        if (datos != null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade500, foregroundColor: Colors.white),
            onPressed: _guardando ? null : () => _guardar(quitar: false),
            icon: const Icon(Icons.card_giftcard, size: 18),
            label: const Text("Regalar"),
          ),
      ],
    );
  }
}
