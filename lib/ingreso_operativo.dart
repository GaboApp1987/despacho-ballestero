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
  final double monto; // subtotal, antes de impuesto -- SIEMPRE en colones
  final double montoIva; // SIEMPRE en colones
  final String condicionVenta; // "01" Contado, "02" Crédito
  final String? comprobanteUrl;
  // Si la venta se cobró en dólares, monto/montoIva ya vienen convertidos a
  // colones con este tipo de cambio -- el monto original en dólares se
  // recupera dividiendo (monto / tipoCambio) en vez de duplicar el dato.
  final String moneda;
  final double tipoCambio;

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
    this.moneda = 'CRC',
    this.tipoCambio = 1.0,
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
      moneda: json['moneda'] ?? 'CRC',
      tipoCambio: double.tryParse(json['tipo_cambio']?.toString() ?? '') ?? 1.0,
    );
  }
}
