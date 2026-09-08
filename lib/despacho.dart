class Despacho {
  final int id;
  final String nombre;
  final String? cedulaJuridica;
  final bool tieneUsuario;
  final String? logoUrl;
  final String? emailActual;
  final int? suscripcionId;
  final String? suscripcionEstado;
  final bool suscripcionCobroAutomatico;

  Despacho({
    required this.id,
    required this.nombre,
    this.cedulaJuridica,
    required this.tieneUsuario,
    this.logoUrl,
    this.emailActual,
    this.suscripcionId,
    this.suscripcionEstado,
    this.suscripcionCobroAutomatico = false,
  });

  factory Despacho.fromJson(Map<String, dynamic> json) {
    return Despacho(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      cedulaJuridica: json['cedula_juridica'],
      tieneUsuario: json['tiene_usuario'] ?? false,
      logoUrl: json['logo'],
      emailActual: json['email_actual'],
      suscripcionId: json['suscripcion_id'],
      suscripcionEstado: json['suscripcion_estado'],
      suscripcionCobroAutomatico: json['suscripcion_cobro_automatico'] ?? false,
    );
  }
}
