import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'conciliacion_util.dart';
import 'cuenta_contable.dart';
import 'formato.dart';
import 'perfil_sesion.dart';
import 'recorridos.dart';
import 'widgets/recorrido_guiado.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Conciliación bancaria de una cuenta, mes a mes: el estado de cuenta del
/// banco (Excel o CSV, leído con [leerEstadoDeCuenta]) contra los
/// movimientos en libros. La trabaja y la cierra el contador; el dueño del
/// negocio solo la ve. Backend: gestion/conciliacion.py.
class ConciliacionesScreen extends StatefulWidget {
  final int negocioId;
  final Map<String, dynamic> cuenta;
  final List<CuentaContable> catalogo;
  const ConciliacionesScreen({super.key, required this.negocioId, required this.cuenta, required this.catalogo});

  @override
  State<ConciliacionesScreen> createState() => _ConciliacionesScreenState();
}

/// Contador, despacho o administrador (los que concilian, igual que
/// es_contador en gestion/bancos.py).
bool get _esContador => const {'socio', 'despacho', 'superuser'}.contains(PerfilSesion.rol);

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String _nombreMes(String fechaIso) {
  final f = DateTime.parse(fechaIso);
  final m = _meses[f.month - 1];
  return "${m[0].toUpperCase()}${m.substring(1)} ${f.year}";
}

String _fechaCorta(String? fechaIso) {
  if (fechaIso == null || fechaIso.isEmpty) return '';
  final f = DateTime.parse(fechaIso);
  return "${f.day}/${f.month}/${f.year}";
}

String _dinero(dynamic valor, String moneda, {bool signo = false}) {
  final v = double.tryParse(valor?.toString() ?? '') ?? 0;
  final texto = moneda == 'USD' ? formatearDolares(v.abs()) : formatearColones(v.abs());
  if (v < 0) return "-$texto";
  return signo && v > 0 ? "+$texto" : texto;
}

void _aviso(BuildContext context, Object mensaje) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(mensaje))));
}

const _verde = Color(0xFF16A34A);
const _ambar = Color(0xFFD97706);
const _rojo = Color(0xFFDC2626);

class _ConciliacionesScreenState extends State<ConciliacionesScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _conciliaciones = [];

  String get _moneda => widget.cuenta['moneda'].toString();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = ApiService.verificar(
          await ApiService.get('/conciliaciones-bancarias/?negocio=${widget.negocioId}&cuenta=${widget.cuenta['id']}'));
      _conciliaciones = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (mounted) _aviso(context, "No se pudieron cargar las conciliaciones: $e");
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _nueva() async {
    // Por defecto el mes pasado (o el siguiente al último conciliado).
    final hoy = DateTime.now();
    final opciones = List.generate(18, (i) => DateTime(hoy.year, hoy.month - 1 - i, 1));
    final yaHechos = _conciliaciones.map((c) => c['fecha_fin'].toString().substring(0, 7)).toSet();
    String clave(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}";
    DateTime mes = opciones.firstWhere((d) => !yaHechos.contains(clave(d)), orElse: () => opciones.first);
    final saldo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Nueva conciliación"),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<DateTime>(
                initialValue: mes,
                decoration: const InputDecoration(labelText: "Mes"),
                items: opciones
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text("${_nombreMes(d.toIso8601String())}${yaHechos.contains(clave(d)) ? '  (ya existe)' : ''}"),
                        ))
                    .toList(),
                onChanged: (v) => set(() => mes = v ?? mes),
              ),
              TextField(
                controller: saldo,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: "Saldo final según el banco ($_moneda) *",
                  helperText: "El que dice el estado de cuenta al último día del mes.",
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Crear")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final fin = DateTime(mes.year, mes.month + 1, 0);
    try {
      final r = ApiService.verificar(await ApiService.post('/conciliaciones-bancarias/', {
        'negocio': widget.negocioId,
        'cuenta': widget.cuenta['id'],
        'fecha_inicio': mes.toIso8601String().substring(0, 10),
        'fecha_fin': fin.toIso8601String().substring(0, 10),
        'saldo_banco': saldo.text.trim().replaceAll(',', '.').isEmpty ? '0' : saldo.text.trim().replaceAll(',', '.'),
      }));
      final creada = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      await _cargar();
      if (mounted) await _abrir(creada);
    } catch (e) {
      if (mounted) _aviso(context, e);
    }
  }

  Future<void> _abrir(Map<String, dynamic> c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ConciliacionDetalleScreen(conciliacionId: c['id'], cuenta: widget.cuenta, catalogo: widget.catalogo),
      ),
    );
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cuenta;
    return Scaffold(
      appBar: AppBar(
        title: Text("Conciliación · ${c['banco']} ${c['nombre']}"),
        actions: [const BotonCalculadora(), IconButton(tooltip: "Actualizar", icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      floatingActionButton: _esContador
          ? FloatingActionButton.extended(onPressed: _nueva, icon: const Icon(Icons.add), label: const Text("Nueva conciliación"))
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _conciliaciones.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.fact_check_outlined, size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        _esContador
                            ? "Todavía no hay conciliaciones de esta cuenta.\nCreá la del mes con el saldo del estado de cuenta y "
                                "cargá el Excel o CSV del banco: lo que coincida se empareja solo."
                            : "Tu contador todavía no ha conciliado esta cuenta.\nCuando lo haga, aquí vas a ver cada mes y si cuadró con el banco.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: _conciliaciones.map((con) {
                    final res = (con['resumen'] as Map?) ?? {};
                    final cerrada = con['estado'] == 'cerrada';
                    final cuadra = res['cuadra'] == true;
                    final color = cerrada ? _verde : (cuadra ? AppColors.primary : _ambar);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () => _abrir(con),
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Icon(cerrada ? Icons.lock_outline : Icons.pending_actions_outlined, color: color),
                        ),
                        title: Text(_nombreMes(con['fecha_fin']), style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "${cerrada ? 'Cerrada' : 'En proceso'} · ${res['lineas_emparejadas'] ?? 0} de ${res['lineas_total'] ?? 0} líneas del banco emparejadas"
                          "${cerrada && con['cerrada_en'] != null ? ' · ${_fechaCorta(con['cerrada_en'].toString().substring(0, 10))}' : ''}",
                        ),
                        trailing: _EtiquetaCuadre(cuadra: cuadra, diferencia: res['diferencia'], moneda: _moneda),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}

class _EtiquetaCuadre extends StatelessWidget {
  final bool cuadra;
  final dynamic diferencia;
  final String moneda;
  const _EtiquetaCuadre({required this.cuadra, required this.diferencia, required this.moneda});

  @override
  Widget build(BuildContext context) {
    final color = cuadra ? _verde : _rojo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(cuadra ? Icons.check_circle : Icons.error_outline, size: 15, color: color),
        const SizedBox(width: 4),
        Text(cuadra ? "Cuadra" : "Dif. ${_dinero(diferencia, moneda)}",
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConciliacionDetalleScreen extends StatefulWidget {
  final int conciliacionId;
  final Map<String, dynamic> cuenta;
  final List<CuentaContable> catalogo;
  const _ConciliacionDetalleScreen({required this.conciliacionId, required this.cuenta, required this.catalogo});

  @override
  State<_ConciliacionDetalleScreen> createState() => _ConciliacionDetalleScreenState();
}

class _ConciliacionDetalleScreenState extends State<_ConciliacionDetalleScreen> {
  bool _cargando = true;
  bool _trabajando = false;
  Map<String, dynamic>? _datos;

  // Tipos para registrar en libros una línea del banco, por signo, y la
  // contrapartida sugerida (catálogo estándar de CR, igual que en Bancos).
  static const _tiposEntrada = {'deposito': 'Depósito', 'interes': 'Interés ganado'};
  static const _tiposSalida = {
    'comision': 'Comisión bancaria',
    'cargo': 'Otro cargo del banco',
    'transferencia_salida': 'Transferencia / pago',
    'retiro': 'Retiro',
    'cheque': 'Cheque emitido',
  };
  static const _contrapartidaSugerida = {
    'deposito': '1104',
    'interes': '4104',
    'retiro': '1101',
    'cheque': '2101',
    'transferencia_salida': '2101',
    'comision': '6110',
    'cargo': '6110',
  };

  String get _moneda => widget.cuenta['moneda'].toString();
  String get _base => '/conciliaciones-bancarias/${widget.conciliacionId}';
  bool get _cerrada => _datos?['estado'] == 'cerrada';
  bool get _editable => _esContador && !_cerrada;
  Map<String, dynamic> get _resumen => (_datos?['resumen'] as Map?)?.cast<String, dynamic>() ?? {};
  List<Map<String, dynamic>> get _lineas => ((_datos?['lineas'] as List?) ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _pendientes => ((_datos?['movimientos_pendientes'] as List?) ?? []).cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get('$_base/'));
      _datos = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      if (mounted) _aviso(context, "No se pudo cargar la conciliación: $e");
    }
    if (mounted) setState(() => _cargando = false);
    if (mounted && _editable) {
      ofrecerRecorrido(context, clave: GuiaConciliacion.clave, titulo: "se concilia un mes", iniciar: () => GuiaConciliacion.mostrar(context));
    }
  }

  /// Corre una acción contra el backend y recarga; devuelve la respuesta.
  Future<Map<String, dynamic>?> _accion(String ruta, [Map<String, dynamic> cuerpo = const {}]) async {
    setState(() => _trabajando = true);
    Map<String, dynamic>? respuesta;
    try {
      final r = ApiService.verificar(await ApiService.post('$_base/$ruta/', cuerpo));
      final cuerpoRespuesta = utf8.decode(r.bodyBytes);
      respuesta = cuerpoRespuesta.isEmpty ? {} : json.decode(cuerpoRespuesta) as Map<String, dynamic>;
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(context, e);
    }
    if (mounted) setState(() => _trabajando = false);
    return respuesta;
  }

  Future<void> _cargarEstadoDeCuenta() async {
    final elegido = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv'], withData: true);
    final archivo = elegido?.files.firstOrNull;
    if (archivo?.bytes == null) return;
    List<Map<String, dynamic>> filas;
    try {
      filas = leerEstadoDeCuenta(archivo!.bytes!, archivo.name);
    } catch (e) {
      if (mounted) _aviso(context, e);
      return;
    }
    if (!mounted) return;
    final entradas = filas.map((f) => double.parse(f['monto'])).where((m) => m > 0).fold<double>(0, (a, b) => a + b);
    final salidas = filas.map((f) => double.parse(f['monto'])).where((m) => m < 0).fold<double>(0, (a, b) => a + b);
    final fechas = filas.map((f) => f['fecha'].toString()).toList()..sort();
    bool reemplazar = _lineas.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Estado de cuenta"),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(archivo.name, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Text("${filas.length} movimientos del ${_fechaCorta(fechas.first)} al ${_fechaCorta(fechas.last)}",
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text("Entradas ${_dinero(entradas, _moneda)}  ·  Salidas ${_dinero(salidas.abs(), _moneda)}"),
              if (_lineas.isNotEmpty) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reemplazar,
                  onChanged: (v) => set(() => reemplazar = v ?? false),
                  title: Text("Reemplazar las ${_lineas.length} líneas que ya estaban"),
                  subtitle: const Text("Si no, se agregan a las que ya hay."),
                ),
              ],
              const SizedBox(height: 4),
              Text("Lo que coincida con libros (mismo monto, hasta 5 días de diferencia) se empareja solo.",
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Cargar")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final r = await _accion('lineas', {'filas': filas, 'reemplazar': reemplazar});
    if (r != null && mounted) _aviso(context, "Se cargaron ${r['creadas']} líneas y ${r['emparejadas']} se emparejaron solas.");
  }

  Future<void> _emparejarAuto() async {
    final r = await _accion('emparejar-auto');
    if (r != null && mounted) {
      _aviso(context, r['emparejadas'] == 0 ? "No hubo más coincidencias: emparejá el resto a mano." : "Se emparejaron ${r['emparejadas']} líneas.");
    }
  }

  Future<void> _emparejarAMano(Map<String, dynamic> linea) async {
    final monto = double.parse(linea['monto'].toString());
    final fechaLinea = DateTime.parse(linea['fecha']);
    final candidatos = _pendientes.where((m) {
      final conSigno = double.parse(m['monto'].toString()) * (m['es_entrada'] == true ? 1 : -1);
      return (conSigno - monto).abs() < 0.005;
    }).toList()
      ..sort((a, b) => DateTime.parse(a['fecha']).difference(fechaLinea).inDays.abs()
          .compareTo(DateTime.parse(b['fecha']).difference(fechaLinea).inDays.abs()));
    final elegido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text("Emparejar ${_dinero(monto, _moneda, signo: true)} del ${_fechaCorta(linea['fecha'])}"),
        children: candidatos.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Text(
                    "No hay movimientos en libros pendientes por ese mismo monto.\nSi el banco lo cobró o acreditó y no estaba anotado, "
                    "usá \"Registrar en libros\".",
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ]
            : candidatos
                .map((m) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, m),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(m['descripcion'].toString()),
                        subtitle: Text("${_fechaCorta(m['fecha'])} · ${m['tipo_nombre']}"
                            "${(m['referencia'] ?? '').toString().isNotEmpty ? ' · Ref. ${m['referencia']}' : ''}"),
                      ),
                    ))
                .toList(),
      ),
    );
    if (elegido == null) return;
    await _accion('emparejar', {'linea': linea['id'], 'movimiento': elegido['id']});
  }

  Future<void> _registrarEnLibros(Map<String, dynamic> linea) async {
    if (_moneda == 'USD') {
      _aviso(context, "En cuentas en dólares registrá el movimiento desde la cuenta (con su tipo de cambio) y después emparejalo.");
      return;
    }
    final entra = double.parse(linea['monto'].toString()) > 0;
    final tipos = entra ? _tiposEntrada : _tiposSalida;
    final descripcion = '${linea['descripcion'] ?? ''}'.toLowerCase();
    String tipo = entra
        ? (descripcion.contains('interes') || descripcion.contains('interés') ? 'interes' : 'deposito')
        : (descripcion.contains('comision') || descripcion.contains('comisión') ? 'comision' : 'cargo');
    final detalle = widget.catalogo.where((c) => c.esDetalle && c.id != widget.cuenta['cuenta_contable']).toList();
    int? sugerida(String t) {
      for (final c in detalle) {
        if (c.codigo == _contrapartidaSugerida[t]) return c.id;
      }
      return null;
    }

    int? contrapartida = sugerida(tipo);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Registrar en libros"),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${linea['descripcion'] ?? ''}", style: const TextStyle(fontWeight: FontWeight.w600)),
              Text("${_fechaCorta(linea['fecha'])} · ${_dinero(linea['monto'], _moneda, signo: true)}",
                  style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: tipo,
                decoration: const InputDecoration(labelText: "Tipo"),
                items: tipos.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => set(() {
                  tipo = v ?? tipo;
                  contrapartida = sugerida(tipo) ?? contrapartida;
                }),
              ),
              DropdownButtonFormField<int>(
                initialValue: contrapartida,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Contrapartida (cuenta contable) *"),
                items: detalle
                    .map((c) => DropdownMenuItem(value: c.id, child: Text("${c.codigo} · ${c.nombre}", overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => set(() => contrapartida = v),
              ),
              const SizedBox(height: 8),
              Text("Se crea el movimiento con su asiento y queda emparejado con esta línea.",
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: contrapartida == null ? null : () => Navigator.pop(ctx, true), child: const Text("Registrar")),
          ],
        ),
      ),
    );
    if (ok != true || contrapartida == null) return;
    await _accion('registrar-linea', {'linea': linea['id'], 'contrapartida': contrapartida, 'tipo': tipo});
  }

  Future<void> _editarSaldo() async {
    final saldo = TextEditingController(text: _datos?['saldo_banco']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Saldo según el banco"),
        content: TextField(
          controller: saldo,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: "Saldo final al ${_fechaCorta(_datos?['fecha_fin'])} ($_moneda)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.patch('$_base/', {'saldo_banco': saldo.text.trim().replaceAll(',', '.')}));
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(context, e);
    }
  }

  Future<void> _cerrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Cerrar la conciliación?"),
        content: Text(
          "Los movimientos de esta cuenta hasta el ${_fechaCorta(_datos?['fecha_fin'])} quedan bloqueados: nadie los puede "
          "agregar, editar ni eliminar. Podés reabrirla si hace falta corregir algo.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Cerrar mes")),
        ],
      ),
    );
    if (ok != true) return;
    if (await _accion('cerrar') != null && mounted) _aviso(context, "Conciliación cerrada: el mes quedó bloqueado.");
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Eliminar la conciliación?"),
        content: const Text("Se borran las líneas cargadas del banco. Los movimientos en libros no se tocan."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Eliminar", style: TextStyle(color: _rojo))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.delete('$_base/'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _aviso(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _datos == null ? "Conciliación" : "Conciliación · ${_nombreMes(_datos!['fecha_fin'])}";
    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        actions: [const BotonCalculadora(), 
          if (_editable) ...[
            IconButton(
                key: GuiaConciliacion.cargar,
                tooltip: "Cargar estado de cuenta (Excel o CSV)",
                icon: const Icon(Icons.upload_file),
                onPressed: _trabajando ? null : _cargarEstadoDeCuenta),
            IconButton(
                key: GuiaConciliacion.emparejar,
                tooltip: "Emparejar automático",
                icon: const Icon(Icons.auto_fix_high),
                onPressed: _trabajando ? null : _emparejarAuto),
          ],
          BotonGuia(iniciar: () => GuiaConciliacion.mostrar(context)),
          if (_esContador && _datos != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'saldo') _editarSaldo();
                if (v == 'reabrir') _accion('reabrir');
                if (v == 'eliminar') _eliminar();
              },
              itemBuilder: (_) => [
                if (!_cerrada) const PopupMenuItem(value: 'saldo', child: Text("Cambiar saldo del banco")),
                if (_cerrada) const PopupMenuItem(value: 'reabrir', child: Text("Reabrir")),
                if (!_cerrada) const PopupMenuItem(value: 'eliminar', child: Text("Eliminar conciliación")),
              ],
            ),
        ],
        bottom: _trabajando ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
      ),
      bottomNavigationBar: _editable && _datos != null ? _barraCierre() : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _datos == null
              ? const SizedBox.shrink()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _tarjetaResumen(),
                      const SizedBox(height: 20),
                      ..._seccionBanco(),
                      const SizedBox(height: 20),
                      ..._seccionLibros(),
                    ],
                  ),
                ),
    );
  }

  Widget _barraCierre() {
    final cuadra = _resumen['cuadra'] == true;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Expanded(
            child: Text(
              cuadra ? "Cuadra con el banco: ya podés cerrar el mes." : "Diferencia de ${_dinero(_resumen['diferencia'], _moneda)}: revisá las partidas.",
              style: TextStyle(color: cuadra ? _verde : _rojo, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            key: GuiaConciliacion.cerrar,
            onPressed: cuadra && !_trabajando ? _cerrar : null,
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text("Cerrar mes"),
          ),
        ]),
      ),
    );
  }

  Widget _tarjetaResumen() {
    final r = _resumen;
    final cuadra = r['cuadra'] == true;
    Widget fila(String etiqueta, dynamic valor, {bool total = false, bool signo = false, String? ayuda}) => Padding(
          padding: EdgeInsets.only(top: total ? 6 : 3),
          child: Row(children: [
            Expanded(
              child: Tooltip(
                message: ayuda ?? '',
                child: Text(etiqueta, style: TextStyle(fontWeight: total ? FontWeight.w700 : FontWeight.normal, color: total ? null : AppColors.textMuted)),
              ),
            ),
            Text(_dinero(valor, _moneda, signo: signo), style: TextStyle(fontWeight: total ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    Widget columna(String titulo, IconData icono, List<Widget> filas) => Container(
          constraints: const BoxConstraints(minWidth: 260, maxWidth: 420),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icono, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ...filas,
          ]),
        );
    final pagos = double.tryParse(r['pagos_pendientes']?.toString() ?? '') ?? 0;
    return Column(key: GuiaConciliacion.resumen, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text("Del ${_fechaCorta(_datos!['fecha_inicio'])} al ${_fechaCorta(_datos!['fecha_fin'])}",
              style: TextStyle(color: AppColors.textMuted)),
        ),
        if (_cerrada)
          Chip(
            avatar: const Icon(Icons.lock_outline, size: 16, color: _verde),
            label: const Text("Cerrada"),
            backgroundColor: _verde.withValues(alpha: 0.1),
            side: BorderSide.none,
          ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        columna("Según el banco", Icons.account_balance_outlined, [
          fila("Saldo del estado de cuenta", r['saldo_banco']),
          fila("+ Depósitos en tránsito", r['depositos_en_transito'],
              ayuda: "Entradas anotadas en libros que el banco todavía no refleja."),
          fila("− Pagos pendientes", pagos == 0 ? 0 : -pagos, ayuda: "Cheques y pagos anotados en libros que el banco todavía no cobra."),
          const Divider(height: 14),
          fila("Saldo ajustado", r['saldo_banco_ajustado'], total: true),
        ]),
        columna("Según libros", Icons.menu_book_outlined, [
          fila("Saldo en libros", r['saldo_libros']),
          fila("± Del banco sin registrar", r['lineas_banco_sin_registrar'], signo: true,
              ayuda: "Comisiones, intereses o depósitos que están en el banco y no en libros."),
          const SizedBox(height: 21),
          const Divider(height: 14),
          fila("Saldo ajustado", r['saldo_libros_ajustado'], total: true),
        ]),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (cuadra ? _verde : _rojo).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(cuadra ? Icons.check_circle : Icons.error_outline, color: cuadra ? _verde : _rojo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              cuadra ? "Cuadra: los dos saldos ajustados son iguales." : "Diferencia de ${_dinero(r['diferencia'], _moneda)} entre banco y libros.",
              style: TextStyle(fontWeight: FontWeight.w600, color: cuadra ? _verde : _rojo),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _titulo(String texto, String ayuda, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(ayuda, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        ]),
      );

  List<Widget> _seccionBanco() {
    final lineas = [..._lineas]..sort((a, b) => (a['movimiento'] == null ? 0 : 1).compareTo(b['movimiento'] == null ? 0 : 1));
    final sueltas = lineas.where((l) => l['movimiento'] == null).length;
    return [
      _titulo(
        key: GuiaConciliacion.banco,
        "Estado de cuenta del banco (${lineas.length})",
        lineas.isEmpty ? "Cargá el Excel o CSV que descargás del banco." : "$sueltas sin emparejar · ${lineas.length - sueltas} emparejadas",
      ),
      if (lineas.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Icon(Icons.upload_file, size: 36, color: AppColors.textMuted),
              const SizedBox(height: 8),
              Text(
                _editable
                    ? "Columnas que se reconocen: Fecha, Descripción, Referencia y Monto (o Débito y Crédito)."
                    : "Todavía no se cargó el estado de cuenta.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
              if (_editable) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _trabajando ? null : _cargarEstadoDeCuenta,
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Cargar estado de cuenta"),
                ),
              ],
            ]),
          ),
        ),
      ...lineas.map((l) {
        final emparejada = l['movimiento'] != null;
        final monto = double.tryParse(l['monto'].toString()) ?? 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(emparejada ? Icons.link : Icons.link_off, color: emparejada ? _verde : _ambar),
            title: Text((l['descripcion'] ?? '').toString().isEmpty ? 'Sin descripción' : l['descripcion'].toString()),
            subtitle: Text(
              "${_fechaCorta(l['fecha'])}${(l['referencia'] ?? '').toString().isNotEmpty ? ' · Ref. ${l['referencia']}' : ''}"
              "${emparejada ? '\nEn libros: ${l['movimiento_descripcion']} (${_fechaCorta(l['movimiento_fecha']?.toString())})' : ''}",
            ),
            isThreeLine: emparejada,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_dinero(monto, _moneda, signo: true),
                  style: TextStyle(fontWeight: FontWeight.bold, color: monto >= 0 ? _verde : _rojo)),
              if (_editable)
                PopupMenuButton<String>(
                  enabled: !_trabajando,
                  onSelected: (v) {
                    if (v == 'emparejar') _emparejarAMano(l);
                    if (v == 'registrar') _registrarEnLibros(l);
                    if (v == 'soltar') _accion('desemparejar', {'linea': l['id']});
                  },
                  itemBuilder: (_) => emparejada
                      ? [const PopupMenuItem(value: 'soltar', child: Text("Desemparejar"))]
                      : [
                          const PopupMenuItem(value: 'emparejar', child: Text("Emparejar con un movimiento")),
                          const PopupMenuItem(value: 'registrar', child: Text("Registrar en libros")),
                        ],
                ),
            ]),
          ),
        );
      }),
    ];
  }

  List<Widget> _seccionLibros() {
    final pendientes = _pendientes.where((m) => !_lineas.any((l) => l['movimiento'] == m['id'])).toList();
    return [
      _titulo(
        "En libros y no en el banco (${pendientes.length})",
        "Depósitos en tránsito y cheques o pagos que el banco todavía no refleja al cierre.",
      ),
      if (pendientes.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text("Ninguno: todo lo de libros está en el banco.", style: TextStyle(color: AppColors.textMuted)),
        ),
      ...pendientes.map((m) {
        final entra = m['es_entrada'] == true;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(entra ? Icons.south_west : Icons.north_east, color: entra ? _verde : _rojo),
            title: Text(m['descripcion'].toString()),
            subtitle: Text("${_fechaCorta(m['fecha'])} · ${entra ? 'Depósito en tránsito' : 'Pago pendiente'} · ${m['tipo_nombre']}"
                "${(m['referencia'] ?? '').toString().isNotEmpty ? ' · Ref. ${m['referencia']}' : ''}"),
            trailing: Text("${entra ? '+' : '-'}${_dinero(m['monto'], _moneda)}",
                style: TextStyle(fontWeight: FontWeight.bold, color: entra ? _verde : _rojo)),
          ),
        );
      }),
    ];
  }
}
