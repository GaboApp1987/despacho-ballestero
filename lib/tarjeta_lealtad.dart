class TarjetaLealtad {
  final int id;
  final int cliente;
  final String clienteNombre;
  final String clienteCedula;
  final String clienteTelefono;
  int puntos;
  int sellos;
  final String codigo;
  final String url;
  final bool enGoogleWallet;

  TarjetaLealtad({
    required this.id,
    required this.cliente,
    required this.clienteNombre,
    required this.clienteCedula,
    this.clienteTelefono = '',
    required this.puntos,
    this.sellos = 0,
    this.codigo = '',
    this.url = '',
    this.enGoogleWallet = false,
  });

  factory TarjetaLealtad.fromJson(Map<String, dynamic> json) {
    return TarjetaLealtad(
      id: json['id'],
      cliente: json['cliente'],
      clienteNombre: json['cliente_nombre'] ?? 'Cliente',
      clienteCedula: json['cliente_cedula'] ?? '',
      clienteTelefono: json['cliente_telefono'] ?? '',
      puntos: json['puntos'] ?? 0,
      sellos: json['sellos'] ?? 0,
      codigo: json['codigo'] ?? '',
      url: json['url'] ?? '',
      enGoogleWallet: json['en_google_wallet'] == true,
    );
  }
}

/// Cómo funciona la tarjeta del negocio (GET/PATCH /lealtad/programa/).
class ProgramaLealtad {
  String modo; // puntos | sellos | ambos
  int colonesPorPunto;
  int sellosMeta;
  String premioSellos;
  int montoMinimoSello;
  String color;
  final String urlPublica;
  final String qrPng;
  final bool googleWallet;
  final int tarjetas;
  final int enGoogleWallet;
  final int avisosDisponiblesHoy;
  final List<Map<String, dynamic>> avisos;

  ProgramaLealtad({
    required this.modo,
    required this.colonesPorPunto,
    required this.sellosMeta,
    required this.premioSellos,
    required this.montoMinimoSello,
    required this.color,
    required this.urlPublica,
    required this.qrPng,
    required this.googleWallet,
    required this.tarjetas,
    required this.enGoogleWallet,
    required this.avisosDisponiblesHoy,
    required this.avisos,
  });

  bool get usaPuntos => modo == 'puntos' || modo == 'ambos';
  bool get usaSellos => modo == 'sellos' || modo == 'ambos';

  factory ProgramaLealtad.fromJson(Map<String, dynamic> json) {
    return ProgramaLealtad(
      modo: json['modo'] ?? 'puntos',
      colonesPorPunto: json['colones_por_punto'] ?? 1000,
      sellosMeta: json['sellos_meta'] ?? 10,
      premioSellos: json['premio_sellos'] ?? '',
      montoMinimoSello: json['monto_minimo_sello'] ?? 0,
      color: json['color'] ?? '#1E3A8A',
      urlPublica: json['url_publica'] ?? '',
      qrPng: json['qr_png'] ?? '',
      googleWallet: json['google_wallet'] == true,
      tarjetas: json['tarjetas'] ?? 0,
      enGoogleWallet: json['en_google_wallet'] ?? 0,
      avisosDisponiblesHoy: json['avisos_disponibles_hoy'] ?? 0,
      avisos: ((json['avisos'] as List?) ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList(),
    );
  }
}

class MovimientoLealtad {
  final String tipo;
  final int puntos;
  final int sellos;
  final String descripcion;
  final String fecha;

  MovimientoLealtad({required this.tipo, required this.puntos, this.sellos = 0, required this.descripcion, required this.fecha});

  factory MovimientoLealtad.fromJson(Map<String, dynamic> json) {
    return MovimientoLealtad(
      tipo: json['tipo'] ?? '',
      puntos: json['puntos'] ?? 0,
      sellos: json['sellos'] ?? 0,
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
