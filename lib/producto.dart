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
  // Moneda del precio de venta: 'CRC' o 'USD' (ej. un alquiler que se cobra
  // en dólares) -- ver Producto.moneda_precio en el backend.
  final String monedaPrecio;

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
    this.monedaPrecio = 'CRC',
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
      monedaPrecio: json['moneda_precio'] ?? 'CRC',
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
      'moneda_precio': monedaPrecio,
      if (impuesto != null) 'impuesto': impuesto!.id, // Si Impuesto tiene un campo 'id'
    };
  }
}

/// "mercancia" (bien físico) o "servicio" -- ver Producto.tipo.
const Map<String, String> tiposProducto = {
  'mercancia': 'Mercancía',
  'servicio': 'Servicio',
};

/// Unidades de medida de Hacienda para la factura electrónica v4.4 (las
/// de uso común; el catálogo oficial completo tiene ~100 y el backend las
/// acepta todas, ver UNIDADES_MEDIDA_HACIENDA en gestion/utils.py).
/// Códigos verificados contra FacturaElectronica_V4.4.xsd (UnidadMedidaType):
/// ojo que distingue mayúsculas -- "Cm" es COMISIONES y "cm" es centímetro,
/// "G" es gramo, "D" es día y "h" es hora. Antes este catálogo tenía "Cm"
/// rotulado como centímetro, así que esos productos salían ante Hacienda
/// como comisiones (la migración 0107 los pasó a "cm").
/// "Kit"/"Paquete"/"Docena" no son unidades de Hacienda -- ese caso ya lo
/// cubre PresentacionProducto (ver Producto.presentaciones): la unidad real
/// del producto es "Unid" y la presentación (ej. "Caja" = 20 Unid) es solo
/// una equivalencia para interpretar notas, no algo que se declare ante
/// Hacienda.
const Map<String, String> unidadesMedidaHacienda = {
  'Unid': 'Unidad',
  // Servicios
  'Sp': 'Servicios profesionales',
  'Spe': 'Servicios personales',
  'St': 'Servicios técnicos',
  'Os': 'Otro tipo de servicio',
  'Al': 'Alquiler de uso habitacional',
  'Alc': 'Alquiler de uso comercial',
  'Cm': 'Comisiones',
  'I': 'Intereses',
  // Tiempo
  'h': 'Hora',
  'D': 'Día',
  'Min': 'Minuto',
  // Peso
  'G': 'Gramo',
  'Kg': 'Kilogramo',
  'Oz': 'Onza',
  'Qq': 'Quintal',
  'T': 'Tonelada',
  // Volumen
  'mL': 'Mililitro',
  'L': 'Litro',
  'Gal': 'Galón',
  'm³': 'Metro cúbico',
  // Longitud y superficie
  'Mm': 'Milímetro',
  'cm': 'Centímetro',
  'Ln': 'Pulgada',
  'M': 'Metro',
  'Km': 'Kilómetro',
  'm²': 'Metro cuadrado',
  // Energía
  'Kw': 'Kilovatio',
  'kWh': 'Kilovatio hora',
  'Otros': 'Otros',
};

/// Unidades que corresponden a servicios (mismo criterio que
/// UNIDADES_SERVICIO en gestion/utils.py).
const Set<String> unidadesDeServicio = {'Sp', 'Spe', 'St', 'Os', 'Al', 'Alc', 'Cm', 'I'};
