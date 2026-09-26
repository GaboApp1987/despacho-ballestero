import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Catálogo oficial de Provincia/Cantón/Distrito de Hacienda (Costa Rica),
/// el mismo que exige la Ubicación del emisor en el XML v4.3/v4.4 (ver
/// generar_xml_v44 en el backend) -- 7 provincias, 84 cantones, 492
/// distritos, extraído del archivo oficial que publica el Ministerio de
/// Hacienda (Codificacionubicacion_V4.3.xlsx) para que el negocio elija por
/// nombre en vez de tener que saber el código de memoria.
class DistritoCR {
  final String codigo; // 2 dígitos, con ceros a la izquierda (ej: "01")
  final String nombre;
  DistritoCR({required this.codigo, required this.nombre});
}

class CantonCR {
  final String codigo; // 2 dígitos
  final String nombre;
  final List<DistritoCR> distritos;
  CantonCR({required this.codigo, required this.nombre, required this.distritos});
}

class ProvinciaCR {
  final String codigo; // 1 dígito, sin ceros a la izquierda
  final String nombre;
  final List<CantonCR> cantones;
  ProvinciaCR({required this.codigo, required this.nombre, required this.cantones});
}

class UbicacionCR {
  static List<ProvinciaCR>? _cache;

  static Future<List<ProvinciaCR>> cargar() async {
    if (_cache != null) return _cache!;
    final texto = await rootBundle.loadString('assets/data/ubicaciones_cr.json');
    final data = json.decode(texto) as List;
    _cache = data.map((p) {
      final cantones = (p['cantones'] as List).map((c) {
        final distritos = (c['distritos'] as List)
            .map((d) => DistritoCR(codigo: (d['codigo'] as int).toString().padLeft(2, '0'), nombre: d['nombre']))
            .toList();
        return CantonCR(codigo: (c['codigo'] as int).toString().padLeft(2, '0'), nombre: c['nombre'], distritos: distritos);
      }).toList();
      return ProvinciaCR(codigo: (p['codigo'] as int).toString(), nombre: p['nombre'], cantones: cantones);
    }).toList();
    return _cache!;
  }
}
