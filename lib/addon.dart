class Addon {
  final int id;
  final String nombre;
  final String descripcion;
  final double precioPorMensaje;

  Addon({required this.id, required this.nombre, required this.descripcion, required this.precioPorMensaje});

  factory Addon.fromJson(Map<String, dynamic> json) {
    return Addon(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'] ?? '',
      precioPorMensaje: double.tryParse(json['precio_por_mensaje'].toString()) ?? 0,
    );
  }
}

/// La relación de contratación de un Addon con un Negocio en particular
/// (si está activo, cuántos mensajes lleva enviados este mes y su costo).
class NegocioAddon {
  final int id;
  final int addonId;
  final String addonNombre;
  final String addonDescripcion;
  final double precioPorMensaje;
  bool activo;
  final int mensajesEsteMes;
  final double costoEsteMes;

  NegocioAddon({
    required this.id,
    required this.addonId,
    required this.addonNombre,
    required this.addonDescripcion,
    required this.precioPorMensaje,
    required this.activo,
    required this.mensajesEsteMes,
    required this.costoEsteMes,
  });

  factory NegocioAddon.fromJson(Map<String, dynamic> json) {
    return NegocioAddon(
      id: json['id'],
      addonId: json['addon'],
      addonNombre: json['addon_nombre'] ?? '',
      addonDescripcion: json['addon_descripcion'] ?? '',
      precioPorMensaje: double.tryParse(json['precio_por_mensaje'].toString()) ?? 0,
      activo: json['activo'] ?? false,
      mensajesEsteMes: json['mensajes_este_mes'] ?? 0,
      costoEsteMes: double.tryParse(json['costo_este_mes'].toString()) ?? 0,
    );
  }
}
