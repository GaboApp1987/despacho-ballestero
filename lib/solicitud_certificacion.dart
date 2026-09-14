class SolicitudArchivoAdjunto {
  final int id;
  final String archivoUrl;
  final String nombreOriginal;

  SolicitudArchivoAdjunto({required this.id, required this.archivoUrl, required this.nombreOriginal});

  factory SolicitudArchivoAdjunto.fromJson(Map<String, dynamic> json) => SolicitudArchivoAdjunto(
        id: json['id'],
        archivoUrl: json['archivo'] ?? '',
        nombreOriginal: json['nombre_original'] ?? '',
      );
}

/// Solicitud de Certificación de Ingresos que un cliente llena por su
/// cuenta desde el link público del contador (sin login) -- ver
/// SolicitudCertificacion en el backend.
class SolicitudCertificacion {
  final int id;
  final String estado; // 'pendiente' | 'completada'
  final String nombreSolicitante;
  final String cedula;
  final String tipoCedulaTexto;
  final String nacionalidad;
  final String estadoCivil;
  final String actividadEconomica;
  final String numeroActividadEconomica;
  final List<String> actividades;
  final int? anosEjerciendo;
  final String proposito;
  final String dirigidoA;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final String moneda;
  final String telefonoContacto;
  final String correoContacto;
  final String mensajeCliente;
  final List<SolicitudArchivoAdjunto> archivosAdjuntos;
  final DateTime creadoEn;

  SolicitudCertificacion({
    required this.id,
    required this.estado,
    required this.nombreSolicitante,
    required this.cedula,
    this.tipoCedulaTexto = '',
    this.nacionalidad = '',
    this.estadoCivil = '',
    this.actividadEconomica = '',
    this.numeroActividadEconomica = '',
    List<String>? actividades,
    this.anosEjerciendo,
    this.proposito = '',
    this.dirigidoA = '',
    this.fechaInicio,
    this.fechaFin,
    this.moneda = 'CRC',
    this.telefonoContacto = '',
    this.correoContacto = '',
    this.mensajeCliente = '',
    List<SolicitudArchivoAdjunto>? archivosAdjuntos,
    required this.creadoEn,
  })  : actividades = actividades ?? [],
        archivosAdjuntos = archivosAdjuntos ?? [];

  factory SolicitudCertificacion.fromJson(Map<String, dynamic> json) => SolicitudCertificacion(
        id: json['id'],
        estado: json['estado'] ?? 'pendiente',
        nombreSolicitante: json['nombre_solicitante'] ?? '',
        cedula: json['cedula'] ?? '',
        tipoCedulaTexto: json['tipo_cedula_texto'] ?? '',
        nacionalidad: json['nacionalidad'] ?? '',
        estadoCivil: json['estado_civil'] ?? '',
        actividadEconomica: json['actividad_economica'] ?? '',
        numeroActividadEconomica: json['numero_actividad_economica'] ?? '',
        actividades: ((json['actividades'] as List?) ?? []).map((a) => a.toString()).toList(),
        anosEjerciendo: json['anos_ejerciendo'],
        proposito: json['proposito'] ?? '',
        dirigidoA: json['dirigido_a'] ?? '',
        fechaInicio: json['fecha_inicio'] != null ? DateTime.tryParse(json['fecha_inicio']) : null,
        fechaFin: json['fecha_fin'] != null ? DateTime.tryParse(json['fecha_fin']) : null,
        moneda: json['moneda'] ?? 'CRC',
        telefonoContacto: json['telefono_contacto'] ?? '',
        correoContacto: json['correo_contacto'] ?? '',
        mensajeCliente: json['mensaje_cliente'] ?? '',
        archivosAdjuntos: ((json['archivos_adjuntos'] as List?) ?? []).map((a) => SolicitudArchivoAdjunto.fromJson(a)).toList(),
        creadoEn: DateTime.tryParse(json['creado_en'] ?? '') ?? DateTime.now(),
      );
}
