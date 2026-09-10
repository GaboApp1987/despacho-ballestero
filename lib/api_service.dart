import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // URL base del servidor Django. Por defecto apunta a local (para "flutter
  // run" normal, sin tocar nada). Para compilar apuntando a producción:
  //   flutter build windows --dart-define=API_BASE_URL=https://web-production-925bf0.up.railway.app/api
  // o para probar en caliente contra producción con hot reload:
  //   flutter run -d windows --dart-define=API_BASE_URL=https://web-production-925bf0.up.railway.app/api
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  /// Obtiene el token guardado en el dispositivo
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  /// Guarda el access token (y el refresh token, si viene) tras el login.
  static Future<void> saveTokens({required String access, String? refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', access);
    if (refresh != null) {
      await prefs.setString('refresh_token', refresh);
    }
  }

  /// Elimina los tokens guardados (cierre de sesión)
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
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
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString('refresh_token');
    if (refresh == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh': refresh}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await prefs.setString('token', data['access']);
        // Con ROTATE_REFRESH_TOKENS=True el backend invalida el refresh
        // token usado y manda uno nuevo en la misma respuesta -- si no lo
        // guardamos aca, la proxima renovacion (unas horas despues) falla
        // con el refresh token ya invalidado y la sesion se cierra sola,
        // justo lo contrario de lo que se buscaba con la rotacion.
        if (data['refresh'] != null) {
          await prefs.setString('refresh_token', data['refresh']);
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
    String filename,
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    return _conRenovacion((headers) async {
      final request = http.MultipartRequest('POST', url);
      final headersSinContentType = Map<String, String>.from(headers)..remove('Content-Type');
      request.headers.addAll(headersSinContentType);
      request.fields.addAll(campos);
      request.files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: filename));
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
