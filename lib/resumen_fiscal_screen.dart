import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'declaracion_fiscal_widgets.dart';
import 'detalle_negocio.dart';
import 'export_service.dart';
import 'factura.dart';
import 'gasto_operativo.dart';
import 'negocio.dart';
import 'nota_credito.dart';
import 'widgets/selector_periodo.dart';

/// Lo primero que ve el contador al entrar a un cliente: el resumen fiscal
/// completo (IVA del periodo + Renta del año) antes de meterse a administrar
/// el negocio por dentro (facturas, inventario, etc.).
class ResumenFiscalNegocioScreen extends StatefulWidget {
  final Negocio negocio;
  const ResumenFiscalNegocioScreen({super.key, required this.negocio});

  @override
  State<ResumenFiscalNegocioScreen> createState() => _ResumenFiscalNegocioScreenState();
}

class _ResumenFiscalNegocioScreenState extends State<ResumenFiscalNegocioScreen> {
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  late int _anioRenta;
  late Future<Map<String, dynamic>> _declaracionIvaFuture;
  late Future<Map<String, dynamic>> _declaracionRentaFuture;
  bool _exportandoIva = false;
  bool _exportandoRenta = false;
  // Controla la animacion del "interruptor" de Gestionar Cliente
  // Internamente -- se prende (thumb se desliza a la derecha, cambia de
  // color) apenas se toca, y recien despues de que se ve esa animacion
  // navega a DetalleNegocio con una transicion propia (ver
  // _gestionarClienteInternamente).
  bool _entrandoAGestionInterna = false;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month + 1, 0);
    _anioRenta = ahora.year;
    _declaracionIvaFuture = _obtenerDeclaracionIva();
    _declaracionRentaFuture = _obtenerDeclaracionRenta();
  }

  Future<Map<String, dynamic>> _obtenerDeclaracionIva() async {
    String inicioStr = "${_fechaInicio.year}-${_fechaInicio.month.toString().padLeft(2, '0')}-${_fechaInicio.day.toString().padLeft(2, '0')}";
    String finStr = "${_fechaFin.year}-${_fechaFin.month.toString().padLeft(2, '0')}-${_fechaFin.day.toString().padLeft(2, '0')}";
    final response = await ApiService.get(
      '/facturas/declaracion-iva/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr',
    );
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return {};
  }

  Future<Map<String, dynamic>> _obtenerDeclaracionRenta() async {
    final response = await ApiService.get(
      '/facturas/declaracion-renta/?negocio=${widget.negocio.id}&periodo_fiscal=$_anioRenta',
    );
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return {};
  }

  Future<void> _cambiarPeriodoIva() async {
    final rango = await elegirPeriodo(context, inicial: DateTimeRange(start: _fechaInicio, end: _fechaFin));
    if (rango == null) return;
    setState(() {
      _fechaInicio = rango.start;
      _fechaFin = rango.end;
      _declaracionIvaFuture = _obtenerDeclaracionIva();
    });
  }

  static const List<String> _nombresMes = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  /// True si el rango actual es exactamente un mes calendario completo --
  /// para mostrar el nombre del mes en vez del rango de fechas, igual que
  /// en Reportes/Ingresos.
  bool get _esMesCompletoIva {
    final primerDia = DateTime(_fechaInicio.year, _fechaInicio.month, 1);
    final ultimoDia = DateTime(_fechaInicio.year, _fechaInicio.month + 1, 0);
    return _fechaInicio.isAtSameMomentAs(primerDia) && _fechaFin.isAtSameMomentAs(ultimoDia);
  }

  String get _mesAnioIvaTexto => '${_nombresMes[_fechaInicio.month - 1]} ${_fechaInicio.year}';

  /// Salta directo a un mes calendario completo -- antes la única forma de
  /// cambiar de periodo era el selector de rango manual (elegir día de
  /// inicio y de fin uno por uno), lento para el caso normal de "ver el
  /// mes pasado".
  void _irAMesIva(int deltaMeses) {
    final base = DateTime(_fechaInicio.year, _fechaInicio.month + deltaMeses, 1);
    setState(() {
      _fechaInicio = DateTime(base.year, base.month, 1);
      _fechaFin = DateTime(base.year, base.month + 1, 0);
      _declaracionIvaFuture = _obtenerDeclaracionIva();
    });
  }

  void _cambiarAnioRenta(int nuevoAnio) {
    setState(() {
      _anioRenta = nuevoAnio;
      _declaracionRentaFuture = _obtenerDeclaracionRenta();
    });
  }

  String _fmtFecha(DateTime f) => "${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}";

  Future<List<Factura>> _obtenerFacturasPeriodo(DateTime inicio, DateTime fin) async {
    final response = await ApiService.get(
      '/facturas/?negocio=${widget.negocio.id}&fecha_inicio=${_fmtFecha(inicio)}&fecha_fin=${_fmtFecha(fin)}',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => Factura.fromJson(j)).toList();
  }

  Future<List<NotaCredito>> _obtenerNotasCreditoPeriodo(DateTime inicio, DateTime fin) async {
    final response = await ApiService.get(
      '/notas-credito/?negocio=${widget.negocio.id}&fecha_inicio=${_fmtFecha(inicio)}&fecha_fin=${_fmtFecha(fin)}',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => NotaCredito.fromJson(j)).toList();
  }

  Future<List<Compra>> _obtenerComprasPeriodo(DateTime inicio, DateTime fin) async {
    final response = await ApiService.get(
      '/compras/?negocio=${widget.negocio.id}&fecha_inicio=${_fmtFecha(inicio)}&fecha_fin=${_fmtFecha(fin)}',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => Compra.fromJson(j)).toList();
  }

  Future<List<GastoOperativo>> _obtenerGastosAnio(int anio) async {
    final response = await ApiService.get(
      '/gastos-operativos/?negocio=${widget.negocio.id}&fecha_inicio=$anio-01-01&fecha_fin=$anio-12-31',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => GastoOperativo.fromJson(j)).toList();
  }

  String get _periodoIvaTexto =>
      "Del ${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} al ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}";

  Future<void> _exportarIva({required bool excel}) async {
    if (_exportandoIva) return;
    setState(() => _exportandoIva = true);
    try {
      final resultados = await Future.wait([
        _declaracionIvaFuture,
        _obtenerFacturasPeriodo(_fechaInicio, _fechaFin),
        _obtenerNotasCreditoPeriodo(_fechaInicio, _fechaFin),
        _obtenerComprasPeriodo(_fechaInicio, _fechaFin),
      ]);
      final declaracion = resultados[0] as Map<String, dynamic>;
      final facturas = resultados[1] as List<Factura>;
      final notas = resultados[2] as List<NotaCredito>;
      final compras = resultados[3] as List<Compra>;

      if (declaracion.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo cargar la declaración de IVA para exportar")),
          );
        }
        return;
      }

      if (excel) {
        await ExportService.exportDeclaracionIvaDetalladaExcel(
          negocioNombre: widget.negocio.nombreComercial,
          periodo: _periodoIvaTexto,
          declaracion: declaracion,
          facturas: facturas,
          notasCredito: notas,
          compras: compras,
        );
      } else {
        await ExportService.exportDeclaracionIvaDetalladaPdf(
          negocioNombre: widget.negocio.nombreComercial,
          negocioCedula: widget.negocio.cedula,
          periodo: _periodoIvaTexto,
          declaracion: declaracion,
          facturas: facturas,
          notasCredito: notas,
          compras: compras,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al exportar: $e")));
      }
    } finally {
      if (mounted) setState(() => _exportandoIva = false);
    }
  }

  Future<void> _exportarRenta({required bool excel}) async {
    if (_exportandoRenta) return;
    setState(() => _exportandoRenta = true);
    try {
      final inicioAnio = DateTime(_anioRenta, 1, 1);
      final finAnio = DateTime(_anioRenta, 12, 31);
      final resultados = await Future.wait([
        _declaracionRentaFuture,
        _obtenerFacturasPeriodo(inicioAnio, finAnio),
        _obtenerComprasPeriodo(inicioAnio, finAnio),
        _obtenerGastosAnio(_anioRenta),
      ]);
      final declaracion = resultados[0] as Map<String, dynamic>;
      final facturas = resultados[1] as List<Factura>;
      final compras = resultados[2] as List<Compra>;
      final gastos = resultados[3] as List<GastoOperativo>;

      if (declaracion.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo cargar la declaración de Renta para exportar")),
          );
        }
        return;
      }

      if (excel) {
        await ExportService.exportDeclaracionRentaDetalladaExcel(
          negocioNombre: widget.negocio.nombreComercial,
          declaracion: declaracion,
          facturas: facturas,
          compras: compras,
          gastos: gastos,
        );
      } else {
        await ExportService.exportDeclaracionRentaDetalladaPdf(
          negocioNombre: widget.negocio.nombreComercial,
          negocioCedula: widget.negocio.cedula,
          declaracion: declaracion,
          facturas: facturas,
          compras: compras,
          gastos: gastos,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al exportar: $e")));
      }
    } finally {
      if (mounted) setState(() => _exportandoRenta = false);
    }
  }

  Future<void> _gestionarClienteInternamente() async {
    if (_entrandoAGestionInterna) return;
    setState(() => _entrandoAGestionInterna = true);
    // Deja ver la animacion del interruptor prendiendose antes de arrancar
    // la transicion de pantalla -- si se navega en el mismo frame, el
    // usuario nunca alcanza a percibir el cambio.
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => DetalleNegocio(negocio: widget.negocio),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curva = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curva,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curva),
              child: child,
            ),
          );
        },
      ),
    );
    if (mounted) setState(() => _entrandoAGestionInterna = false);
  }

  /// Fila con el label + un control tipo "interruptor" (track + thumb que se
  /// desliza, como un Switch) en vez del boton grande de siempre -- antes
  /// quedaba hasta abajo de toda la pantalla, obligando a hacer scroll para
  /// encontrarlo; ahora esta justo debajo de los datos del negocio.
  Widget _botonGestionarInterno() {
    final activo = _entrandoAGestionInterna;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: activo ? null : _gestionarClienteInternamente,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: activo ? AppColors.primary.withOpacity(0.10) : AppColors.surface,
            border: Border.all(color: activo ? AppColors.primary : AppColors.border, width: activo ? 1.6 : 1),
            boxShadow: activo
                ? [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 14, spreadRadius: 1)]
                : const [],
          ),
          child: Row(
            children: [
              Icon(Icons.settings_suggest_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 280),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: activo ? AppColors.primary : AppColors.textStrong,
                    fontSize: 14.5,
                  ),
                  child: const Text("Gestionar cliente internamente"),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                width: 54,
                height: 30,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: activo
                        ? [AppColors.primary, const Color(0xFF1E1B4B)]
                        : [AppColors.textMuted.withOpacity(0.30), AppColors.textMuted.withOpacity(0.20)],
                  ),
                  boxShadow: activo
                      ? [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 8)]
                      : const [],
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  alignment: activo ? Alignment.centerRight : Alignment.centerLeft,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    scale: activo ? 1.15 : 1.0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: RotationTransition(turns: anim, child: child),
                        ),
                        child: Icon(
                          activo ? Icons.check_rounded : Icons.arrow_forward_ios_rounded,
                          key: ValueKey(activo),
                          size: 13,
                          color: activo ? AppColors.primary : const Color(0xFF1E1B4B),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.negocio.nombreComercial),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primary.withOpacity(0.12),
                    child: Icon(Icons.business_center, color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.negocio.nombreComercial, style: TextStyle(color: AppColors.textStrong, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("Cédula: ${widget.negocio.cedula}", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _botonGestionarInterno(),
            const SizedBox(height: 26),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text("Declaración de IVA (Borrador del Periodo)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                ),
                if (_exportandoIva)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  IconButton(
                    tooltip: "Exportar a PDF (detallado)",
                    onPressed: () => _exportarIva(excel: false),
                    icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: "Exportar a Excel (detallado)",
                    onPressed: () => _exportarIva(excel: true),
                    icon: const Icon(Icons.table_chart_outlined, color: Colors.green),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: "Mes anterior",
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _irAMesIva(-1),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _irAMesIva(0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      _esMesCompletoIva
                          ? _mesAnioIvaTexto
                          : "${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} - ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}",
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: "Mes siguiente",
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _irAMesIva(1),
                ),
                IconButton(
                  icon: const Icon(Icons.date_range, size: 18),
                  tooltip: "Elegir un rango de fechas personalizado",
                  visualDensity: VisualDensity.compact,
                  onPressed: _cambiarPeriodoIva,
                ),
              ],
            ),
            const SizedBox(height: 15),
            FutureBuilder<Map<String, dynamic>>(
              future: _declaracionIvaFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                final d = snapshot.data ?? {};
                if (d.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: const Text("No se pudo cargar la declaración de IVA de este periodo", style: TextStyle(color: Colors.grey)),
                  );
                }
                return buildDeclaracionIva(d);
              },
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text("Declaración de Renta (Borrador Anual)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                ),
                if (_exportandoRenta)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  IconButton(
                    tooltip: "Exportar a PDF (detallado)",
                    onPressed: () => _exportarRenta(excel: false),
                    icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: "Exportar a Excel (detallado)",
                    onPressed: () => _exportarRenta(excel: true),
                    icon: const Icon(Icons.table_chart_outlined, color: Colors.green),
                  ),
                ],
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _anioRenta,
                    items: List.generate(5, (i) => DateTime.now().year - i)
                        .map((a) => DropdownMenuItem(value: a, child: Text("Periodo fiscal $a")))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _cambiarAnioRenta(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            FutureBuilder<Map<String, dynamic>>(
              future: _declaracionRentaFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                final d = snapshot.data ?? {};
                if (d.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: const Text("No se pudo cargar la declaración de Renta de este periodo", style: TextStyle(color: Colors.grey)),
                  );
                }
                return buildDeclaracionRenta(d);
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
