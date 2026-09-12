import 'dart:html' as html;
import 'dart:typed_data';

/// Dispara la descarga de un archivo en el navegador armando un Blob y
/// haciendo click en un <a download> invisible -- así es como Flutter Web
/// "guarda" un archivo de verdad, ya que file_picker no implementa
/// saveFile() en esta plataforma (ver export_service.dart).
void descargarBytesEnNavegador(Uint8List bytes, String fileName) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
