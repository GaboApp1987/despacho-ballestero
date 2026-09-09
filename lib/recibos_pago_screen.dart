import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'negocio.dart';
import 'formato.dart';

/// Un Recibo Electrónico de Pago (REP) -- documenta el pago de una factura
/// de crédito ante Hacienda (obligatorio por ley, ver
/// ReciboElectronicoPago en el backend). Se crea solo al registrar un abono
/// contra una factura de crédito específica (ver
/// DetalleCuentaClienteScreen._mostrarDialogoAbono); esta pantalla es el
/// único lugar donde se ven y se pueden reenviar los que quedaron
/// pendientes o con error.
class _ReciboPago {
  final int id;
  final String clienteNombre;
  final String? facturaConsecutivo;
  final String consecutivo;
  final double montoPagado;
  final String estadoHacienda;
  final DateTime? fechaEmision;

  _ReciboPago({
    required this.id,
    required this.clienteNombre,
    required this.facturaConsecutivo,
    required this.consecutivo,
    required this.montoPagado,
    required this.estadoHacienda,
    required this.fechaEmision,
  });

  factory _ReciboPago.fromJson(Map<String, dynamic> j) {
    return _ReciboPago(
      id: j['id'],
      clienteNombre: j['cliente_nombre'] ?? 'Cliente',
      facturaConsecutivo: j['factura_consecutivo'],
      consecutivo: j['consecutivo'] ?? '',
      montoPagado: double.tryParse(j['monto_pagado'].toString()) ?? 0.0,
      estadoHacienda: j['estado_hacienda'] ?? '1',
      fechaEmision: DateTime.tryParse(j['fecha_emision'] ?? ''),
    );
  }

  // Mismos códigos que Factura.ESTADOS_HACIENDA (ReciboElectronicoPago los
  // reusa tal cual): 1 Sin Enviar, 2 Enviando, 3 Aceptado, 4 Rechazado,
  // 5 Error Técnico, 6 No Aplica.
  bool get necesitaReenvio => estadoHacienda == '1' || estadoHacienda == '4' || estadoHacienda == '5';

  String get estadoTexto {
    switch (estadoHacienda) {
      case '1':
        return 'Sin enviar';
      case '2':
        return 'Enviando...';
      case '3':
        return 'Aceptado';
      case '4':
        return 'Rechazado';
      case '5':
        return 'Error técnico';
      default:
        return 'Desconocido';
    }
  }

  Color get estadoColor {
    switch (estadoHacienda) {
      case '3':
        return Colors.green;
      case '2':
        return Colors.blue;
      case '4':
      case '5':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }
}

class RecibosPagoScreen extends StatefulWidget {
  final Negocio negocio;
  const RecibosPagoScreen({super.key, required this.negocio});

  @override
  State<RecibosPagoScreen> createState() => _RecibosPagoScreenState();
}

class _RecibosPagoScreenState extends State<RecibosPagoScreen> {
  bool _cargando = true;
  List<_ReciboPago> _recibos = [];
  final Set<int> _reenviando = {};

  int get _pendientesCount => _recibos.where((r) => r.necesitaReenvio).length;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    try {
      final response = await ApiService.get('/recibos-pago/?negocio=${widget.negocio.id}');
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as List;
        if (mounted) {
          setState(() {
            _recibos = data.map((j) => _ReciboPago.fromJson(j)).toList();
            _cargando = false;
          });
        }
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar los recibos de pago: $e')),
        );
      }
    }
  }

  Future<void> _reenviar(_ReciboPago recibo) async {
    setState(() => _reenviando.add(recibo.id));
    try {
      final response = await ApiService.post('/recibos-pago/${recibo.id}/reenviar-hacienda/', {});
      if (response.statusCode != 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(data['detail'] ?? 'Error al reenviar');
      }
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recibo reenviado a Hacienda.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reenviar: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _reenviando.remove(recibo.id));
    }
  }

  String _formatFecha(DateTime? fecha) {
    if (fecha == null) return '';
    final local = fecha.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$dd/$mm/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text('Recibos Electrónicos de Pago', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
              ],
            ),
          ),
          if (!_cargando && _pendientesCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.red.withOpacity(0.08),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pendientesCount == 1
                          ? 'Tenés 1 recibo de pago pendiente de reenviar a Hacienda.'
                          : 'Tenés $_pendientesCount recibos de pago pendientes de reenviar a Hacienda.',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _recibos.isEmpty
                    ? Center(
                        child: Text(
                          'Todavía no hay recibos de pago.\nSe generan solos al registrar un abono contra una factura de crédito.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _recibos.length,
                          itemBuilder: (context, i) {
                            final r = _recibos[i];
                            final reenviando = _reenviando.contains(r.id);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  r.clienteNombre,
                                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: r.estadoColor.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  r.estadoTexto,
                                                  style: TextStyle(color: r.estadoColor, fontWeight: FontWeight.w600, fontSize: 11.5),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Factura F-${r.facturaConsecutivo ?? '?'} · ${_formatFecha(r.fechaEmision)}',
                                            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(formatearColones(r.montoPagado), style: const TextStyle(fontWeight: FontWeight.bold)),
                                        if (r.necesitaReenvio) ...[
                                          const SizedBox(height: 6),
                                          reenviando
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                              : TextButton.icon(
                                                  onPressed: () => _reenviar(r),
                                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                                  icon: const Icon(Icons.refresh, size: 14),
                                                  label: const Text('Reenviar', style: TextStyle(fontSize: 12.5)),
                                                ),
                                        ],
                                      ],
                                    ),
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
