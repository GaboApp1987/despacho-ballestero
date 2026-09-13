/// Certificación de ingresos que un contador emite para un cliente (nuevo o
/// ya existente en su cartera) -- ver CertificacionIngreso en el backend.
class MesCertificacion {
  final String mes; // etiqueta libre, ej "Noviembre 2024"
  double ingresos;
  double egresos;

  MesCertificacion({required this.mes, this.ingresos = 0, this.egresos = 0});

  double get total => ingresos - egresos;

  factory MesCertificacion.fromJson(Map<String, dynamic> json) {
    return MesCertificacion(
      mes: json['mes'] ?? '',
      ingresos: (json['ingresos'] as num?)?.toDouble() ?? 0,
      egresos: (json['egresos'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'mes': mes, 'ingresos': ingresos, 'egresos': egresos};
}

class CertificacionIngreso {
  final int? id;
  final int? negocio;
  final String? negocioNombre;
  String nombreSolicitante;
  String cedula;
  String tipoCedulaTexto;
  String nacionalidad;
  String estadoCivil;
  String actividadEconomica;
  String numeroActividadEconomica;
  int? anosEjerciendo;
  String proposito;
  String dirigidoA;
  DateTime fechaInicio;
  DateTime fechaFin;
  String moneda;
  String modoEgresos; // 'manual' | 'porcentaje'
  double? porcentajeEgresos;
  List<MesCertificacion> datosMensuales;
  String lugarEmision;
  final double? ingresoBrutoPromedio;
  final double? ingresoNetoPromedio;

  static const Map<String, String> estadosCiviles = {
    'soltero': 'Soltero(a)',
    'casado': 'Casado(a)',
    'divorciado': 'Divorciado(a)',
    'viudo': 'Viudo(a)',
    'union_libre': 'Unión libre',
  };

  CertificacionIngreso({
    this.id,
    this.negocio,
    this.negocioNombre,
    this.nombreSolicitante = '',
    this.cedula = '',
    this.tipoCedulaTexto = '',
    this.nacionalidad = '',
    this.estadoCivil = 'soltero',
    this.actividadEconomica = '',
    this.numeroActividadEconomica = '',
    this.anosEjerciendo,
    this.proposito = '',
    this.dirigidoA = '',
    required this.fechaInicio,
    required this.fechaFin,
    this.moneda = 'CRC',
    this.modoEgresos = 'manual',
    this.porcentajeEgresos,
    List<MesCertificacion>? datosMensuales,
    this.lugarEmision = 'San José',
    this.ingresoBrutoPromedio,
    this.ingresoNetoPromedio,
  }) : datosMensuales = datosMensuales ?? [];

  factory CertificacionIngreso.fromJson(Map<String, dynamic> json) {
    return CertificacionIngreso(
      id: json['id'],
      negocio: json['negocio'],
      negocioNombre: json['negocio_nombre'],
      nombreSolicitante: json['nombre_solicitante'] ?? '',
      cedula: json['cedula'] ?? '',
      tipoCedulaTexto: json['tipo_cedula_texto'] ?? '',
      nacionalidad: json['nacionalidad'] ?? '',
      estadoCivil: json['estado_civil'] ?? 'soltero',
      actividadEconomica: json['actividad_economica'] ?? '',
      numeroActividadEconomica: json['numero_actividad_economica'] ?? '',
      anosEjerciendo: json['anos_ejerciendo'],
      proposito: json['proposito'] ?? '',
      dirigidoA: json['dirigido_a'] ?? '',
      fechaInicio: DateTime.parse(json['fecha_inicio']),
      fechaFin: DateTime.parse(json['fecha_fin']),
      moneda: json['moneda'] ?? 'CRC',
      modoEgresos: json['modo_egresos'] ?? 'manual',
      porcentajeEgresos: (json['porcentaje_egresos'] as num?)?.toDouble(),
      datosMensuales: ((json['datos_mensuales'] as List?) ?? [])
          .map((m) => MesCertificacion.fromJson(m as Map<String, dynamic>))
          .toList(),
      lugarEmision: json['lugar_emision'] ?? 'San José',
      ingresoBrutoPromedio: (json['ingreso_bruto_promedio'] as num?)?.toDouble(),
      ingresoNetoPromedio: (json['ingreso_neto_promedio'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (negocio != null) 'negocio': negocio,
        'nombre_solicitante': nombreSolicitante,
        'cedula': cedula,
        'tipo_cedula_texto': tipoCedulaTexto,
        'nacionalidad': nacionalidad,
        'estado_civil': estadoCivil,
        'actividad_economica': actividadEconomica,
        'numero_actividad_economica': numeroActividadEconomica,
        if (anosEjerciendo != null) 'anos_ejerciendo': anosEjerciendo,
        'proposito': proposito,
        'dirigido_a': dirigidoA,
        'fecha_inicio': fechaInicio.toIso8601String().split('T').first,
        'fecha_fin': fechaFin.toIso8601String().split('T').first,
        'moneda': moneda,
        'modo_egresos': modoEgresos,
        if (porcentajeEgresos != null) 'porcentaje_egresos': porcentajeEgresos,
        'datos_mensuales': datosMensuales.map((m) => m.toJson()).toList(),
        'lugar_emision': lugarEmision,
      };
}
