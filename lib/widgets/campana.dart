import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// "Ding" corto (dos notas) para avisos del restaurante: comanda nueva en
/// la cocina, platos listos en el salón. Se arma en memoria como WAV (no
/// hace falta un archivo de sonido) y se toca como data: URL, igual que
/// las notas de voz (ver adjuntos_ia.dart).
class Campana {
  Campana._();

  static final AudioPlayer _player = AudioPlayer();
  static String? _wav;

  static String _armar() {
    const muestras = 22050;
    const duracion = 0.7;
    final n = (muestras * duracion).round();
    final pcm = Int16List(n);
    for (var i = 0; i < n; i++) {
      final t = i / muestras;
      // Primera nota y, a los 0.18 s, una quinta arriba; las dos se apagan solas.
      var v = sin(2 * pi * 880 * t) * exp(-6 * t);
      if (t > 0.18) v += sin(2 * pi * 1320 * (t - 0.18)) * exp(-6 * (t - 0.18));
      pcm[i] = (v * 0.45 * 32767).clamp(-32768, 32767).round();
    }
    final datos = pcm.buffer.asUint8List();
    final cabecera = ByteData(44);
    void texto(int pos, String s) {
      for (var i = 0; i < s.length; i++) {
        cabecera.setUint8(pos + i, s.codeUnitAt(i));
      }
    }

    texto(0, 'RIFF');
    cabecera.setUint32(4, 36 + datos.length, Endian.little);
    texto(8, 'WAVE');
    texto(12, 'fmt ');
    cabecera.setUint32(16, 16, Endian.little);
    cabecera.setUint16(20, 1, Endian.little); // PCM
    cabecera.setUint16(22, 1, Endian.little); // mono
    cabecera.setUint32(24, muestras, Endian.little);
    cabecera.setUint32(28, muestras * 2, Endian.little);
    cabecera.setUint16(32, 2, Endian.little);
    cabecera.setUint16(34, 16, Endian.little);
    texto(36, 'data');
    cabecera.setUint32(40, datos.length, Endian.little);
    final wav = Uint8List(44 + datos.length)
      ..setAll(0, cabecera.buffer.asUint8List())
      ..setAll(44, datos);
    return 'data:audio/wav;base64,${base64Encode(wav)}';
  }

  /// Nunca falla: si el navegador no deja sonar (todavía nadie tocó la
  /// pantalla) simplemente no suena.
  static Future<void> sonar() async {
    try {
      _wav ??= _armar();
      await _player.stop();
      await _player.play(UrlSource(_wav!));
    } catch (_) {}
  }
}
