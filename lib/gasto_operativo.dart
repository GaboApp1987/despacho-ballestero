/// Categorías curadas de gasto operativo (no exhaustivo). Alimentan el
/// cálculo de Renta junto con Compras: Compra solo cubre mercadería para
/// reventa, estas categorías cubren el resto del gasto deducible típico
/// de un negocio pequeño en Costa Rica.
const Map<String, String> categoriasGasto = {
  'planilla': 'Planilla y CCSS',
  'alquiler': 'Alquiler',
  'servicios': 'Servicios públicos (agua, luz, internet)',
  'honorarios': 'Honorarios profesionales',
  'mantenimiento': 'Mantenimiento y reparaciones',
  'publicidad': 'Publicidad y mercadeo',
  'transporte': 'Transporte y viáticos',
  'seguros': 'Seguros',
  'depreciacion': 'Depreciación de activos',
  'financieros': 'Gastos financieros e intereses',
  'impuestos_municipales': 'Impuestos y patentes municipales',
  'otros': 'Otros gastos',
};

class GastoOperativo {
  final int id;
  final String fecha; // yyyy-MM-dd
  final String categoria;
  final String descripcion;
  final double monto;
  final bool deducible;
  final int? proveedorId;
  final String? nombreProveedor;
  final String? comprobanteUrl;

  GastoOperativo({
    required this.id,
    required this.fecha,
    required this.categoria,
    required this.descripcion,
    required this.monto,
    required this.deducible,
    this.proveedorId,
    this.nombreProveedor,
    this.comprobanteUrl,
  });

  String get categoriaLabel => categoriasGasto[categoria] ?? categoria;

  factory GastoOperativo.fromJson(Map<String, dynamic> json) {
    return GastoOperativo(
      id: json['id'],
      fecha: json['fecha'] ?? '',
      categoria: json['categoria'] ?? 'otros',
      descripcion: json['descripcion'] ?? '',
      monto: double.tryParse(json['monto'].toString()) ?? 0,
      deducible: json['deducible'] ?? true,
      proveedorId: json['proveedor'],
      nombreProveedor: json['nombre_proveedor'],
      comprobanteUrl: json['comprobante'],
    );
  }
}
