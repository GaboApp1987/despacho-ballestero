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
  // AUDITORIA.md hallazgo A3 -- ver DetalleFactura.monto_descuento en el
  // backend. subtotal ya viene neto (con esto restado); se guarda aparte
  // solo para poder mostrarlo (PDF, detalle de factura).
  final double montoDescuento;
  final String naturalezaDescuento;
  // AUDITORIA.md hallazgo A3 -- ver DetalleFactura.monto_exoneracion en el
  // backend. monto_iva ya viene neto (con esto restado).
  final double porcentajeExoneracion;
  final double montoExoneracion;
  final String nombreInstitucionExoneracion;

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
    this.montoDescuento = 0,
    this.naturalezaDescuento = '',
    this.porcentajeExoneracion = 0,
    this.montoExoneracion = 0,
    this.nombreInstitucionExoneracion = '',
  });

  double get total => subtotal + montoIva;
  double get montoBruto => precioUnitario * cantidad;

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
      montoDescuento: double.tryParse(json['monto_descuento']?.toString() ?? '') ?? 0.0,
      naturalezaDescuento: json['naturaleza_descuento'] ?? '',
      porcentajeExoneracion: double.tryParse(json['porcentaje_exoneracion']?.toString() ?? '') ?? 0.0,
      montoExoneracion: double.tryParse(json['monto_exoneracion']?.toString() ?? '') ?? 0.0,
      nombreInstitucionExoneracion: json['nombre_institucion_exoneracion'] ?? '',
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
  // Motivo legible del rechazo/error técnico de Hacienda -- solo viene
  // lleno cuando estadoHacienda es '4' (Rechazada) o '5' (Error Técnico),
  // ver Factura.get_motivo_rechazo en el backend.
  final String? motivoRechazo;
  // totalFactura/totalIva y los montos de detalles SIEMPRE están en
  // colones -- si esta factura se emitió en dólares, moneda/tipoCambio
  // permiten mostrar el equivalente (total / tipoCambio) sin duplicar el
  // dato en otra columna.
  final String moneda;
  final double tipoCambio;
  // Solo se llena en el camino directo a Hacienda (sin Alanube, ver
  // FacturaViewSet._enviar_a_hacienda_directo): el XML firmado exacto que
  // se transmitió, la única forma de confirmar qué recibió Hacienda
  // realmente (moneda incluida) ya que ese camino no tiene PDF ni correo
  // automático ni consulta de estado todavía.
  final String? xmlFirmado;
  final bool correoEnviado;

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
    this.motivoRechazo,
    this.moneda = 'CRC',
    this.tipoCambio = 1.0,
    this.xmlFirmado,
    this.correoEnviado = false,
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
      motivoRechazo: json['motivo_rechazo'],
      moneda: json['moneda'] ?? 'CRC',
      tipoCambio: double.tryParse(json['tipo_cambio']?.toString() ?? '') ?? 1.0,
      xmlFirmado: json['xml_firmado'],
      correoEnviado: json['correo_enviado'] == true,
    );
  }
}