import 'producto.dart';

class Proveedor {
  final int id;
  final String nombre;
  final String? cedula;
  final String? correo;

  Proveedor({required this.id, required this.nombre, this.cedula, this.correo});

  factory Proveedor.fromJson(Map<String, dynamic> json) {
    return Proveedor(
      id: json['id'],
      nombre: json['nombre'],
      cedula: json['cedula_juridica'],
      correo: json['correo'],
    );
  }
}

class LineaCompra {
  final Producto producto;
  int cantidad;
  double precioCosto;

  LineaCompra({
    required this.producto,
    required this.cantidad,
    required this.precioCosto,
  });

  double get subtotal => cantidad * precioCosto;
}

class DetalleCompraItem {
  final String nombreProducto;
  final int cantidad;
  final double precioCosto;
  // IVA estimado de esta línea y la tarifa usada (según el impuesto
  // asignado al producto) -- null si el producto no tiene impuesto
  // asignado, no se puede estimar. Ver DetalleCompraSerializer.
  final double? montoIva;
  final double? tarifa;

  DetalleCompraItem({
    required this.nombreProducto,
    required this.cantidad,
    required this.precioCosto,
    this.montoIva,
    this.tarifa,
  });

  double get subtotal => cantidad * precioCosto;

  factory DetalleCompraItem.fromJson(Map<String, dynamic> json) {
    return DetalleCompraItem(
      nombreProducto: json['nombre_producto'] ?? '',
      cantidad: json['cantidad'] ?? 0,
      precioCosto: double.tryParse(json['precio_costo'].toString()) ?? 0,
      montoIva: json['monto_iva'] != null ? double.tryParse(json['monto_iva'].toString()) : null,
      tarifa: json['tarifa'] != null ? double.tryParse(json['tarifa'].toString()) : null,
    );
  }
}

class NotaDebitoCompraItem {
  final int id;
  final String numeroDocumento;
  final String fecha;
  final double monto;
  final String motivo;
  final String? comprobanteUrl;

  NotaDebitoCompraItem({
    required this.id,
    required this.numeroDocumento,
    required this.fecha,
    required this.monto,
    required this.motivo,
    this.comprobanteUrl,
  });

  factory NotaDebitoCompraItem.fromJson(Map<String, dynamic> json) {
    return NotaDebitoCompraItem(
      id: json['id'],
      numeroDocumento: json['numero_documento'] ?? '',
      fecha: json['fecha'] ?? '',
      monto: double.tryParse(json['monto'].toString()) ?? 0,
      motivo: json['motivo'] ?? '',
      comprobanteUrl: json['comprobante'],
    );
  }
}

class Compra {
  final int id;
  final int? proveedorId;
  final String? nombreProveedor;
  final String numeroFacturaProveedor;
  final String fechaCompra;
  final double totalCompra;
  final String condicionCompra;
  final bool pagada;
  final String? comprobanteUrl;
  final List<DetalleCompraItem> detalles;
  final List<NotaDebitoCompraItem> notasDebito;
  // Clave del comprobante del proveedor (solo si la compra vino de un XML
  // real) y estado del Mensaje Receptor que este negocio le mandó a
  // Hacienda sobre esa compra -- ver Compra.mensaje_receptor_* en el backend.
  final String? claveHacienda;
  final String? mensajeReceptorTipo;
  final String? mensajeReceptorEstado;
  final String? mensajeReceptorFecha;
  // Si la factura del proveedor vino en dólares, totalCompra ya está
  // convertido a colones con este tipo de cambio -- el monto original en
  // dólares se recupera dividiendo (totalCompra / tipoCambio).
  final String moneda;
  final double tipoCambio;

  Compra({
    required this.id,
    this.proveedorId,
    this.nombreProveedor,
    required this.numeroFacturaProveedor,
    required this.fechaCompra,
    required this.totalCompra,
    this.condicionCompra = '01',
    this.pagada = false,
    this.comprobanteUrl,
    required this.detalles,
    this.notasDebito = const [],
    this.claveHacienda,
    this.mensajeReceptorTipo,
    this.mensajeReceptorEstado,
    this.mensajeReceptorFecha,
    this.moneda = 'CRC',
    this.tipoCambio = 1.0,
  });

  factory Compra.fromJson(Map<String, dynamic> json) {
    return Compra(
      id: json['id'],
      proveedorId: json['proveedor'] is int ? json['proveedor'] : int.tryParse(json['proveedor']?.toString() ?? ''),
      nombreProveedor: json['nombre_proveedor'],
      numeroFacturaProveedor: json['numero_factura_proveedor'] ?? '',
      fechaCompra: json['fecha_compra'] ?? '',
      totalCompra: double.tryParse(json['total_compra'].toString()) ?? 0,
      condicionCompra: json['condicion_compra'] ?? '01',
      pagada: json['pagada'] == true,
      comprobanteUrl: json['comprobante'],
      detalles: ((json['detalles_compra'] ?? []) as List)
          .map((d) => DetalleCompraItem.fromJson(d))
          .toList(),
      notasDebito: ((json['notas_debito'] ?? []) as List)
          .map((n) => NotaDebitoCompraItem.fromJson(n))
          .toList(),
      claveHacienda: (json['clave_hacienda'] as String?)?.isNotEmpty == true ? json['clave_hacienda'] : null,
      mensajeReceptorTipo: (json['mensaje_receptor_tipo'] as String?)?.isNotEmpty == true ? json['mensaje_receptor_tipo'] : null,
      mensajeReceptorEstado: (json['mensaje_receptor_estado'] as String?)?.isNotEmpty == true ? json['mensaje_receptor_estado'] : null,
      mensajeReceptorFecha: json['mensaje_receptor_fecha'],
      moneda: json['moneda'] ?? 'CRC',
      tipoCambio: double.tryParse(json['tipo_cambio']?.toString() ?? '') ?? 1.0,
    );
  }
}