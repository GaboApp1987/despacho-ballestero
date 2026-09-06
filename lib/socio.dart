class Socio {
  final int id;
  final String nombre;
  final String email;
  final bool tieneUsuario;
  final int cantidadNegocios;
  final String? logoUrl;

  Socio({
    required this.id,
    required this.nombre,
    required this.email,
    required this.tieneUsuario,
    this.cantidadNegocios = 0,
    this.logoUrl,
  });

  factory Socio.fromJson(Map<String, dynamic> json) {
    return Socio(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      email: json['email'] ?? '',
      tieneUsuario: json['tiene_usuario'] ?? false,
      cantidadNegocios: (json['negocios'] as List?)?.length ?? 0,
      logoUrl: json['logo'],
    );
  }
}
