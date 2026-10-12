import 'dart:convert';

import 'package:despacho_app/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

http.Response _r(int codigo, String cuerpo) => http.Response.bytes(utf8.encode(cuerpo), codigo);

void main() {
  group('mensajeError', () {
    test('usa el detail del servidor', () {
      expect(ApiService.mensajeError(_r(400, '{"detail": "Es una nota de crédito."}')), 'Es una nota de crédito.');
    });

    test('error de un campo con su nombre legible, no el técnico', () {
      expect(ApiService.mensajeError(_r(400, '{"numero_factura_proveedor": ["Este campo es requerido."]}')),
          'Número de factura: Este campo es requerido.');
      expect(ApiService.mensajeError(_r(400, '{"codigo_actividad": ["No válido."]}')), 'Código actividad: No válido.');
      expect(ApiService.mensajeError(_r(400, '{"non_field_errors": ["Ya existe."]}')), 'Ya existe.');
    });

    test('errores anidados de líneas', () {
      expect(ApiService.mensajeError(_r(400, '{"detalles_compra": [{}, {"producto": ["No existe."]}]}')), 'Producto: No existe.');
    });

    test('página HTML de error o cuerpo vacío: mensaje según el código', () {
      expect(ApiService.mensajeError(_r(500, '<!doctype html><h1>Server Error (500)</h1>')), contains('error en el servidor'));
      expect(ApiService.mensajeError(_r(502, '')), contains('Probá de nuevo en un minuto'));
      expect(ApiService.mensajeError(_r(403, '')), 'No tenés permiso para hacer esto.');
    });
  });

  group('textoError', () {
    test('sin "Exception:" ni detalles internos', () {
      expect(ApiService.textoError(Exception('No hay caja abierta.')), 'No hay caja abierta.');
      expect(ApiService.textoError(Exception('ClientException: Failed to fetch, uri=https://x/api/')),
          contains('No hay conexión con el servidor'));
      expect(ApiService.textoError(TypeError()), isNot(contains('TypeError')));
      expect(ApiService.textoError("type 'Null' is not a subtype of type 'String'"), contains('Algo salió mal'));
    });

    test('si alguien metió el JSON crudo, saca el mensaje', () {
      expect(ApiService.textoError(Exception('{"detail":"Sin permiso."}')), 'Sin permiso.');
    });
  });
}
