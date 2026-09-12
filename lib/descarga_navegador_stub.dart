import 'dart:typed_data';

/// Stub para plataformas que no son Web (Windows/Android/etc.) -- ahí el
/// guardado real lo maneja file_picker, esto nunca se llama (ver
/// export_service.dart, que solo usa descargarBytesEnNavegador si kIsWeb).
void descargarBytesEnNavegador(Uint8List bytes, String fileName) {
  throw UnsupportedError('descargarBytesEnNavegador solo está disponible en Web.');
}
