/// Una linea de factura historica de un cliente (ver
/// ClienteViewSet.historial_precios en el backend): que producto, a que
/// precio y cuando -- se usa tanto para sugerir el precio anterior al
/// facturar de nuevo como para mostrar el historial completo del cliente.
class PrecioHistoricoCliente {
  final int productoId;
  final String productoNombre;
  final double precioUnitario;
  final int cantidad;
  final int facturaId;
  final String facturaConsecutivo;
  final bool facturaAnulada;
  final DateTime fechaEmision;

  PrecioHistoricoCliente({
    required this.productoId,
    required this.productoNombre,
    required this.precioUnitario,
    required this.cantidad,
    required this.facturaId,
    required this.facturaConsecutivo,
    required this.facturaAnulada,
    required this.fechaEmision,
  });

  factory PrecioHistoricoCliente.fromJson(Map<String, dynamic> json) {
    return PrecioHistoricoCliente(
      productoId: json['producto_id'],
      productoNombre: json['producto_nombre'] ?? '',
      precioUnitario: double.tryParse(json['precio_unitario'].toString()) ?? 0,
      cantidad: json['cantidad'] ?? 0,
      facturaId: json['factura_id'],
      facturaConsecutivo: json['factura_consecutivo'] ?? '',
      facturaAnulada: json['factura_anulada'] ?? false,
      fechaEmision: DateTime.tryParse(json['fecha_emision'] ?? '') ?? DateTime.now(),
    );
  }
}
