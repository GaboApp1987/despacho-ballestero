class Cliente {
  final int id;
  final int negocio;
  final String nombre;
  final String tipoCedula;
  final String cedula;
  final String correo;
  final String telefono;
  final String direccion;
  final String codigoActividad;

  Cliente({
    required this.id,
    required this.negocio,
    required this.nombre,
    required this.tipoCedula,
    required this.cedula,
    required this.correo,
    required this.telefono,
    required this.direccion,
    this.codigoActividad = '',
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    return Cliente(
      id: json['id'],
      negocio: json['negocio'],
      nombre: json['nombre'],
      tipoCedula: json['tipo_cedula'] ?? '01',
      cedula: json['cedula'] ?? '',
      correo: json['correo'] ?? '',
      telefono: json['telefono'] ?? '',
      direccion: json['direccion'] ?? '',
      codigoActividad: json['codigo_actividad'] ?? '',
    );
  }
}