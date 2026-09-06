class TarjetaLealtad {
  final int id;
  final int cliente;
  final String clienteNombre;
  final String clienteCedula;
  int puntos;

  TarjetaLealtad({
    required this.id,
    required this.cliente,
    required this.clienteNombre,
    required this.clienteCedula,
    required this.puntos,
  });

  factory TarjetaLealtad.fromJson(Map<String, dynamic> json) {
    return TarjetaLealtad(
      id: json['id'],
      cliente: json['cliente'],
      clienteNombre: json['cliente_nombre'] ?? 'Cliente',
      clienteCedula: json['cliente_cedula'] ?? '',
      puntos: json['puntos'] ?? 0,
    );
  }
}

class MovimientoLealtad {
  final String tipo;
  final int puntos;
  final String descripcion;
  final String fecha;

  MovimientoLealtad({required this.tipo, required this.puntos, required this.descripcion, required this.fecha});

  factory MovimientoLealtad.fromJson(Map<String, dynamic> json) {
    return MovimientoLealtad(
      tipo: json['tipo'] ?? '',
      puntos: json['puntos'] ?? 0,
      descripcion: json['descripcion'] ?? '',
      fecha: json['fecha'] ?? '',
    );
  }

  String get etiquetaTipo {
    switch (tipo) {
      case 'acumulacion': return 'Acumulación por compra';
      case 'canje': return 'Canje';
      case 'ajuste': return 'Ajuste manual';
      default: return tipo;
    }
  }
}
