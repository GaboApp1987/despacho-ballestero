/// Actividad económica adicional que un Negocio tiene registrada ante
/// Hacienda, además de la principal (Negocio.codigoActividad). Un mismo
/// contribuyente puede facturar bajo distintas actividades según la venta
/// -- ver el selector en FormularioFactura.
class ActividadEconomica {
  final int id;
  final int negocioId;
  final String codigoActividad;
  final String? alanubeEconomicActivity;
  final String descripcion;

  ActividadEconomica({
    required this.id,
    required this.negocioId,
    required this.codigoActividad,
    this.alanubeEconomicActivity,
    this.descripcion = '',
  });

  String get etiqueta => descripcion.isNotEmpty ? "$codigoActividad - $descripcion" : codigoActividad;

  factory ActividadEconomica.fromJson(Map<String, dynamic> json) {
    return ActividadEconomica(
      id: json['id'],
      negocioId: json['negocio'],
      codigoActividad: json['codigo_actividad'] ?? '',
      alanubeEconomicActivity: json['alanube_economic_activity'],
      descripcion: json['descripcion'] ?? '',
    );
  }
}
