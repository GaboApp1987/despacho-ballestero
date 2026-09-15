import 'impuesto.dart'; // <--- Esto trae la definición única de Impuesto

class Categoria {
  final int id;
  final String nombre;

  Categoria({required this.id, required this.nombre});

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(
      id: json['id'],
      nombre: json['nombre'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
    };
  }
}

/// Empaque/presentación alternativa de un producto (ej. "Caja" = 20 kg),
/// usada para convertir notas escritas a mano ("1 caja") a la unidad real
/// del inventario. Ver PresentacionProducto en el backend.
class PresentacionProducto {
  final int id;
  final int productoId;
  final String nombre;
  final double equivalencia;

  PresentacionProducto({
    required this.id,
    required this.productoId,
    required this.nombre,
    required this.equivalencia,
  });

  factory PresentacionProducto.fromJson(Map<String, dynamic> json) {
    return PresentacionProducto(
      id: json['id'],
      productoId: json['producto'],
      nombre: json['nombre'] ?? '',
      equivalencia: double.tryParse(json['equivalencia'].toString()) ?? 0.0,
    );
  }
}

class Producto {
  final int id;
  final String nombre;
  final String codigoCabys;
  final String unidadMedida;
  final double precioUnitario;
  final double costo;
  final double margenGanancia;
  final int? categoriaId;
  final String? nombreCategoria;
  final int stock;
  final Impuesto? impuesto; // Usa la clase del archivo importado
  final String? imagenUrl;
  final List<PresentacionProducto> presentaciones;
  // "mercancia" (bien físico) o "servicio" -- Hacienda exige reportarlos por
  // separado en el resumen de cada factura (ver Producto.tipo en el backend).
  final String tipo;

  Producto({
    required this.id,
    required this.nombre,
    required this.codigoCabys,
    this.unidadMedida = 'Unid',
    required this.precioUnitario,
    this.costo = 0,
    this.margenGanancia = 30,
    this.categoriaId,
    this.nombreCategoria,
    required this.stock,
    this.impuesto,
    this.imagenUrl,
    this.presentaciones = const [],
    this.tipo = 'mercancia',
  });

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'],
      nombre: json['nombre'],
      codigoCabys: json['codigo_cabys'] ?? '',
      unidadMedida: json['unidad_medida'] ?? 'Unid',
      precioUnitario: double.tryParse(json['precio_unitario'].toString()) ?? 0.0,
      costo: double.tryParse(json['costo']?.toString() ?? '') ?? 0.0,
      margenGanancia: double.tryParse(json['margen_ganancia']?.toString() ?? '') ?? 30.0,
      categoriaId: json['categoria'],
      nombreCategoria: json['nombre_categoria'],
      stock: json['stock'] ?? 0,
      // Mapeamos usando los datos que vienen de Django
      impuesto: json['impuesto_detalle'] != null
          ? Impuesto.fromJson(json['impuesto_detalle'])
          : null,
      imagenUrl: json['imagen'],
      presentaciones: (json['presentaciones'] as List? ?? [])
          .map((p) => PresentacionProducto.fromJson(p))
          .toList(),
      tipo: json['tipo'] ?? 'mercancia',
    );
  }

  // 🛠️ MÉTODO TOJSON AGREGADO PARA SERIALIZAR EN PUT/POST
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'codigo_cabys': codigoCabys,
      'unidad_medida': unidadMedida,
      'precio_unitario': precioUnitario,
      'costo': costo,
      'margen_ganancia': margenGanancia,
      'categoria': categoriaId,
      'stock': stock,
      'tipo': tipo,
      if (impuesto != null) 'impuesto': impuesto!.id, // Si Impuesto tiene un campo 'id'
    };
  }
}

/// "mercancia" (bien físico) o "servicio" -- ver Producto.tipo.
const Map<String, String> tiposProducto = {
  'mercancia': 'Mercancía',
  'servicio': 'Servicio',
};

/// Catálogo (curado, no exhaustivo) de unidades de medida oficiales de
/// Hacienda para la facturación electrónica v4.3. Los códigos y mayúsculas
/// deben coincidir EXACTO con lo que Alanube valida (confirmado por su
/// propio error AP0079 "Value must be one of: ..."); versiones previas de
/// este catálogo incluían códigos que Hacienda en realidad no acepta
/// ('kg' en vez de 'Kg', 'cm' en vez de 'Cm', 'm2'/'m3' en vez de 'm²'/'m³',
/// y 'g', 'm', 'h', 'd', 'Kit', 'Pqt', 'Doc' que no existen en su catálogo
/// real), lo que hacía que la factura se guardara bien pero Hacienda la
/// rechazara después con "Error Técnico" al no poder validar la unidad.
/// "Kit"/"Paquete"/"Docena" no son unidades de Hacienda -- ese caso ya lo
/// cubre PresentacionProducto (ver Producto.presentaciones): la unidad real
/// del producto es "Unid" y la presentación (ej. "Caja" = 20 Unid) es solo
/// una equivalencia para interpretar notas, no algo que se declare ante
/// Hacienda.
const Map<String, String> unidadesMedidaHacienda = {
  'Unid': 'Unidad',
  'Sp': 'Servicios profesionales',
  'St': 'Servicios técnicos',
  'Os': 'Otros servicios',
  'Kg': 'Kilogramo',
  'L': 'Litro',
  'mL': 'Mililitro',
  'M': 'Metro',
  'Cm': 'Centímetro',
  'Km': 'Kilómetro',
  'm²': 'Metro cuadrado',
  'm³': 'Metro cúbico',
  'Min': 'Minuto',
  'Otros': 'Otros',
};