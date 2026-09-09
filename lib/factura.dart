import 'negocio.dart';

class DetalleFacturaItem {
  final int? id;
  final int productoId;
  final String nombreProducto;
  final String codigoCabys;
  final int cantidad;
  final double precioUnitario;
  final double montoIva;
  final double subtotal;
  final bool yaAcreditado;

  DetalleFacturaItem({
    this.id,
    required this.productoId,
    required this.nombreProducto,
    this.codigoCabys = '',
    required this.cantidad,
    required this.precioUnitario,
    required this.montoIva,
    required this.subtotal,
    this.yaAcreditado = false,
  });

  double get total => subtotal + montoIva;

  factory DetalleFacturaItem.fromJson(Map<String, dynamic> json) {
    final productoDetalle = json['producto_detalle'] as Map<String, dynamic>?;
    return DetalleFacturaItem(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()),
      productoId: json['producto'] is int ? json['producto'] : int.tryParse(json['producto'].toString()) ?? 0,
      nombreProducto: json['nombre_producto'] ?? 'Producto',
      codigoCabys: json['codigo_cabys'] ?? productoDetalle?['codigo_cabys'] ?? '',
      cantidad: json['cantidad'] is int ? json['cantidad'] : int.tryParse(json['cantidad'].toString()) ?? 0,
      precioUnitario: double.tryParse(json['precio_unitario'].toString()) ?? 0.0,
      montoIva: double.tryParse(json['monto_iva'].toString()) ?? 0.0,
      subtotal: double.tryParse(json['subtotal'].toString()) ?? 0.0,
      yaAcreditado: json['ya_acreditado'] == true,
    );
  }
}

class Factura {
  final int id;
  final int negocio;
  final String tipoDocumento; // "01" Factura Electrónica, "04" Tiquete Electrónico
  final bool esInterno; // Tiquete Interno: no fiscal, no va a Hacienda, sin impuestos
  final String consecutivo;
  final String? clave;
  final String fechaEmision;
  final String receptorNombre;
  final String? receptorCedula;
  final String? receptorCorreo;
  final double totalIva;
  final double totalFactura;
  final bool pagada;
  final bool anulada;
  final String estadoHacienda;
  final String condicionVenta; // "01" Contado, "02" Crédito
  final int plazoCredito;      // Días de crédito
  final List<DetalleFacturaItem> detalles;
  final String nombreNegocio;
  final String? logoNegocioUrl;
  final NegocioInfo? negocioInfo;

  bool get esTiquete => tipoDocumento == '04';

  Factura({
    required this.id,
    required this.negocio,
    this.tipoDocumento = '01',
    this.esInterno = false,
    required this.consecutivo,
    this.clave,
    required this.fechaEmision,
    required this.receptorNombre,
    this.receptorCedula,
    this.receptorCorreo,
    required this.totalIva,
    required this.totalFactura,
    required this.pagada,
    this.anulada = false,
    required this.estadoHacienda,
    this.condicionVenta = "01",
    this.plazoCredito = 0,
    this.detalles = const [],
    this.nombreNegocio = '',
    this.logoNegocioUrl,
    this.negocioInfo,
  });

  factory Factura.fromJson(Map<String, dynamic> json) {
    return Factura(
      id: json['id'],
      negocio: json['negocio'],
      tipoDocumento: json['tipo_documento'] ?? '01',
      esInterno: json['es_interno'] ?? false,
      consecutivo: json['consecutivo'] ?? '',
      clave: json['clave'],
      fechaEmision: json['fecha_emision'] ?? '',
      receptorNombre: (json['receptor_nombre'] as String?)?.trim().isNotEmpty == true
          ? json['receptor_nombre']
          : 'Consumidor Final',
      receptorCedula: json['receptor_cedula'],
      receptorCorreo: json['receptor_correo'],
      totalIva: double.tryParse(json['total_iva'].toString()) ?? 0.0,
      totalFactura: double.tryParse(json['total_factura'].toString()) ?? 0.0,
      pagada: json['pagada'] ?? false,
      anulada: json['anulada'] ?? false,
      estadoHacienda: json['estado_hacienda'] ?? '1',
      condicionVenta: json['condicion_venta'] ?? '01',
      plazoCredito: json['plazo_credito'] ?? 0,
      detalles: (json['detalles'] as List<dynamic>? ?? [])
          .map((d) => DetalleFacturaItem.fromJson(d as Map<String, dynamic>))
          .toList(),
      nombreNegocio: json['nombre_negocio'] ?? '',
      logoNegocioUrl: json['logo_negocio'],
      negocioInfo: json['negocio_info'] != null ? NegocioInfo.fromJson(json['negocio_info']) : null,
    );
  }
}