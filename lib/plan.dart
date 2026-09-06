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
