/// Plan de suscripción (nivel plataforma): define cuántas facturas
/// electrónicas puede emitir un negocio por mes.
class Plan {
  final int id;
  final String nombre;
  final int limiteFacturasMensual;
  final double? precioMensual;
  final String descripcion;
  final bool activo;

  Plan({
    required this.id,
    required this.nombre,
    required this.limiteFacturasMensual,
    this.precioMensual,
    this.descripcion = '',
    this.activo = true,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      limiteFacturasMensual: json['limite_facturas_mensual'] ?? 0,
      precioMensual: json['precio_mensual'] != null
          ? double.tryParse(json['precio_mensual'].toString())
          : null,
      descripcion: json['descripcion'] ?? '',
      activo: json['activo'] ?? true,
    );
  }

  @override
  String toString() => '$nombre ($limiteFacturasMensual facturas/mes)';
}

/// Plan de suscripción para un contador independiente: define cuántos
/// negocios (clientes) puede tener a cargo. null = ilimitado.
class PlanContador {
  final int id;
  final String nombre;
  final int? limiteNegocios;
  final double? precioMensual;
  final String descripcion;
  final bool activo;

  PlanContador({
    required this.id,
    required this.nombre,
    this.limiteNegocios,
    this.precioMensual,
    this.descripcion = '',
    this.activo = true,
  });

  factory PlanContador.fromJson(Map<String, dynamic> json) {
    return PlanContador(
      id: json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      limiteNegocios: json['limite_negocios'],
      precioMensual: json['precio_mensual'] != null
          ? double.tryParse(json['precio_mensual'].toString())
          : null,
      descripcion: json['descripcion'] ?? '',
      activo: json['activo'] ?? true,
    );
  }
}

/// Plan de suscripción para un Despacho: define cuántos contadores puede
/// tener a cargo. null = ilimitado.
class PlanDespacho {
  final int id;
  final String nombre;
  final int? limiteContadores;
  final double? precioMensual;
  final String descripcion;
  final bool activo;

  PlanDespacho({
    required this.id,
    required this.nombre,
    this.limiteContadores,
    this.precioMensual,
    this.descripcion = '',
    this.activo = true,
  });

  factory PlanDespacho.fromJson(Map<String, dynamic> json) {
    return PlanDespacho(
      id: json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      limiteContadores: json['limite_contadores'],
      precioMensual: json['precio_mensual'] != null
          ? double.tryParse(json['precio_mensual'].toString())
          : null,
      descripcion: json['descripcion'] ?? '',
      activo: json['activo'] ?? true,
    );
  }
}
