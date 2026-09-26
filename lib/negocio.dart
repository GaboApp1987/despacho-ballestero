/// Datos del negocio para mostrar en el pie de página de facturas y notas
/// de crédito (Costa Rica: distinta forma de mostrar cédula física/jurídica).
class NegocioInfo {
  final String nombreComercial;
  final String cedula;
  final String tipoCedula;
  final String? correo;
  final String? direccion;
  final String? telefono;
  final String? logoUrl;

  NegocioInfo({
    required this.nombreComercial,
    required this.cedula,
    required this.tipoCedula,
    this.correo,
    this.direccion,
    this.telefono,
    this.logoUrl,
  });

  static const Map<String, String> _tiposCedula = {
    '01': 'Física',
    '02': 'Jurídica',
    '03': 'DIMEX',
    '04': 'NITE',
  };

  String get cedulaEtiquetada => "Cédula ${_tiposCedula[tipoCedula] ?? ''}: $cedula".trim();

  factory NegocioInfo.fromJson(Map<String, dynamic> json) {
    return NegocioInfo(
      nombreComercial: json['nombre_comercial'] ?? '',
      cedula: json['cedula'] ?? '',
      tipoCedula: json['tipo_cedula'] ?? '01',
      correo: json['correo_hacienda'],
      direccion: json['direccion'],
      telefono: json['telefono'],
      logoUrl: json['logo'],
    );
  }
}

class Negocio {
  final int id;
  final String nombreComercial;
  final String cedula;
  final String tipoCedula;
  final String? codigoActividad;

  // 🔥 1. DECLARAMOS LOS CAMPOS DE HACIENDA COMO OPCIONALES (CON ?)
  final String? usuarioApi;
  final String? pinLlave;
  final String? llaveCriptografica;
  final String? entornoHacienda;
  final int? socioId;
  final String? nombreSocio;
  final bool tieneUsuario;
  final String? logoUrl;
  final String? direccion;
  final String? provincia;
  final String? canton;
  final String? distrito;
  final String? telefono;
  final String? correoHacienda;
  final String? alanubeEconomicActivity;
  final int? planId;
  final String? planNombre;
  final int? limiteFacturasMensual;
  final int? facturasUsadasMes;
  final int? facturasDisponibles;
  final int? suscripcionId;
  final String? suscripcionEstado;
  final bool suscripcionCobroAutomatico;

  // 🔥 2. LOS AGREGAMOS AL CONSTRUCTOR (AQUÍ ERA DONDE FALLABA)
  Negocio({
    required this.id,
    required this.nombreComercial,
    required this.cedula,
    this.tipoCedula = '01',
    this.codigoActividad,
    this.usuarioApi,           // 👈 Ahora sí existe el parámetro
    this.pinLlave,
    this.llaveCriptografica,
    this.entornoHacienda,
    this.socioId,
    this.nombreSocio,
    this.tieneUsuario = false,
    this.logoUrl,
    this.direccion,
    this.provincia,
    this.canton,
    this.distrito,
    this.telefono,
    this.correoHacienda,
    this.alanubeEconomicActivity,
    this.planId,
    this.planNombre,
    this.limiteFacturasMensual,
    this.facturasUsadasMes,
    this.facturasDisponibles,
    this.suscripcionId,
    this.suscripcionEstado,
    this.suscripcionCobroAutomatico = false,
  });

  // 🔥 3. MAPEAMOS CORRECTAMENTE EL CONSTRUCTOR FROMJSON
  factory Negocio.fromJson(Map<String, dynamic> json) {
    return Negocio(
      id: json['id'] ?? 0,
      nombreComercial: json['nombre_comercial'] ?? json['nombreComercial'] ?? 'Sin Nombre',
      cedula: json['cedula'] ?? '',
      tipoCedula: json['tipo_cedula'] ?? '01',
      codigoActividad: json['codigo_actividad'],

      // Mapeo seguro que tolera los valores Null de la base de datos
      usuarioApi: json['usuario_api'],
      pinLlave: json['pin_llave'],
      llaveCriptografica: json['llave_criptografica'],
      entornoHacienda: json['entorno_hacienda'],
      socioId: json['socio'],
      nombreSocio: json['nombre_socio'],
      tieneUsuario: json['tiene_usuario'] ?? false,
      logoUrl: json['logo'],
      direccion: json['direccion'],
      provincia: json['provincia'],
      canton: json['canton'],
      distrito: json['distrito'],
      telefono: json['telefono'],
      correoHacienda: json['correo_hacienda'],
      alanubeEconomicActivity: json['alanube_economic_activity'],
      planId: json['plan'],
      planNombre: json['plan_nombre'],
      limiteFacturasMensual: json['limite_facturas_mensual'],
      facturasUsadasMes: json['facturas_usadas_mes'],
      facturasDisponibles: json['facturas_disponibles'],
      suscripcionId: json['suscripcion_id'],
      suscripcionEstado: json['suscripcion_estado'],
      suscripcionCobroAutomatico: json['suscripcion_cobro_automatico'] ?? false,
    );
  }
}