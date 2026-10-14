import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api_service.dart';

/// Botón del colaborador para marcar entrada y salida
/// (POST /asistencia/marcar/, ver gestion/asistencia.py). Sin marca abierta
/// dice "Marcar entrada"; trabajando muestra cuánto lleva y al tocarlo
/// (con confirmación) marca la salida.
class BotonAsistencia extends StatefulWidget {
  final int negocioId;
  const BotonAsistencia({super.key, required this.negocioId});

  @override
  State<BotonAsistencia> createState() => _BotonAsistenciaState();
}

class _BotonAsistenciaState extends State<BotonAsistencia> {
  DateTime? _entrada;
  bool _cargado = false;
  bool _enviando = false;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Refresca "lleva X h" cada minuto.
    _reloj = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _entrada != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _aplicar(Map<String, dynamic> datos) {
    final abierta = datos['abierta'];
    _entrada = abierta == null ? null : DateTime.parse(abierta['entrada']).toLocal();
    _cargado = true;
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/asistencia/marcar/?negocio=${widget.negocioId}');
      if (r.statusCode == 200 && mounted) setState(() => _aplicar(jsonDecode(utf8.decode(r.bodyBytes))));
    } catch (_) {
      // Sin conexión: el botón no se muestra hasta que cargue.
    }
  }

  static String _hora(DateTime d) => "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  static String _duracion(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h == 0 ? "$m min" : "$h h ${m.toString().padLeft(2, '0')} min";
  }

  Future<void> _marcar() async {
    final saliendo = _entrada != null;
    if (saliendo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("¿Marcar salida?"),
          content: Text("Entraste a las ${_hora(_entrada!)}. Llevás ${_duracion(DateTime.now().difference(_entrada!))}."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Marcar salida")),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _enviando = true);
    try {
      final r = await ApiService.post('/asistencia/marcar/', {'negocio': widget.negocioId});
      ApiService.verificar(r);
      final datos = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _aplicar(datos));
      final horasHoy = ((datos['horas_hoy'] as num?) ?? 0).toDouble();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(datos['marco'] == 'entrada'
            ? "Entrada marcada a las ${_hora(DateTime.now())}"
            : "Salida marcada a las ${_hora(DateTime.now())}. Hoy: ${_duracion(Duration(minutes: (horasHoy * 60).round()))}"),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado) return const SizedBox.shrink();
    final trabajando = _entrada != null;
    final angosto = MediaQuery.sizeOf(context).width < 600;
    final color = trabajando ? Colors.green.shade700 : Theme.of(context).colorScheme.primary;
    final texto = trabajando
        ? (angosto ? _duracion(DateTime.now().difference(_entrada!)) : "Trabajando · ${_duracion(DateTime.now().difference(_entrada!))}")
        : (angosto ? "Entrada" : "Marcar entrada");
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: trabajando ? "Entraste a las ${_hora(_entrada!)}. Tocá para marcar la salida." : "Marcar tu hora de entrada",
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            backgroundColor: color.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _enviando ? null : _marcar,
          icon: _enviando
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(trabajando ? Icons.timer_outlined : Icons.login, size: 18),
          label: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
