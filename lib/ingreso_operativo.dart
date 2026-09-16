/// Ingreso/venta que NO pasa por Factura -- para negocios que llevan su
/// contabilidad con Equilibra pero no facturan electrónicamente acá. Junto
/// con Compra, alimenta la Declaración de IVA/Renta y "Generar asientos
/// automáticos" (ver IngresoOperativo en el backend).
class IngresoOperativo {
  final int id;
  final String fecha; // yyyy-MM-dd
  final String clienteNombre;
  final String clienteCedula;
  final String descripcion;
  final String referencia;
  final double monto; // subtotal, antes de impuesto
  final double montoIva;
  final String condicionVenta; // "01" Contado, "02" Crédito
  final String? comprobanteUrl;

  IngresoOperativo({
    required this.id,
    required this.fecha,
    this.clienteNombre = '',
    this.clienteCedula = '',
    this.descripcion = '',
    this.referencia = '',
    required this.monto,
    this.montoIva = 0,
    this.condicionVenta = '01',
    this.comprobanteUrl,
  });

  double get total => monto + montoIva;

  factory IngresoOperativo.fromJson(Map<String, dynamic> json) {
    return IngresoOperativo(
      id: json['id'],
      fecha: json['fecha'] ?? '',
      clienteNombre: json['cliente_nombre'] ?? '',
      clienteCedula: json['cliente_cedula'] ?? '',
      descripcion: json['descripcion'] ?? '',
      referencia: json['referencia'] ?? '',
      monto: double.tryParse(json['monto'].toString()) ?? 0,
      montoIva: double.tryParse(json['monto_iva']?.toString() ?? '') ?? 0,
      condicionVenta: json['condicion_venta'] ?? '01',
      comprobanteUrl: json['comprobante'],
    );
  }
}
