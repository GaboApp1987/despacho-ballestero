class DetalleAsientoContable {
  int? cuenta;
  final String? cuentaCodigo;
  final String? cuentaNombre;
  String detalle;
  double debe;
  double haber;

  DetalleAsientoContable({
    this.cuenta,
    this.cuentaCodigo,
    this.cuentaNombre,
    this.detalle = '',
    this.debe = 0,
    this.haber = 0,
  });

  factory DetalleAsientoContable.fromJson(Map<String, dynamic> json) => DetalleAsientoContable(
        cuenta: json['cuenta'],
        cuentaCodigo: json['cuenta_codigo'],
        cuentaNombre: json['cuenta_nombre'],
        detalle: json['detalle'] ?? '',
        debe: double.tryParse(json['debe']?.toString() ?? '0') ?? 0,
        haber: double.tryParse(json['haber']?.toString() ?? '0') ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'cuenta': cuenta,
        'detalle': detalle,
        'debe': debe,
        'haber': haber,
      };
}

class AsientoContable {
  final int? id;
  final int negocio;
  final String? negocioNombre;
  final int? numero;
  DateTime fecha;
  String concepto;
  String referencia;
  List<DetalleAsientoContable> detalles;

  AsientoContable({
    this.id,
    required this.negocio,
    this.negocioNombre,
    this.numero,
    DateTime? fecha,
    this.concepto = '',
    this.referencia = '',
    List<DetalleAsientoContable>? detalles,
  })  : fecha = fecha ?? DateTime.now(),
        detalles = detalles ?? [];

  double get totalDebe => detalles.fold(0.0, (s, d) => s + d.debe);
  double get totalHaber => detalles.fold(0.0, (s, d) => s + d.haber);
  bool get cuadrado => (totalDebe - totalHaber).abs() < 0.005;

  factory AsientoContable.fromJson(Map<String, dynamic> json) => AsientoContable(
        id: json['id'],
        negocio: json['negocio'],
        negocioNombre: json['negocio_nombre'],
        numero: json['numero'],
        fecha: json['fecha'] != null ? DateTime.tryParse(json['fecha']) : null,
        concepto: json['concepto'] ?? '',
        referencia: json['referencia'] ?? '',
        detalles: ((json['detalles'] as List?) ?? []).map((d) => DetalleAsientoContable.fromJson(d)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'negocio': negocio,
        'fecha': fecha.toIso8601String().split('T').first,
        'concepto': concepto,
        'referencia': referencia,
        'detalles': detalles.map((d) => d.toJson()).toList(),
      };
}
