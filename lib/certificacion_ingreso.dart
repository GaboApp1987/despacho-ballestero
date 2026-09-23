/// Certificación de ingresos que un contador emite para un cliente (nuevo o
/// ya existente en su cartera) -- ver CertificacionIngreso en el backend.
class MesCertificacion {
  final String mes; // etiqueta libre, ej "Noviembre 2024"
  // Un monto por actividad económica, en el MISMO ORDEN que
  // CertificacionIngreso.actividades -- por posición, no por nombre, para
  // que renombrar una actividad no desordene los montos ya cargados.
  List<double> ingresosPorActividad;
  double egresos;

  MesCertificacion({required this.mes, List<double>? ingresosPorActividad, this.egresos = 0})
      : ingresosPorActividad = ingresosPorActividad ?? [0];

  double get ingresos => ingresosPorActividad.fold(0.0, (a, b) => a + b);
  double get total => ingresos - egresos;

  factory MesCertificacion.fromJson(Map<String, dynamic> json) {
    final lista = json['ingresos_por_actividad'] as List?;
    return MesCertificacion(
      mes: json['mes'] ?? '',
      ingresosPorActividad: (lista != null && lista.isNotEmpty)
          ? lista.map((v) => (v as num).toDouble()).toList()
          : [(json['ingresos'] as num?)?.toDouble() ?? 0],
      egresos: (json['egresos'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'mes': mes,
        'ingresos_por_actividad': ingresosPorActividad,
        'ingresos': ingresos,
        'egresos': egresos,
      };
}

class CertificacionIngreso {
  final int? id;
  final int? negocio;
  final String? negocioNombre;
  final String? socioNombre;
  int? firmante;
  final String? firmanteNombre;
  String nombreSolicitante;
  String cedula;
  String tipoCedulaTexto;
  String nacionalidad;
  String direccion;
  String estadoCivil;
  String actividadEconomica;
  // Nombres de las actividades a certificar -- si tiene más de un
  // elemento, la tabla de 12 meses muestra una columna de ingresos por
  // cada una (igual que el formato real que ya usa el despacho).
  List<String> actividades;
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
  final DateTime? creadoEn;

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
    this.socioNombre,
    this.firmante,
    this.firmanteNombre,
    this.nombreSolicitante = '',
    this.cedula = '',
    this.tipoCedulaTexto = '',
    this.nacionalidad = '',
    this.direccion = '',
    this.estadoCivil = 'soltero',
    this.actividadEconomica = '',
    List<String>? actividades,
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
    this.creadoEn,
  })  : datosMensuales = datosMensuales ?? [],
        actividades = actividades ?? [];

  factory CertificacionIngreso.fromJson(Map<String, dynamic> json) {
    return CertificacionIngreso(
      id: json['id'],
      negocio: json['negocio'],
      negocioNombre: json['negocio_nombre'],
      socioNombre: json['socio_nombre'],
      firmante: json['firmante'],
      firmanteNombre: json['firmante_nombre'],
      nombreSolicitante: json['nombre_solicitante'] ?? '',
      cedula: json['cedula'] ?? '',
      tipoCedulaTexto: json['tipo_cedula_texto'] ?? '',
      nacionalidad: json['nacionalidad'] ?? '',
      direccion: json['direccion'] ?? '',
      estadoCivil: json['estado_civil'] ?? 'soltero',
      actividadEconomica: json['actividad_economica'] ?? '',
      actividades: ((json['actividades'] as List?) ?? []).map((a) => a.toString()).toList(),
      numeroActividadEconomica: json['numero_actividad_economica'] ?? '',
      anosEjerciendo: json['anos_ejerciendo'],
      proposito: json['proposito'] ?? '',
      dirigidoA: json['dirigido_a'] ?? '',
      fechaInicio: DateTime.parse(json['fecha_inicio']),
      fechaFin: DateTime.parse(json['fecha_fin']),
      moneda: json['moneda'] ?? 'CRC',
      modoEgresos: json['modo_egresos'] ?? 'manual',
      // Django manda un DecimalField como STRING en el JSON (ej. "25.00"),
      // no como num -- un "as num?" directo tira TypeError apenas se guarda
      // un porcentaje real. double.tryParse acepta String o num.toString().
      porcentajeEgresos: json['porcentaje_egresos'] != null ? double.tryParse(json['porcentaje_egresos'].toString()) : null,
      datosMensuales: ((json['datos_mensuales'] as List?) ?? [])
          .map((m) => MesCertificacion.fromJson(m as Map<String, dynamic>))
          .toList(),
      lugarEmision: json['lugar_emision'] ?? 'San José',
      ingresoBrutoPromedio: (json['ingreso_bruto_promedio'] as num?)?.toDouble(),
      ingresoNetoPromedio: (json['ingreso_neto_promedio'] as num?)?.toDouble(),
      creadoEn: json['creado_en'] != null ? DateTime.tryParse(json['creado_en']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (negocio != null) 'negocio': negocio,
        if (firmante != null) 'firmante': firmante,
        'nombre_solicitante': nombreSolicitante,
        'cedula': cedula,
        'tipo_cedula_texto': tipoCedulaTexto,
        'nacionalidad': nacionalidad,
        'direccion': direccion,
        'estado_civil': estadoCivil,
        'actividad_economica': actividadEconomica,
        'actividades': actividades,
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
