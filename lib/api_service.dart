import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'perfil_sesion.dart';
import 'cliente_en_vivo.dart';
import 'widgets/asistente_flotante.dart';

class ApiService {
  // AUDITORIA.md hallazgo B3 -- el token/refresh_token vivían en
  // SharedPreferences (texto plano, legible en el dispositivo con
  // root/adb backup); FlutterSecureStorage usa Android Keystore / iOS
  // Keychain / DPAPI en Windows, cifrados por el sistema operativo.
  static const _almacenSeguro = FlutterSecureStorage();
  // URL base del servidor Django. Por defecto apunta a local (para "flutter
  // run" normal, sin tocar nada). Para compilar apuntando a producción:
  //   flutter build windows --dart-define=API_BASE_URL=https://equilibracr.com/api
  // o para probar en caliente contra producción con hot reload:
  //   flutter run -d windows --dart-define=API_BASE_URL=https://equilibracr.com/api
  // OJO: tiene que ser equilibracr.com, NUNCA el dominio *.up.railway.app --
  // Railway tiene ALLOWED_HOSTS=equilibracr.com, así que cualquier build
  // (web, windows, android) que apunte al dominio de railway.app recibe
  // "Bad Request (400)" en TODAS las peticiones reales (login incluido),
  // aunque los archivos estáticos sigan cargando bien. Pasó real en
  // producción el 2026-09-11: cuatro builds seguidos con la URL de railway
  // dejaron el login roto sin que el build avisara nada.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  /// Obtiene el token guardado en el dispositivo
  static Future<String?> getToken() async {
    return _almacenSeguro.read(key: 'token');
  }

  /// Guarda el access token (y el refresh token, si viene) tras el login.
  static Future<void> saveTokens({required String access, String? refresh}) async {
    await _almacenSeguro.write(key: 'token', value: access);
    if (refresh != null) {
      await _almacenSeguro.write(key: 'refresh_token', value: refresh);
    }
  }

  /// Elimina los tokens guardados (cierre de sesión)
  static Future<void> logout() async {
    PerfilSesion.limpiar();
    AsistenteFlotante.limpiar();
    await _almacenSeguro.delete(key: 'token');
    await _almacenSeguro.delete(key: 'refresh_token');
  }

  /// Construye las cabeceras predeterminadas con el token Bearer JWT
  static Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Intenta renovar el access token usando el refresh token guardado.
  /// Devuelve true si lo logró.
  static Future<bool> _renovarToken() async {
    final refresh = await _almacenSeguro.read(key: 'refresh_token');
    if (refresh == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh': refresh}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _almacenSeguro.write(key: 'token', value: data['access']);
        // Con ROTATE_REFRESH_TOKENS=True el backend invalida el refresh
        // token usado y manda uno nuevo en la misma respuesta -- si no lo
        // guardamos aca, la proxima renovacion (unas horas despues) falla
        // con el refresh token ya invalidado y la sesion se cierra sola,
        // justo lo contrario de lo que se buscaba con la rotacion.
        if (data['refresh'] != null) {
          await _almacenSeguro.write(key: 'refresh_token', value: data['refresh']);
        }
        return true;
      }
    } catch (_) {
      // Sin conexión u otro error: seguimos con el token viejo, la petición original fallará igual.
    }
    return false;
  }

  /// Ejecuta la petición con el token actual; si el servidor responde 401
  /// (token vencido), intenta renovarlo una vez y reintenta la petición.
  static Future<http.Response> _conRenovacion(
    Future<http.Response> Function(Map<String, String> headers) hacerPeticion,
  ) async {
    final headers = await _getHeaders();
    final response = await hacerPeticion(headers);
    if (response.statusCode == 401 && await _renovarToken()) {
      final headersNuevos = await _getHeaders();
      return hacerPeticion(headersNuevos);
    }
    return response;
  }

  /// Método GET genérico
  static Future<http.Response> get(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) => http.get(url, headers: headers));
  }

  /// Método POST genérico
  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) => http.post(url, headers: headers, body: json.encode(body)));
  }

  /// POST cuya respuesta llega en vivo (Server-Sent Events, ver
  /// SoporteChatView._responder_en_vivo): entrega cada evento `data: {...}`
  /// decodificado apenas llega. Si el servidor contesta un JSON normal (ej.
  /// un aviso sin pasar por la IA) lo entrega como un solo evento "fin".
  static Stream<Map<String, dynamic>> postEnVivo(String endpoint, Map<String, dynamic> body) async* {
    final url = Uri.parse('$baseUrl$endpoint');
    var headers = await _getHeaders();
    for (var intento = 0; intento < 2; intento++) {
      final cliente = crearClienteEnVivo();
      try {
        final pedido = http.Request('POST', url)
          ..headers.addAll(headers)
          ..headers['Accept'] = 'text/event-stream'
          ..body = json.encode(body);
        final respuesta = await cliente.send(pedido);
        if (respuesta.statusCode == 401 && intento == 0 && await _renovarToken()) {
          headers = await _getHeaders();
          continue;
        }
        final tipo = respuesta.headers['content-type'] ?? '';
        if (respuesta.statusCode != 200 || !tipo.contains('text/event-stream')) {
          final texto = await respuesta.stream.bytesToString();
          dynamic datos;
          try {
            datos = json.decode(texto);
          } catch (_) {
            datos = null;
          }
          if (respuesta.statusCode == 200 && datos is Map) {
            yield {'tipo': 'fin', 'dato': datos};
          } else {
            yield {'tipo': 'error', 'dato': (datos is Map ? datos['detail'] : null) ?? 'Error ${respuesta.statusCode}'};
          }
          return;
        }
        await for (final linea in respuesta.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (linea.startsWith('data:')) {
            yield Map<String, dynamic>.from(json.decode(linea.substring(5).trim()) as Map);
          }
        }
        return;
      } finally {
        cliente.close();
      }
    }
  }

  /// Método PUT genérico
  static Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) => http.put(url, headers: headers, body: json.encode(body)));
  }

  /// Método PATCH genérico (actualización parcial)
  static Future<http.Response> patch(String endpoint, Map<String, dynamic> body) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) => http.patch(url, headers: headers, body: json.encode(body)));
  }

  /// Texto legible del error que devolvió el backend: "detail"/"error" o
  /// el primer error de campo de DRF ({"campo": ["mensaje"]}).
  static String mensajeError(http.Response r) {
    try {
      final data = json.decode(utf8.decode(r.bodyBytes));
      if (data is Map) {
        final directo = data['detail'] ?? data['error'];
        if (directo != null) return directo.toString();
        for (final entrada in data.entries) {
          final v = entrada.value;
          return "${entrada.key}: ${v is List && v.isNotEmpty ? v.first : v}";
        }
      }
    } catch (_) {}
    return "Error del servidor (HTTP ${r.statusCode})";
  }

  /// Lanza una excepción con el mensaje del backend si la respuesta no es
  /// 2xx -- para las llamadas que antes se hacían con `await` sin revisar
  /// el código (ej. descartar un correo de compra daba 500 y la app no
  /// decía nada).
  static http.Response verificar(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception(mensajeError(r));
    return r;
  }

  /// Método DELETE genérico
  static Future<http.Response> delete(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) => http.delete(url, headers: headers));
  }

  /// Sube un archivo (ej. un logo) como PATCH multipart/form-data.
  static Future<http.Response> uploadFile(String endpoint, String fieldName, String filePath) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) async {
      final request = http.MultipartRequest('PATCH', url);
      final headersSinContentType = Map<String, String>.from(headers)..remove('Content-Type');
      request.headers.addAll(headersSinContentType);
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  /// Igual que [uploadFile] pero a partir de bytes en memoria en vez de una
  /// ruta en disco — necesario en Flutter Web, donde no existe sistema de
  /// archivos real y file_picker solo entrega bytes. Funciona igual en
  /// escritorio, así que se puede usar en todas las plataformas.
  static Future<http.Response> uploadBytes(String endpoint, String fieldName, List<int> bytes, String filename) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) async {
      final request = http.MultipartRequest('PATCH', url);
      final headersSinContentType = Map<String, String>.from(headers)..remove('Content-Type');
      request.headers.addAll(headersSinContentType);
      request.files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: filename));
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  /// POST multipart/form-data con un archivo y campos adicionales (ej. subir
  /// un XML a analizar junto con el id del negocio).
  static Future<http.Response> postMultipart(
    String endpoint,
    Map<String, String> campos,
    String fieldName,
    String filePath,
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) async {
      final request = http.MultipartRequest('POST', url);
      final headersSinContentType = Map<String, String>.from(headers)..remove('Content-Type');
      request.headers.addAll(headersSinContentType);
      request.fields.addAll(campos);
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  /// Igual que [postMultipart] pero a partir de bytes en memoria (ver
  /// [uploadBytes]).
  static Future<http.Response> postMultipartBytes(
    String endpoint,
    Map<String, String> campos,
    String fieldName,
    List<int> bytes,
    String filename, {
    String? contentType,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) async {
      final request = http.MultipartRequest('POST', url);
      final headersSinContentType = Map<String, String>.from(headers)..remove('Content-Type');
      request.headers.addAll(headersSinContentType);
      request.fields.addAll(campos);
      // Sin `contentType` explícito, MultipartFile.fromBytes manda
      // application/octet-stream sin importar el archivo -- eso hace que
      // Django (request.FILES[...].content_type) y por lo tanto la API de
      // Anthropic (que exige el media_type real de la imagen/PDF) reciban
      // un tipo incorrecto. Pasarlo acá es necesario para cualquier subida
      // que dependa de content_type en el backend (ej. certificaciones).
      request.files.add(http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
        contentType: contentType != null ? MediaType.parse(contentType) : null,
      ));
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  /// Igual que [postMultipartBytes] pero con VARIOS archivos bajo el mismo
  /// campo (ej. varios estados de cuenta en una Solicitud de Certificación
  /// pública) -- Django los recibe todos con `request.FILES.getlist(...)`.
  static Future<http.Response> postMultipartVariosArchivos(
    String endpoint,
    Map<String, String> campos,
    String fieldName,
    List<({List<int> bytes, String filename, String? contentType})> archivos,
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) async {
      final request = http.MultipartRequest('POST', url);
      final headersSinContentType = Map<String, String>.from(headers)..remove('Content-Type');
      request.headers.addAll(headersSinContentType);
      request.fields.addAll(campos);
      for (final a in archivos) {
        request.files.add(http.MultipartFile.fromBytes(
          fieldName,
          a.bytes,
          filename: a.filename,
          contentType: a.contentType != null ? MediaType.parse(a.contentType!) : null,
        ));
      }
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  /// Obtener las métricas del Dashboard Comercial para un negocio específico
  static Future<Map<String, dynamic>?> getDashboardComercial(int negocioId) async {
    final response = await get('/facturas/dashboard-comercial/?negocio=$negocioId');
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return null;
  }
}
