import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../theme/app_theme.dart';

/// Notas de voz, fotos y archivos para los chats (asistente de IA, soporte
/// y chat negocio <-> contador). En el chat de la IA el backend "escucha"
/// la nota de voz (ver gestion/ia_adjuntos.py) y contesta a lo que se dijo
/// -- la transcripción nunca se muestra; acá solo se ve la nota de voz
/// como en WhatsApp.
class AdjuntoIA {
  final String nombre;
  final String mime;
  final Uint8List bytes;
  final Duration? duracion;
  const AdjuntoIA({required this.nombre, required this.mime, required this.bytes, this.duracion});

  bool get esAudio => mime.startsWith('audio/');
  bool get esImagen => mime.startsWith('image/');

  Map<String, dynamic> toJson() => {'nombre': nombre, 'mime': mime, 'base64': base64Encode(bytes)};
}

const int maxBytesAdjunto = 15 * 1024 * 1024;

const _mimes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'pdf': 'application/pdf',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'xls': 'application/vnd.ms-excel',
  'csv': 'text/csv',
  'xml': 'application/xml',
  'txt': 'text/plain',
  'webm': 'audio/webm',
  'ogg': 'audio/ogg',
  'm4a': 'audio/mp4',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
};

String mimePorNombre(String nombre) => _mimes[nombre.split('.').last.toLowerCase()] ?? 'application/octet-stream';

bool nombreEsAudio(String nombre) => mimePorNombre(nombre).startsWith('audio/');

/// Abre el selector de archivos (fotos, PDF, Excel, CSV, XML). Los que
/// pasan de 15 MB se descartan con un aviso.
Future<List<AdjuntoIA>> elegirArchivosParaIA(BuildContext context) async {
  final resultado = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    withData: true,
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf', 'xlsx', 'xls', 'csv', 'xml', 'txt'],
  );
  final archivos = <AdjuntoIA>[];
  var pesados = 0;
  for (final f in resultado?.files ?? <PlatformFile>[]) {
    if (f.bytes == null) continue;
    if (f.bytes!.length > maxBytesAdjunto) {
      pesados++;
      continue;
    }
    archivos.add(AdjuntoIA(nombre: f.name, mime: mimePorNombre(f.name), bytes: f.bytes!));
  }
  if (pesados > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Algún archivo pesa más de 15 MB y no se adjuntó.')),
    );
  }
  return archivos.take(5).toList();
}

/// Graba una nota de voz con el micrófono (web: webm/opus, o mp4 en
/// Safari; Windows/celular: m4a). Máximo 3 minutos.
class GrabadorVoz {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _inicio;
  String _extension = 'webm';
  String _mime = 'audio/webm';

  static const duracionMaxima = Duration(minutes: 3);

  Stream<Amplitude> amplitud() => _recorder.onAmplitudeChanged(const Duration(milliseconds: 120));

  /// false si no hay permiso de micrófono o el dispositivo no puede grabar.
  Future<bool> iniciar() async {
    if (!await _recorder.hasPermission()) return false;
    var encoder = AudioEncoder.aacLc;
    _extension = 'm4a';
    _mime = 'audio/mp4';
    if (kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.opus)) {
      encoder = AudioEncoder.opus;
      _extension = 'webm';
      _mime = 'audio/webm';
    }
    var ruta = '';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      ruta = '${dir.path}/nota_de_voz_${DateTime.now().millisecondsSinceEpoch}.$_extension';
    }
    await _recorder.start(RecordConfig(encoder: encoder, numChannels: 1), path: ruta);
    _inicio = DateTime.now();
    return true;
  }

  Future<AdjuntoIA?> detener() async {
    final ruta = await _recorder.stop();
    final duracion = _inicio == null ? null : DateTime.now().difference(_inicio!);
    _inicio = null;
    if (ruta == null || ruta.isEmpty) return null;
    final bytes = await XFile(ruta).readAsBytes();
    if (bytes.isEmpty) return null;
    return AdjuntoIA(nombre: 'nota_de_voz.$_extension', mime: _mime, bytes: bytes, duracion: duracion);
  }

  Future<void> cancelar() async {
    _inicio = null;
    await _recorder.cancel();
  }

  void dispose() => _recorder.dispose();
}

String formatearDuracion(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Lo que se ve mientras se graba: punto rojo que late, tiempo, ondas que
/// siguen la voz, botón para descartar y botón para mandar. Cuando llega
/// a la duración máxima se manda sola.
class GrabandoNotaVoz extends StatefulWidget {
  final GrabadorVoz grabador;
  final VoidCallback onCancelar;
  final VoidCallback onEnviar;
  final Color colorTexto;
  const GrabandoNotaVoz({
    super.key,
    required this.grabador,
    required this.onCancelar,
    required this.onEnviar,
    this.colorTexto = Colors.white,
  });

  @override
  State<GrabandoNotaVoz> createState() => _GrabandoNotaVozState();
}

class _GrabandoNotaVozState extends State<GrabandoNotaVoz> with SingleTickerProviderStateMixin {
  final _inicio = DateTime.now();
  late final Timer _timer;
  StreamSubscription<Amplitude>? _sub;
  final List<double> _niveles = List.filled(28, 0.08, growable: true);
  late final AnimationController _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().difference(_inicio) >= GrabadorVoz.duracionMaxima) widget.onEnviar();
    });
    _sub = widget.grabador.amplitud().listen((a) {
      // dBFS: -45 (silencio) .. 0 (fuerte) -> 0.08 .. 1
      final nivel = ((a.current + 45) / 45).clamp(0.08, 1.0);
      if (mounted) {
        setState(() {
          _niveles.removeAt(0);
          _niveles.add(nivel);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _sub?.cancel();
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transcurrido = DateTime.now().difference(_inicio);
    return Row(
      children: [
        IconButton(
          onPressed: widget.onCancelar,
          icon: Icon(Icons.delete_outline_rounded, color: widget.colorTexto.withOpacity(0.8)),
          tooltip: 'Descartar',
        ),
        FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(_pulso),
          child: const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
        ),
        const SizedBox(width: 6),
        Text(formatearDuracion(transcurrido),
            style: TextStyle(color: widget.colorTexto, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final n in _niveles)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 3,
                    height: 4 + 26 * n,
                    decoration: BoxDecoration(color: widget.colorTexto.withOpacity(0.75), borderRadius: BorderRadius.circular(2)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: widget.onEnviar,
          icon: const Icon(Icons.send_rounded),
          tooltip: 'Mandar nota de voz',
          style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
        ),
      ],
    );
  }
}

/// Burbuja reproducible de una nota de voz (de bytes recién grabados o de
/// una URL ya subida, ej. el chat con el contador).
class NotaVozBurbuja extends StatefulWidget {
  final Uint8List? bytes;
  final String? mime;
  final String? url;
  final Duration? duracion;
  final Color color;
  const NotaVozBurbuja({super.key, this.bytes, this.mime, this.url, this.duracion, required this.color});

  @override
  State<NotaVozBurbuja> createState() => _NotaVozBurbujaState();
}

class _NotaVozBurbujaState extends State<NotaVozBurbuja> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _estado = PlayerState.stopped;
  Duration _posicion = Duration.zero;
  Duration? _total;
  bool _cargada = false;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _total = widget.duracion;
    _subs.add(_player.onPlayerStateChanged.listen((s) => mounted ? setState(() => _estado = s) : null));
    _subs.add(_player.onPositionChanged.listen((p) => mounted ? setState(() => _posicion = p) : null));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _total = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) => mounted ? setState(() => _posicion = Duration.zero) : null));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _alternar() async {
    try {
      if (_estado == PlayerState.playing) {
        await _player.pause();
        return;
      }
      if (!_cargada) {
        if (widget.url != null) {
          await _player.setSource(UrlSource(widget.url!));
        } else if (kIsWeb) {
          await _player.setSource(UrlSource('data:${widget.mime ?? 'audio/webm'};base64,${base64Encode(widget.bytes!)}'));
        } else {
          await _player.setSource(BytesSource(widget.bytes!, mimeType: widget.mime));
        }
        _cargada = true;
      }
      await _player.resume();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo reproducir la nota de voz ($e).')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total ?? Duration.zero;
    final progreso = total.inMilliseconds > 0 ? (_posicion.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final reproduciendo = _estado == PlayerState.playing;
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          InkWell(
            onTap: _alternar,
            customBorder: const CircleBorder(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity(0.15)),
              child: Icon(reproduciendo ? Icons.pause_rounded : Icons.play_arrow_rounded, color: widget.color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 4,
                    backgroundColor: widget.color.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation(widget.color),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(Icons.mic_rounded, size: 13, color: widget.color.withOpacity(0.8)),
                    const SizedBox(width: 3),
                    Text(
                      formatearDuracion(reproduciendo || _posicion > Duration.zero ? _posicion : total),
                      style: TextStyle(fontSize: 11.5, color: widget.color.withOpacity(0.85)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vista previa de un adjunto antes de mandarlo (miniatura o ícono + nombre).
class ChipAdjunto extends StatelessWidget {
  final AdjuntoIA adjunto;
  final VoidCallback? onQuitar;
  const ChipAdjunto({super.key, required this.adjunto, this.onQuitar});

  @override
  Widget build(BuildContext context) {
    final icono = adjunto.mime == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : (adjunto.nombre.toLowerCase().endsWith('.xml') ? Icons.code : Icons.insert_drive_file_outlined);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: adjunto.esImagen
                ? Image.memory(adjunto.bytes, width: 34, height: 34, fit: BoxFit.cover)
                : Container(width: 34, height: 34, color: AppColors.primary.withOpacity(0.12), child: Icon(icono, size: 18, color: AppColors.primary)),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(adjunto.nombre, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
          if (onQuitar != null)
            IconButton(
              onPressed: onQuitar,
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Quitar',
            ),
        ],
      ),
    );
  }
}
