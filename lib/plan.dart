/// Plan de suscripción de un NEGOCIO. Se hacen cumplir solo los límites
/// numéricos (documentos por período, usuarios y consultas de IA al mes);
/// `incluye` es informativo. null en un límite = ilimitado.
class Plan {
  final int id;
  final String nombre;
  /// Documentos por PERÍODO del plan (mes, o año si [esAnual]). null = ilimitados.
  final int? limiteFacturasMensual;
  /// Precio por período (mes, o año si [esAnual]).
  final double? precioMensual;
  final String descripcion;
  final bool activo;
  final String periodicidad;
  final String paraQuien;
  final List<String> incluye;
  final int? limiteUsuarios;
  final int? limiteConsultasIa;
  final double? precioDocumentoExtra;
  final int? recargaDocumentos;
  final double? recargaPrecio;
  final bool destacado;
  final int orden;

  Plan({
    required this.id,
    required this.nombre,
    this.limiteFacturasMensual,
    this.precioMensual,
    this.descripcion = '',
    this.activo = true,
    this.periodicidad = 'mensual',
    this.paraQuien = '',
    this.incluye = const [],
    this.limiteUsuarios,
    this.limiteConsultasIa,
    this.precioDocumentoExtra,
    this.recargaDocumentos,
    this.recargaPrecio,
    this.destacado = false,
    this.orden = 0,
  });

  static double? _dec(dynamic v) => v == null ? null : double.tryParse(v.toString());

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      limiteFacturasMensual: json['limite_facturas_mensual'],
      precioMensual: _dec(json['precio_mensual']),
      descripcion: json['descripcion'] ?? '',
      activo: json['activo'] ?? true,
      periodicidad: json['periodicidad'] ?? 'mensual',
      paraQuien: json['para_quien'] ?? '',
      incluye: (json['incluye'] ?? '').toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
      limiteUsuarios: json['limite_usuarios'],
      limiteConsultasIa: json['limite_consultas_ia'],
      precioDocumentoExtra: _dec(json['precio_documento_extra']),
      recargaDocumentos: json['recarga_documentos'],
      recargaPrecio: _dec(json['recarga_precio']),
      destacado: json['destacado'] ?? false,
      orden: json['orden'] ?? 0,
    );
  }

  bool get esAnual => periodicidad == 'anual';
  String get unidadPeriodo => esAnual ? 'año' : 'mes';
  bool get documentosIlimitados => limiteFacturasMensual == null;

  /// Para comparar planes de distinta periodicidad (subir/bajar de plan).
  double? get precioMensualEquivalente => precioMensual == null ? null : (esAnual ? precioMensual! / 12 : precioMensual);

  String get textoDocumentos =>
      documentosIlimitados ? "Documentos ilimitados" : "$limiteFacturasMensual documentos al $unidadPeriodo";

  String get textoUsuarios => limiteUsuarios == null
      ? "Usuarios ilimitados"
      : "$limiteUsuarios usuario${limiteUsuarios == 1 ? '' : 's'}";

  String get textoConsultasIa =>
      limiteConsultasIa == null ? "IA ilimitada" : "$limiteConsultasIa consultas de IA al mes";

  /// "Documentos ilimitados · 2 usuarios · 30 consultas de IA al mes"
  String get resumenLimites => [textoDocumentos, textoUsuarios, textoConsultasIa].join(' · ');

  @override
  String toString() => '$nombre ($textoDocumentos)';
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
