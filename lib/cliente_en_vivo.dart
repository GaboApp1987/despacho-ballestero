// Cliente HTTP que entrega la respuesta a medida que llega (para el chat
// del asistente en vivo, ver ApiService.postEnVivo). En la web el cliente
// normal de `http` espera la respuesta completa; FetchClient usa fetch(),
// que sí la va entregando por partes.
export 'cliente_en_vivo_io.dart' if (dart.library.js_interop) 'cliente_en_vivo_web.dart';
