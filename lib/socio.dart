import 'firmante_contador.dart';

class Socio {
  final int id;
  final String nombre;
  final String email;
  final bool tieneUsuario;
  final int cantidadNegocios;
  final String? logoUrl;
  final String codigoPublico;
  final bool firmarConNombreRegistrado;
  final List<FirmanteContador> firmantes;

  Socio({
    required this.id,
    required this.nombre,
    required this.email,
    required this.tieneUsuario,
    this.cantidadNegocios = 0,
    this.logoUrl,
    this.codigoPublico = '',
    this.firmarConNombreRegistrado = true,
    List<FirmanteContador>? firmantes,
  }) : firmantes = firmantes ?? [];

  factory Socio.fromJson(Map<String, dynamic> json) {
    return Socio(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      email: json['email'] ?? '',
      tieneUsuario: json['tiene_usuario'] ?? false,
      cantidadNegocios: (json['negocios'] as List?)?.length ?? 0,
      logoUrl: json['logo'],
      codigoPublico: json['codigo_publico'] ?? '',
      firmarConNombreRegistrado: json['firmar_con_nombre_registrado'] ?? true,
      firmantes: ((json['firmantes'] as List?) ?? []).map((f) => FirmanteContador.fromJson(f)).toList(),
    );
  }
}
