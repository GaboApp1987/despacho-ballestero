import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';
import 'factura.dart';
import 'export_service.dart';
import 'formato.dart';
import 'api_service.dart';
import 'nota_credito.dart';
import 'negocio.dart';
import 'formulario_factura.dart';
import 'widgets/automatizacion_factura.dart';

class DetalleFacturaScreen extends StatefulWidget {
  final Factura factura;

  const DetalleFacturaScreen({super.key, required this.factura});

  @override
  State<DetalleFacturaScreen> createState() => _DetalleFacturaScreenState();
}

class _DetalleFacturaScreenState extends State<DetalleFacturaScreen> {
  // Los montos del detalle/totales vienen siempre en colones (ver
  // Factura.moneda); una factura en dólares se muestra en dólares, igual
  // que el PDF (exportFacturaDetalleToPdf), con el equivalente en colones
  // solo como referencia.
  bool get _esUsd => widget.factura.moneda == 'USD' && widget.factura.tipoCambio > 0;
  String _fmt(num colones) => _esUsd ? formatearDolares(colones / widget.factura.tipoCambio) : formatearColones(colones);
  bool _isProcesando = false;
  bool _facturaAnulada = false;
  // Se emitió una factura nueva repitiendo esta: la lista tiene que recargar.
  bool _seRepitio = false;

  Future<void> _repetirFactura() async {
    final factura = widget.factura;
    setState(() => _isProcesando = true);
    try {
      final r = await ApiService.get('/negocios/${factura.negocio}/');
      if (r.statusCode != 200) throw Exception('No se pudo cargar el negocio.');
      final negocio = Negocio.fromJson(json.decode(utf8.decode(r.bodyBytes)));
      if (!mounted) return;
      setState(() => _isProcesando = false);
      final creada = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => FormularioFactura(negocio: negocio, plantilla: factura)),
      );
      if (creada == true && mounted) {
        _seRepitio = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Listo, se emitió la factura nueva."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcesando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo repetir: $e"), backgroundColor: Colors.red));
      }
    }
  }
  // Lineas ya acreditadas por una Nota de Credito, ya sea de antes (ver
  // DetalleFacturaItem.yaAcreditado) o generadas en esta misma pantalla sin
  // haber vuelto a cargar la factura desde el backend todavia.
  late final Set<int> _idsDetalleAcreditados = factura.detalles.where((d) => d.yaAcreditado && d.id != null).map((d) => d.id!).toSet();

  List<NotaCredito> _notasCredito = [];

  double get _subtotalAcreditado => _notasCredito.fold(0.0, (s, n) => s + n.subtotal);
  double get _ivaAcreditado => _notasCredito.fold(0.0, (s, n) => s + n.montoIva);
  double get _totalAcreditado => _subtotalAcreditado + _ivaAcreditado;

  Factura get factura => widget.factura;

  @override
  void initState() {
    super.initState();
    _cargarNotasCredito();
  }

  /// Notas de credito YA ACEPTADAS por Hacienda contra esta factura (total o
  /// parcial), para mostrar el desglose "factura original -> notas de
  /// credito -> neto" en el resumen de cuenta, en vez de solo el monto
  /// original sin reflejar lo ya acreditado.
  Future<void> _cargarNotasCredito() async {
    try {
      final response = await ApiService.get('/notas-credito/?negocio=${factura.negocio}&factura=${factura.id}');
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as List;
        setState(() {
          _notasCredito = data.map((j) => NotaCredito.fromJson(j)).where((n) => n.estadoHacienda == '3').toList();
        });
      }
    } catch (_) {
      // Si falla, simplemente no se muestra el desglose de notas de credito.
    }
  }

  Future<void> _manejarAccion(Future<void> Function() accion) async {
    if (_isProcesando) return;
    setState(() => _isProcesando = true);
    try {
      await accion();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcesando = false);
    }
  }

  Future<void> _consultarEstadoHacienda() async {
    final response = await ApiService.post('/facturas/${factura.id}/consultar-hacienda/', {});
    if (!mounted) return;
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Error al consultar el estado');
    }
    final estado = data['ind_estado_hacienda'] ?? '';
    final correoInfo = data['correo_info'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(correoInfo != null ? "Estado: $estado. $correoInfo" : "Estado: $estado")),
    );
    Navigator.pop(context, true);
  }

  /// Reintenta enviar a Hacienda una factura que quedó "Sin Enviar" o en
  /// "Error Técnico" (backend: FacturaViewSet.reenviar_hacienda_view) -- útil
  /// después de corregir la causa del error (ej. una unidad de medida
  /// inválida en el producto, o el plazo de crédito) sin tener que rehacer
  /// la factura completa.
  Future<void> _reenviarHacienda() async {
    final response = await ApiService.post('/facturas/${factura.id}/reenviar-hacienda/', {});
    if (!mounted) return;
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Error al reenviar la factura');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Factura reenviada a Hacienda."), backgroundColor: Colors.green),
    );
    Navigator.pop(context, true);
  }

  Future<void> _eliminarFactura() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar factura"),
        content: Text(
          "¿Seguro que querés eliminar la factura F-${factura.consecutivo}? "
          "El inventario que se descontó volverá al stock. Esta acción no se puede deshacer.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await _manejarAccion(() async {
      final response = await ApiService.delete('/facturas/${factura.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Factura eliminada"), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      } else {
        String mensaje = "No se pudo eliminar la factura.";
        try {
          final data = json.decode(utf8.decode(response.bodyBytes));
          if (data is Map && data['detail'] != null) mensaje = data['detail'];
        } catch (_) {}
        throw Exception(mensaje);
      }
    });
  }

  Future<void> _anularConNotaCredito() async {
    final disponibles = factura.detalles.where((d) => d.id != null && !_idsDetalleAcreditados.contains(d.id)).toList();
    if (disponibles.isEmpty) return;

    final motivoCtrl = TextEditingController(text: "Anulación de factura");
    // Por defecto se seleccionan todos (mismo comportamiento de siempre:
    // "anular la factura completa" en un click); el usuario puede
    // deseleccionar para dejar una Nota de Credito PARCIAL, de uno o varios
    // productos nada mas.
    final seleccionados = {for (final d in disponibles) d.id!: true};

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final elegidos = disponibles.where((d) => seleccionados[d.id] == true).toList();
          final subtotal = elegidos.fold(0.0, (s, d) => s + d.subtotal);
          final iva = elegidos.fold(0.0, (s, d) => s + d.montoIva);
          final total = subtotal + iva;
          final esParcial = elegidos.length < disponibles.length;

          return AlertDialog(
            title: const Text("Anular con Nota de Crédito"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Elija qué productos acreditar. Se devuelven al inventario y, si quedan "
                    "todos seleccionados, la factura queda marcada como ANULADA.",
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...disponibles.map((d) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: seleccionados[d.id] ?? false,
                        title: Text(d.nombreProducto, style: const TextStyle(fontSize: 14)),
                        subtitle: Text("${d.cantidad} x ${_fmt(d.precioUnitario)} = ${_fmt(d.total)}"),
                        onChanged: (v) => setDialogState(() => seleccionados[d.id!] = v ?? false),
                      )),
                  const SizedBox(height: 8),
                  Text(
                    "Subtotal ${_fmt(subtotal)}  ·  IVA ${_fmt(iva)}  ·  Total ${_fmt(total)}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: motivoCtrl,
                    decoration: InputDecoration(labelText: esParcial ? "Motivo (nota parcial)" : "Motivo", border: const OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: elegidos.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(esParcial ? "Generar Nota Parcial" : "Anular Factura", style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmar != true) return;

    final idsElegidos = seleccionados.entries.where((e) => e.value).map((e) => e.key).toList();

    await _manejarAccion(() async {
      final response = await ApiService.post('/notas-credito/', {
        'negocio': factura.negocio,
        'factura': factura.id,
        'motivo': motivoCtrl.text.trim().isEmpty ? "Anulación de factura" : motivoCtrl.text.trim(),
        if (idsElegidos.length < disponibles.length) 'detalle_factura_ids': idsElegidos,
      });
      if (response.statusCode == 201) {
        if (mounted) {
          setState(() {
            _idsDetalleAcreditados.addAll(idsElegidos);
            if (_idsDetalleAcreditados.length >= factura.detalles.length) _facturaAnulada = true;
          });
          _cargarNotasCredito();
          final data = json.decode(utf8.decode(response.bodyBytes));
          final nota = NotaCredito.fromJson(data);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Nota de Crédito ${nota.consecutivo} generada"),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: "VER PDF",
                textColor: Colors.white,
                onPressed: () => ExportService.exportNotaCreditoToPdf(nota),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } else {
        String mensaje = "No se pudo generar la Nota de Crédito.";
        try {
          final data = json.decode(utf8.decode(response.bodyBytes));
          if (data is Map) {
            if (data['detail'] != null) {
              mensaje = data['detail'] is List ? data['detail'].join(' ') : data['detail'].toString();
            } else if (data.values.isNotEmpty) {
              mensaje = data.values.first.toString();
            }
          }
        } catch (_) {}
        throw Exception(mensaje);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool estaAnulada = _facturaAnulada || factura.anulada;
    final bool puedeEliminar = !estaAnulada && factura.estadoHacienda != '3';
    final bool puedeAnular = !estaAnulada && factura.estadoHacienda == '3';

    Color colorEstado;
    String textoEstado;
    if (estaAnulada) {
      colorEstado = Colors.blueGrey;
      textoEstado = "ANULADA (NOTA DE CRÉDITO)";
    } else {
      switch (factura.estadoHacienda) {
        case '3':
          colorEstado = Colors.green;
          textoEstado = "ACEPTADA POR HACIENDA";
          break;
        case '4':
          colorEstado = Colors.red;
          textoEstado = "RECHAZADA POR HACIENDA";
          break;
        case '5':
          colorEstado = Colors.red;
          textoEstado = "ERROR TÉCNICO AL ENVIAR";
          break;
        case '1':
        case '2':
          colorEstado = Colors.orange;
          textoEstado = "PROCESANDO / PENDIENTE";
          break;
        case '6':
          colorEstado = Colors.amber;
          textoEstado = "TIQUETE INTERNO (NO SE ENVÍA A HACIENDA)";
          break;
        default:
          colorEstado = Colors.grey;
          textoEstado = "DESCONOCIDO";
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.pop(context, _facturaAnulada || _seRepitio),
        ),
        title: Text("Documento F-${factura.consecutivo}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      backgroundColor: AppColors.background,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600), // 👈 Manejo correcto de ancho en Windows
          margin: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: colorEstado,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                  ),
                  child: Text(
                    textoEstado,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (factura.motivoRechazo != null && factura.motivoRechazo!.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        factura.estadoHacienda == '5' ? "Motivo del error" : "Motivo del rechazo",
                                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 18, color: Colors.red),
                                      tooltip: "Copiar",
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: factura.motivoRechazo!));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Motivo copiado al portapapeles")),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                SelectableText(factura.motivoRechazo!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.business, size: 40, color: AppColors.primary),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text("FACTURA NÚMERO:", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                Text(factura.consecutivo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(),
                        Text("RECEPTOR", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(height: 5),
                        Text(factura.receptorNombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (factura.receptorCedula != null && factura.receptorCedula!.isNotEmpty)
                          Text("Cédula: ${factura.receptorCedula}", style: TextStyle(color: Colors.grey[700])),
                        if (factura.receptorCorreo != null && factura.receptorCorreo!.isNotEmpty)
                          Text("Correo: ${factura.receptorCorreo}", style: TextStyle(color: Colors.grey[700])),
                        const SizedBox(height: 25),
                        const Divider(),
                        Text("DETALLES DE TIMBRADO", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(height: 5),
                        if (factura.esInterno)
                          Text(
                            "Tiquete interno: no fiscal, no tiene clave numérica de Hacienda.",
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          )
                        else ...[
                          Text("Clave Numérica (50 dígitos):", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          SelectableText(
                            factura.clave ?? "No generada",
                            style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textStrong),
                          ),
                        ],
                        const SizedBox(height: 25),
                        const Divider(),
                        Text("PRODUCTOS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(height: 10),
                        if (factura.detalles.isEmpty)
                          Text("Sin detalle de líneas registrado.", style: TextStyle(color: Colors.grey[600], fontSize: 13))
                        else
                          ...factura.detalles.map((linea) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(linea.nombreProducto, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                          if (linea.codigoCabys.isNotEmpty)
                                            Text(
                                              "CABYS: ${linea.codigoCabys}",
                                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                            ),
                                          Text(
                                            "${linea.cantidad} x ${_fmt(linea.precioUnitario)} = ${_fmt(linea.montoBruto)}"
                                            "${linea.montoIva > 0 ? '  ·  IVA ${_fmt(linea.montoIva)}' : ''}",
                                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                          ),
                                          if (linea.montoDescuento > 0)
                                            Text(
                                              "Descuento: -${_fmt(linea.montoDescuento)}"
                                              "${linea.naturalezaDescuento.isNotEmpty ? ' (${linea.naturalezaDescuento})' : ''}",
                                              style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                                            ),
                                          if (linea.porcentajeExoneracion > 0)
                                            Text(
                                              "Exonerado ${linea.porcentajeExoneracion.toStringAsFixed(0)}% del IVA: -${_fmt(linea.montoExoneracion)}"
                                              "${linea.nombreInstitucionExoneracion.isNotEmpty ? ' (${linea.nombreInstitucionExoneracion})' : ''}",
                                              style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _fmt(linea.total),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ),
                              )),
                        const SizedBox(height: 15),
                        const Divider(),
                        Text("RESUMEN DE CUENTA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(height: 15),
                        _filaFinanciera("Subtotal:", _fmt(factura.totalFactura - factura.totalIva), false),
                        const SizedBox(height: 8),
                        _filaFinanciera("Impuesto (IVA):", _fmt(factura.totalIva), false),
                        const SizedBox(height: 12),
                        const Divider(thickness: 1.5),
                        const SizedBox(height: 8),
                        _filaFinanciera(_notasCredito.isEmpty ? "TOTAL NETO:" : "Total Factura Original:", _fmt(factura.totalFactura), _notasCredito.isEmpty),
                        if (_esUsd) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              "≈ ${formatearColones(factura.totalFactura)} (tipo de cambio ${formatearNumero(factura.tipoCambio)})",
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                        ],
                        if (_notasCredito.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          Text("NOTAS DE CRÉDITO APLICADAS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          const SizedBox(height: 12),
                          ...(_notasCredito.map((n) => _tarjetaNotaCredito(n))),
                          const SizedBox(height: 8),
                          const Divider(thickness: 1.5),
                          const SizedBox(height: 8),
                          Text("FACTURA NETA DESPUÉS DE NC", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          const SizedBox(height: 12),
                          _filaFinanciera("Subtotal neto:", _fmt((factura.totalFactura - factura.totalIva) - _subtotalAcreditado), false),
                          const SizedBox(height: 8),
                          _filaFinanciera("IVA neto:", _fmt(factura.totalIva - _ivaAcreditado), false),
                          const SizedBox(height: 12),
                          const Divider(thickness: 1.5),
                          const SizedBox(height: 8),
                          _filaFinanciera("TOTAL NETO:", _fmt(factura.totalFactura - _totalAcreditado), true),
                          if (_esUsd) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                "≈ ${formatearColones(factura.totalFactura - _totalAcreditado)}",
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ),
                          ],
                        ],
                        // Repetir sola y cobro automático (ver AutomatizacionFactura).
                        if (!factura.esInterno) AutomatizacionFactura(factura: factura),
                      ],
                    ),
                  ),
                ),
                // Acciones, en orden: (1) el documento -- PDF, compartir,
                // repetir, XML --, (2) lo pendiente con Hacienda, solo si
                // aplica, y (3) al final y aparte, lo que no tiene vuelta
                // atrás (anular / eliminar).
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _accionDocumento(
                            icono: Icons.picture_as_pdf,
                            texto: "PDF",
                            principal: true,
                            ocupado: _isProcesando,
                            onTap: () => _manejarAccion(
                                () => ExportService.exportFacturaDetalleToPdf(factura, share: false, notasCredito: _notasCredito)),
                          ),
                          const SizedBox(width: 8),
                          _accionDocumento(
                            icono: Icons.share,
                            texto: "Compartir",
                            onTap: _isProcesando
                                ? null
                                : () => _manejarAccion(
                                    () => ExportService.exportFacturaDetalleToPdf(factura, share: true, notasCredito: _notasCredito)),
                          ),
                          // Misma venta otra vez (ej. un alquiler mensual): una
                          // factura nueva con los mismos datos y la fecha de hoy.
                          if (!factura.esInterno) ...[
                            const SizedBox(width: 8),
                            _accionDocumento(
                              icono: Icons.replay_rounded,
                              texto: "Repetir",
                              onTap: _isProcesando ? null : _repetirFactura,
                            ),
                          ],
                          // Único documento que refleja EXACTAMENTE lo que
                          // Hacienda recibió (moneda incluida) en el camino
                          // directo -- ver FacturaViewSet._enviar_a_hacienda_directo.
                          if (factura.xmlFirmado != null && factura.xmlFirmado!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _accionDocumento(
                              icono: Icons.code,
                              texto: "Ver XML",
                              onTap: () async {
                                final uri = Uri.parse(factura.xmlFirmado!);
                                if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("No se pudo abrir el XML.")),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                      // "Consultar estado" mientras sigue Enviando(2). Una vez
                      // Aceptada(3), si el correo al cliente no salió
                      // (correo_enviado en False), "Reenviar correo": el mismo
                      // endpoint consultar-hacienda reintenta el correo cuando
                      // ve estado '3' y correo_enviado=False (ver
                      // _consultar_y_notificar_hacienda_directo en el backend).
                      if (factura.estadoHacienda == '2' || (factura.estadoHacienda == '3' && !factura.correoEnviado)) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: Icon(factura.estadoHacienda == '3' ? Icons.mail_outline : Icons.refresh, color: Colors.orange),
                          label: Text(
                            factura.estadoHacienda == '3' ? "REENVIAR CORREO" : "CONSULTAR ESTADO EN HACIENDA",
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _isProcesando ? null : () => _manejarAccion(_consultarEstadoHacienda),
                        ),
                      ],
                      // Reintentar en cualquier estado que no sea Enviando(2)/
                      // Aceptada(3) (ver FacturaViewSet.reenviar_hacienda_view),
                      // incluido Rechazada(4).
                      if (factura.estadoHacienda == '5' || factura.estadoHacienda == '1' || factura.estadoHacienda == '4') ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.send_outlined, color: Colors.red),
                          label: const Text("REINTENTAR ENVÍO A HACIENDA", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          onPressed: _isProcesando ? null : () => _manejarAccion(_reenviarHacienda),
                        ),
                      ],
                      if (puedeEliminar || puedeAnular) ...[
                        const SizedBox(height: 16),
                        Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 12),
                        puedeEliminar
                            ? TextButton.icon(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                label: const Text("Eliminar factura", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                onPressed: _isProcesando ? null : _eliminarFactura,
                              )
                            : TextButton.icon(
                                icon: const Icon(Icons.receipt_long_outlined, color: Colors.orange),
                                label: const Text("Anular con nota de crédito", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                                onPressed: _isProcesando ? null : _anularConNotaCredito,
                              ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Botón de la fila de acciones del documento: ícono arriba y el nombre
  /// abajo, todos del mismo ancho (entran bien también en el celular).
  Widget _accionDocumento({
    required IconData icono,
    required String texto,
    required VoidCallback? onTap,
    bool principal = false,
    bool ocupado = false,
  }) {
    final color = principal ? Colors.black : AppColors.primary;
    final contenido = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ocupado
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(icono, color: color, size: 22),
        const SizedBox(height: 4),
        Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ],
    );
    final estilo = principal
        ? ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          )
        : OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.primary.withOpacity(0.6)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          );
    return Expanded(
      child: principal
          ? ElevatedButton(style: estilo, onPressed: ocupado ? null : onTap, child: contenido)
          : OutlinedButton(style: estilo, onPressed: onTap, child: contenido),
    );
  }

  Widget _filaFinanciera(String titulo, String monto, bool esTotal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: TextStyle(fontSize: esTotal ? 16 : 14, fontWeight: esTotal ? FontWeight.bold : FontWeight.normal)),
        Text(monto, style: TextStyle(fontSize: esTotal ? 20 : 14, fontWeight: FontWeight.bold, color: esTotal ? AppColors.primary : Colors.black)),
      ],
    );
  }

  /// Tarjeta de una nota de credito aplicada a esta factura, con el mismo
  /// estilo de "mini documento" que la factura misma (barra de encabezado,
  /// lista de productos, totales) en vez de solo texto plano -- para que se
  /// lea como un comprobante propio, no como una nota al pie.
  Widget _tarjetaNotaCredito(NotaCredito n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.orange.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("NOTA DE CRÉDITO NC-${n.consecutivo}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade900)),
                Text(n.fechaEmision.split('T')[0], style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n.motivo.isNotEmpty) ...[
                  Text(n.motivo, style: TextStyle(fontSize: 12, color: Colors.grey[700], fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),
                ],
                ...n.detalles.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.nombreProducto, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(
                                  "${d.cantidad} x ${_fmt(d.precioUnitario)}"
                                  "${d.montoIva > 0 ? '  ·  IVA ${_fmt(d.montoIva)}' : ''}",
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          Text(_fmt(d.total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    )),
                const Divider(),
                _filaFinancieraNegativa("Subtotal:", n.subtotal),
                _filaFinancieraNegativa("IVA:", n.montoIva),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Total NC:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange.shade900)),
                    Text("-${_fmt(n.total)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaFinancieraNegativa(String titulo, double monto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text("-${_fmt(monto)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red)),
        ],
      ),
    );
  }
}