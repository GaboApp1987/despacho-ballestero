import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

/// Un mensaje del chat interno negocio <-> contador, ya sea recién llegado
/// por WebSocket o cargado del historial por REST (ver
/// ConversacionChatViewSet en el backend) -- misma forma en los dos casos.
class MensajeChat {
  final int id;
  final String texto;
  final bool enviadoPorSocio;
  final DateTime creadoEn;
  final String? archivoUrl;
  final String archivoNombre;

  MensajeChat({
    required this.id,
    required this.texto,
    required this.enviadoPorSocio,
    required this.creadoEn,
    this.archivoUrl,
    this.archivoNombre = '',
  });

  bool get tieneArchivo => archivoUrl != null && archivoUrl!.isNotEmpty;

  static const _extensionesImagen = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
  bool get archivoEsImagen {
    final ext = archivoNombre.split('.').last.toLowerCase();
    return _extensionesImagen.contains(ext);
  }

  factory MensajeChat.fromJson(Map<String, dynamic> json) => MensajeChat(
        id: json['id'],
        texto: json['texto'] ?? '',
        enviadoPorSocio: json['enviado_por_socio'] ?? false,
        creadoEn: DateTime.parse(json['creado_en']),
        archivoUrl: json['archivo_url'],
        archivoNombre: json['archivo_nombre'] ?? '',
      );
}

/// Conexión en vivo a UNA conversación de chat -- se reconecta sola si se
/// cae (con espera creciente para no insistir en loop si el server está
/// caído). El historial de mensajes viejos se carga aparte por REST; esto
/// es solo para lo que llega mientras la pantalla está abierta.
class ChatService {
  final int conversacionId;
  WebSocketChannel? _canal;
  StreamSubscription? _subscripcion;
  final _controlador = StreamController<MensajeChat>.broadcast();
  bool _cerradoPorMi = false;
  int _intentosReconexion = 0;

  ChatService(this.conversacionId);

  Stream<MensajeChat> get mensajes => _controlador.stream;

  Future<void> conectar() async {
    _cerradoPorMi = false;
    final token = await ApiService.getToken();
    if (token == null) return;
    // El WebSocket vive en la raíz del dominio (/ws/chat/...), no bajo
    // /api como el resto de la API REST -- ver config/asgi.py.
    final wsBase = ApiService.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://')
        .replaceFirst(RegExp(r'/api/?$'), '');
    final uri = Uri.parse('$wsBase/ws/chat/$conversacionId/?token=$token');
    try {
      _canal = WebSocketChannel.connect(uri);
      _intentosReconexion = 0;
      _subscripcion = _canal!.stream.listen(
        (data) => _controlador.add(MensajeChat.fromJson(jsonDecode(data as String))),
        onDone: _reconectar,
        onError: (_) => _reconectar(),
        cancelOnError: true,
      );
    } catch (_) {
      _reconectar();
    }
  }

  void _reconectar() {
    if (_cerradoPorMi) return;
    _intentosReconexion++;
    final espera = Duration(seconds: _intentosReconexion.clamp(1, 10));
    Future.delayed(espera, () {
      if (!_cerradoPorMi) conectar();
    });
  }

  void enviar(String texto) {
    _canal?.sink.add(jsonEncode({'texto': texto}));
  }

  void cerrar() {
    _cerradoPorMi = true;
    _subscripcion?.cancel();
    _canal?.sink.close();
    _controlador.close();
  }
}
