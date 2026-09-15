/// Firmante alternativo para documentos formales (Certificación de
/// Ingresos, Atestiguamiento, Flujo de Caja Proyectado) -- para cuando
/// quien firma un documento puntual no es siempre el dueño de la cuenta
/// de Equilibra. Ver Socio.firmarConNombreRegistrado.
class FirmanteContador {
  final int? id;
  String nombre;
  String carneCpa;
  bool activo;

  FirmanteContador({
    this.id,
    this.nombre = '',
    this.carneCpa = '',
    this.activo = true,
  });

  factory FirmanteContador.fromJson(Map<String, dynamic> json) => FirmanteContador(
        id: json['id'],
        nombre: json['nombre'] ?? '',
        carneCpa: json['carne_cpa'] ?? '',
        activo: json['activo'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'carne_cpa': carneCpa,
        'activo': activo,
      };
}
