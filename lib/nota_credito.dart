import 'negocio.dart';

class DetalleNotaCreditoItem {
  final int productoId;
  final String nombreProducto;
  final int cantidad;
  final double precioUnitario;
  final double montoIva;
  final double subtotal;

  DetalleNotaCreditoItem({
    required this.productoId,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
    required this.montoIva,
    required this.subtotal,
  });

  double get total => subtotal + montoIva;

  factory DetalleNotaCreditoItem.fromJson(Map<String, dynamic> json) {
    return DetalleNotaCreditoItem(
      productoId: json['producto'] is int ? json['producto'] : int.tryParse(json['producto'].toString()) ?? 0,
      nombreProducto: json['nombre_producto'] ?? 'Producto',
      cantidad: json['cantidad'] is int ? json['cantidad'] : int.tryParse(json['cantidad'].toString()) ?? 0,
      precioUnitario: double.tryParse(json['precio_unitario'].toString()) ?? 0.0,
      montoIva: double.tryParse(json['monto_iva'].toString()) ?? 0.0,
      subtotal: double.tryParse(json['subtotal'].toString()) ?? 0.0,
    );
  }
}

class NotaCredito {
  final int id;
  final int negocio;
  final int factura;
  final String? facturaConsecutivo;
  final String consecutivo;
  final String? clave;
  final String fechaEmision;
  final String motivo;
  final String receptorNombre;
  final String? receptorCedula;
  final double subtotal;
  final double montoIva;
  final double total;
  final String estadoHacienda;
  final String nombreNegocio;
  final String? logoNegocioUrl;
  final NegocioInfo? negocioInfo;
  final List<DetalleNotaCreditoItem> detalles;
  // Moneda/tipo de cambio de la factura que esta nota anula -- la nota no
  // tiene moneda propia, siempre es la misma que la factura original (ver
  // NotaCreditoSerializer.factura_moneda en el backend).
  final String facturaMoneda;
  final double facturaTipoCambio;
  final bool correoEnviado;

  NotaCredito({
    required this.id,
    required this.negocio,
    required this.factura,
    this.facturaConsecutivo,
    required this.consecutivo,
    this.clave,
    required this.fechaEmision,
    required this.motivo,
    required this.receptorNombre,
    this.receptorCedula,
    required this.subtotal,
    required this.montoIva,
    required this.total,
    required this.estadoHacienda,
    this.nombreNegocio = '',
    this.logoNegocioUrl,
    this.negocioInfo,
    this.detalles = const [],
    this.facturaMoneda = 'CRC',
    this.facturaTipoCambio = 1.0,
    this.correoEnviado = false,
  });

  factory NotaCredito.fromJson(Map<String, dynamic> json) {
    return NotaCredito(
      id: json['id'],
      negocio: json['negocio'],
      factura: json['factura'],
      facturaConsecutivo: json['factura_consecutivo'],
      consecutivo: json['consecutivo'] ?? '',
      clave: json['clave'],
      fechaEmision: json['fecha_emision'] ?? '',
      motivo: json['motivo'] ?? '',
      receptorNombre: json['receptor_nombre'] ?? '',
      receptorCedula: json['receptor_cedula'],
      subtotal: double.tryParse(json['subtotal'].toString()) ?? 0.0,
      montoIva: double.tryParse(json['monto_iva'].toString()) ?? 0.0,
      total: double.tryParse(json['total'].toString()) ?? 0.0,
      estadoHacienda: json['estado_hacienda'] ?? '1',
      nombreNegocio: json['nombre_negocio'] ?? '',
      logoNegocioUrl: json['logo_negocio'],
      negocioInfo: json['negocio_info'] != null ? NegocioInfo.fromJson(json['negocio_info']) : null,
      detalles: (json['detalles'] as List<dynamic>? ?? [])
          .map((d) => DetalleNotaCreditoItem.fromJson(d as Map<String, dynamic>))
          .toList(),
      facturaMoneda: json['factura_moneda'] ?? 'CRC',
      facturaTipoCambio: double.tryParse(json['factura_tipo_cambio']?.toString() ?? '') ?? 1.0,
      correoEnviado: json['correo_enviado'] == true,
    );
  }
}
