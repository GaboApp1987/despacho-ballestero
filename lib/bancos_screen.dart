import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'conciliacion_screen.dart';
import 'recorridos.dart';
import 'widgets/recorrido_guiado.dart';
import 'cuenta_contable.dart';
import 'formato.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Bancos de un negocio: cuentas con su saldo, movimientos (cada uno con su
/// asiento contable automático) y traslados entre cuentas propias. La usan
/// el contador (eligiendo el cliente, ver [abrirBancos]) y el dueño del
/// negocio. Backend: gestion/bancos.py.
class BancosScreen extends StatefulWidget {
  final int negocioId;
  final String negocioNombre;
  // Dentro de la app del negocio (una sección más): sin barra propia.
  final bool embebido;
  const BancosScreen({super.key, required this.negocioId, required this.negocioNombre, this.embebido = false});

  @override
  State<BancosScreen> createState() => _BancosScreenState();
}

String _monto(dynamic valor, String moneda) {
  final v = double.tryParse(valor?.toString() ?? '') ?? 0;
  return moneda == 'USD' ? formatearDolares(v) : formatearColones(v);
}

class _BancosScreenState extends State<BancosScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _cuentas = [];
  List<CuentaContable> _catalogo = [];
  // Otros medios de pago (PayPal, tarjeta...): salen en las facturas.
  List<Map<String, dynamic>> _medios = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await Future.wait([
        ApiService.get('/cuentas-bancarias/?negocio=${widget.negocioId}'),
        ApiService.get('/cuentas-contables/?negocio=${widget.negocioId}'),
        ApiService.get('/medios-pago/?negocio=${widget.negocioId}'),
      ]);
      ApiService.verificar(r[0]);
      _cuentas = (json.decode(utf8.decode(r[0].bodyBytes)) as List).cast<Map<String, dynamic>>();
      if (r[2].statusCode == 200) {
        _medios = (json.decode(utf8.decode(r[2].bodyBytes)) as List).cast<Map<String, dynamic>>();
      }
      if (r[1].statusCode == 200) {
        _catalogo = (json.decode(utf8.decode(r[1].bodyBytes)) as List).map((j) => CuentaContable.fromJson(j)).toList();
      }
      if (mounted) ofrecerRecorrido(context, clave: GuiaBancos.clave, titulo: "funcionan los bancos", iniciar: () => GuiaBancos.mostrar(context));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudieron cargar los bancos: ${ApiService.textoError(e)}")));
    }
    if (mounted) setState(() => _cargando = false);
  }

  /// Nueva cuenta o, con [existente], editar sus datos (banco, nombre,
  /// número, IBAN y si sale en las facturas; moneda y saldo inicial no se
  /// cambian porque ya tienen movimientos y asientos).
  Future<void> _formularioCuenta({Map<String, dynamic>? existente}) async {
    final banco = TextEditingController(text: existente?['banco'] ?? '');
    final nombre = TextEditingController(text: existente?['nombre'] ?? '');
    final numero = TextEditingController(text: existente?['numero'] ?? '');
    final iban = TextEditingController(text: existente?['iban'] ?? '');
    final saldo = TextEditingController(text: '0');
    String moneda = 'CRC';
    DateTime fecha = DateTime.now();
    bool mostrar = existente?['mostrar_en_facturas'] ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existente == null ? "Nueva cuenta bancaria" : "Editar cuenta"),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: banco, decoration: const InputDecoration(labelText: "Banco *", hintText: "BCR, BN, BAC... o Caja")),
                TextField(controller: nombre, decoration: const InputDecoration(labelText: "Nombre *", hintText: "Ej. Operativa colones")),
                TextField(controller: numero, decoration: const InputDecoration(labelText: "Número de cuenta", hintText: "Ej. 100-01-000-123456")),
                TextField(
                  controller: iban,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: "Cuenta IBAN", hintText: "CR + 20 dígitos"),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: mostrar,
                  onChanged: (v) => set(() => mostrar = v ?? true),
                  title: const Text("Mostrar en facturas y cotizaciones"),
                  subtitle: const Text("Para que el cliente sepa a dónde transferir", style: TextStyle(fontSize: 12)),
                ),
                if (existente == null) ...[
                DropdownButtonFormField<String>(
                  initialValue: moneda,
                  decoration: const InputDecoration(labelText: "Moneda"),
                  items: const [
                    DropdownMenuItem(value: 'CRC', child: Text("Colones")),
                    DropdownMenuItem(value: 'USD', child: Text("Dólares")),
                  ],
                  onChanged: (v) => set(() => moneda = v ?? 'CRC'),
                ),
                TextField(
                  controller: saldo,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Saldo inicial"),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Fecha del saldo inicial"),
                  subtitle: Text("${fecha.day}/${fecha.month}/${fecha.year}"),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final f = await showDatePicker(context: ctx, initialDate: fecha, firstDate: DateTime(2015), lastDate: DateTime(2100));
                    if (f != null) set(() => fecha = f);
                  },
                ),
                const Text(
                  "Se le crea su propia cuenta contable dentro de Activo Circulante, para que el mayor de cada banco salga por separado.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(existente == null ? "Crear" : "Guardar")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final ibanLimpio = iban.text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (ibanLimpio.isNotEmpty && !RegExp(r'^CR\d{20}$').hasMatch(ibanLimpio)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("El IBAN de Costa Rica es CR seguido de 20 dígitos. Revisalo e intentá de nuevo.")));
      }
      return;
    }
    try {
      if (existente != null) {
        ApiService.verificar(await ApiService.patch('/cuentas-bancarias/${existente['id']}/', {
          'banco': banco.text.trim(),
          'nombre': nombre.text.trim(),
          'numero': numero.text.trim(),
          'iban': ibanLimpio,
          'mostrar_en_facturas': mostrar,
        }));
        await _cargar();
        return;
      }
      ApiService.verificar(await ApiService.post('/cuentas-bancarias/', {
        'negocio': widget.negocioId,
        'banco': banco.text.trim(),
        'nombre': nombre.text.trim(),
        'numero': numero.text.trim(),
        'iban': ibanLimpio,
        'mostrar_en_facturas': mostrar,
        'moneda': moneda,
        'saldo_inicial': saldo.text.trim().replaceAll(',', '.').isEmpty ? '0' : saldo.text.trim().replaceAll(',', '.'),
        'fecha_saldo_inicial': fecha.toIso8601String().substring(0, 10),
      }));
      await _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  /// Otro medio de pago (PayPal, tarjeta en el local...) nuevo o editado.
  Future<void> _formularioMedio({Map<String, dynamic>? existente}) async {
    final nombre = TextEditingController(text: existente?['nombre'] ?? '');
    final detalle = TextEditingController(text: existente?['detalle'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? "Otro medio de pago" : "Editar medio de pago"),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nombre, decoration: const InputDecoration(labelText: "Nombre *", hintText: "Ej. PayPal, Tarjeta, SINPE de la tienda")),
            TextField(
              controller: detalle,
              maxLines: 2,
              decoration: const InputDecoration(labelText: "Datos para pagar", hintText: "Ej. pagos@minegocio.com o 'Visa y Mastercard en el local'"),
            ),
            const SizedBox(height: 8),
            const Text("Sale en las formas de pago de las facturas, las cotizaciones y la página para pagar en línea.",
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    );
    if (ok != true || nombre.text.trim().isEmpty) return;
    try {
      final datos = {'negocio': widget.negocioId, 'nombre': nombre.text.trim(), 'detalle': detalle.text.trim()};
      ApiService.verificar(existente == null
          ? await ApiService.post('/medios-pago/', datos)
          : await ApiService.patch('/medios-pago/${existente['id']}/', datos));
      await _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  Future<void> _eliminarMedio(Map<String, dynamic> medio) async {
    try {
      ApiService.verificar(await ApiService.delete('/medios-pago/${medio['id']}/'));
      await _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  Widget _seccionMedios() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text("Otros medios de pago", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: () => _formularioMedio(), icon: const Icon(Icons.add), label: const Text("Agregar")),
        ]),
        const Text(
          "Además de SINPE y las cuentas marcadas, salen en las facturas: PayPal, tarjeta en el local, otro SINPE...",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        for (final m in _medios)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(m['nombre'] ?? ''),
              subtitle: (m['detalle'] ?? '').toString().isEmpty ? null : Text(m['detalle']),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'editar' ? _formularioMedio(existente: m) : _eliminarMedio(m),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'editar', child: Text("Editar")),
                  PopupMenuItem(value: 'eliminar', child: Text("Eliminar")),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  Future<void> _traslado() async {
    if (_cuentas.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Necesitás al menos dos cuentas para hacer un traslado.")));
      return;
    }
    Map<String, dynamic>? origen = _cuentas[0];
    Map<String, dynamic>? destino = _cuentas[1];
    final monto = TextEditingController();
    final montoDestino = TextEditingController();
    final tc = TextEditingController();
    final descripcion = TextEditingController(text: "Traslado entre cuentas");
    final referencia = TextEditingController();
    DateTime fecha = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final distintas = origen?['moneda'] != destino?['moneda'];
        final hayUsd = origen?['moneda'] == 'USD' || destino?['moneda'] == 'USD';
        DropdownButtonFormField<Map<String, dynamic>> selector(String etiqueta, Map<String, dynamic>? valor, void Function(Map<String, dynamic>?) cambiar) =>
            DropdownButtonFormField<Map<String, dynamic>>(
              initialValue: valor,
              isExpanded: true,
              decoration: InputDecoration(labelText: etiqueta),
              items: _cuentas
                  .map((c) => DropdownMenuItem(value: c, child: Text("${c['banco']} · ${c['nombre']} (${c['moneda']})", overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => set(() => cambiar(v)),
            );
        return AlertDialog(
          title: const Text("Traslado entre cuentas"),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                selector("Sale de", origen, (v) => origen = v),
                selector("Entra a", destino, (v) => destino = v),
                TextField(
                  controller: monto,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: "Monto que sale (${origen?['moneda'] ?? ''})"),
                ),
                if (distintas)
                  TextField(
                    controller: montoDestino,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: "Monto que entra (${destino?['moneda'] ?? ''})"),
                  ),
                if (hayUsd)
                  TextField(
                    controller: tc,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Tipo de cambio (colones por dólar)"),
                  ),
                TextField(controller: descripcion, decoration: const InputDecoration(labelText: "Descripción")),
                TextField(controller: referencia, decoration: const InputDecoration(labelText: "Referencia (opcional)")),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Fecha"),
                  subtitle: Text("${fecha.day}/${fecha.month}/${fecha.year}"),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final f = await showDatePicker(context: ctx, initialDate: fecha, firstDate: DateTime(2015), lastDate: DateTime(2100));
                    if (f != null) set(() => fecha = f);
                  },
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Trasladar")),
          ],
        );
      }),
    );
    if (ok != true || origen == null || destino == null) return;
    String n(TextEditingController c) => c.text.trim().replaceAll(',', '.');
    try {
      ApiService.verificar(await ApiService.post('/movimientos-bancarios/traslado/', {
        'negocio': widget.negocioId,
        'origen': origen!['id'],
        'destino': destino!['id'],
        'fecha': fecha.toIso8601String().substring(0, 10),
        'monto': n(monto),
        if (n(montoDestino).isNotEmpty) 'monto_destino': n(montoDestino),
        if (n(tc).isNotEmpty) 'tipo_cambio': n(tc),
        'descripcion': descripcion.text.trim(),
        'referencia': referencia.text.trim(),
      }));
      await _cargar();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Traslado registrado con su asiento.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final acciones = [
      IconButton(key: GuiaBancos.traslado, tooltip: "Traslado entre cuentas", icon: const Icon(Icons.swap_horiz), onPressed: _cargando ? null : _traslado),
      IconButton(tooltip: "Actualizar", icon: const Icon(Icons.refresh), onPressed: _cargar),
      BotonGuia(iniciar: () => GuiaBancos.mostrar(context)),
    ];
    return Scaffold(
      appBar: widget.embebido
          ? null
          : AppBar(title: Text("Bancos · ${widget.negocioNombre}"), actions: [const BotonCalculadora(), ...acciones]),
      floatingActionButton: FloatingActionButton.extended(
        key: GuiaBancos.nueva,
        onPressed: () => _formularioCuenta(),
        icon: const Icon(Icons.add),
        label: const Text("Nueva cuenta"),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    if (widget.embebido)
                      Row(children: [
                        const Expanded(child: Text("Cuentas bancarias", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                        ...acciones,
                      ]),
                    if (_cuentas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "Todavía no hay cuentas bancarias.\nAgregá las cuentas del negocio (y la caja, si se maneja efectivo) con su saldo inicial.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ..._cuentas
                      .map((c) => Card(
                            key: identical(c, _cuentas.first) ? GuiaBancos.cuenta : null,
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                child: Icon(c['banco'].toString().toLowerCase() == 'caja' ? Icons.point_of_sale : Icons.account_balance, color: AppColors.primary),
                              ),
                              title: Text("${c['banco']} · ${c['nombre']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                "${(c['numero'] ?? '').toString().isNotEmpty ? 'Cuenta ${c['numero']} · ' : ''}"
                                "${(c['iban'] ?? '').toString().isNotEmpty ? 'IBAN ${c['iban']} · ' : ''}"
                                "Cuenta contable ${c['cuenta_contable_codigo'] ?? '-'} · ${c['cantidad_movimientos']} movimiento(s)",
                              ),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(_monto(c['saldo'], c['moneda']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                IconButton(
                                  tooltip: "Editar cuenta",
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _formularioCuenta(existente: c),
                                ),
                              ]),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _MovimientosCuentaScreen(negocioId: widget.negocioId, cuenta: c, catalogo: _catalogo),
                                  ),
                                );
                                _cargar();
                              },
                            ),
                          )),
                    _seccionMedios(),
                  ],
                ),
    );
  }
}

class _MovimientosCuentaScreen extends StatefulWidget {
  final int negocioId;
  final Map<String, dynamic> cuenta;
  final List<CuentaContable> catalogo;
  const _MovimientosCuentaScreen({required this.negocioId, required this.cuenta, required this.catalogo});

  @override
  State<_MovimientosCuentaScreen> createState() => _MovimientosCuentaScreenState();
}

class _MovimientosCuentaScreenState extends State<_MovimientosCuentaScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _movimientos = [];
  String _saldo = '0';

  static const _tipos = {
    'deposito': 'Depósito',
    'interes': 'Interés ganado',
    'retiro': 'Retiro',
    'cheque': 'Cheque emitido',
    'transferencia_salida': 'Transferencia / pago',
    'comision': 'Comisión bancaria',
    'cargo': 'Otro cargo del banco',
  };

  // Contrapartida sugerida por tipo (códigos del catálogo estándar de CR).
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

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await Future.wait([
        ApiService.get('/movimientos-bancarios/?negocio=${widget.negocioId}&cuenta=${widget.cuenta['id']}'),
        ApiService.get('/cuentas-bancarias/${widget.cuenta['id']}/'),
      ]);
      _movimientos = (json.decode(utf8.decode(ApiService.verificar(r[0]).bodyBytes)) as List).cast<Map<String, dynamic>>();
      _saldo = json.decode(utf8.decode(ApiService.verificar(r[1]).bodyBytes))['saldo'].toString();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudieron cargar los movimientos: ${ApiService.textoError(e)}")));
    }
    if (mounted) setState(() => _cargando = false);
  }

  CuentaContable? _porCodigo(String codigo) {
    for (final c in widget.catalogo) {
      if (c.codigo == codigo) return c;
    }
    return null;
  }

  Future<void> _formulario({Map<String, dynamic>? existente}) async {
    final detalle = widget.catalogo.where((c) => c.esDetalle && c.id != widget.cuenta['cuenta_contable']).toList();
    String tipo = existente?['tipo'] ?? 'deposito';
    int? contrapartida = existente?['contrapartida'] ?? _porCodigo(_contrapartidaSugerida[tipo]!)?.id;
    final descripcion = TextEditingController(text: existente?['descripcion'] ?? '');
    final referencia = TextEditingController(text: existente?['referencia'] ?? '');
    final monto = TextEditingController(text: existente?['monto']?.toString() ?? '');
    final tc = TextEditingController(text: existente != null && _moneda == 'USD' ? existente['tipo_cambio'].toString() : '');
    DateTime fecha = existente != null ? DateTime.parse(existente['fecha']) : DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existente == null ? "Nuevo movimiento" : "Editar movimiento"),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: "Tipo"),
                  items: _tipos.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => set(() {
                    tipo = v ?? 'deposito';
                    // Cambia la sugerencia solo si no eligió otra a mano.
                    contrapartida = _porCodigo(_contrapartidaSugerida[tipo]!)?.id ?? contrapartida;
                  }),
                ),
                TextField(controller: descripcion, decoration: const InputDecoration(labelText: "Descripción *")),
                TextField(controller: referencia, decoration: const InputDecoration(labelText: "Referencia / N.° de comprobante")),
                TextField(
                  controller: monto,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: "Monto ($_moneda) *"),
                ),
                if (_moneda == 'USD')
                  TextField(
                    controller: tc,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Tipo de cambio para el asiento *"),
                  ),
                DropdownButtonFormField<int>(
                  initialValue: detalle.any((c) => c.id == contrapartida) ? contrapartida : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Contrapartida (cuenta contable) *"),
                  items: detalle
                      .map((c) => DropdownMenuItem(value: c.id, child: Text("${c.codigo} · ${c.nombre}", overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => set(() => contrapartida = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Fecha"),
                  subtitle: Text("${fecha.day}/${fecha.month}/${fecha.year}"),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final f = await showDatePicker(context: ctx, initialDate: fecha, firstDate: DateTime(2015), lastDate: DateTime(2100));
                    if (f != null) set(() => fecha = f);
                  },
                ),
                const Text("Se genera el asiento contable automáticamente.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final body = {
      'negocio': widget.negocioId,
      'cuenta': widget.cuenta['id'],
      'tipo': tipo,
      'fecha': fecha.toIso8601String().substring(0, 10),
      'descripcion': descripcion.text.trim(),
      'referencia': referencia.text.trim(),
      'monto': monto.text.trim().replaceAll(',', '.'),
      if (_moneda == 'USD') 'tipo_cambio': tc.text.trim().replaceAll(',', '.'),
      'contrapartida': contrapartida,
    };
    try {
      ApiService.verificar(existente == null
          ? await ApiService.post('/movimientos-bancarios/', body)
          : await ApiService.put('/movimientos-bancarios/${existente['id']}/', body));
      await _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  Future<void> _eliminar(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Eliminar movimiento?"),
        content: Text(m['traslado'].toString().isNotEmpty
            ? "Es parte de un traslado: se eliminan las dos cuentas del traslado y su asiento."
            : "Se elimina también su asiento contable."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Eliminar", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.delete('/movimientos-bancarios/${m['id']}/'));
      await _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cuenta;
    return Scaffold(
      appBar: AppBar(title: Text("${c['banco']} · ${c['nombre']}"), actions: [const BotonCalculadora(), 
        TextButton.icon(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ConciliacionesScreen(negocioId: widget.negocioId, cuenta: c, catalogo: widget.catalogo)),
            );
            _cargar();
          },
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text("Conciliación"),
        ),
        const SizedBox(width: 8),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formulario(),
        icon: const Icon(Icons.add),
        label: const Text("Nuevo movimiento"),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: AppColors.primary.withValues(alpha: 0.06),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Saldo según libros", style: TextStyle(color: Colors.grey)),
                  Text(_monto(_saldo, _moneda), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("Saldo inicial ${_monto(c['saldo_inicial'], _moneda)} al ${c['fecha_saldo_inicial']}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
              Expanded(
                child: _movimientos.isEmpty
                    ? const Center(child: Text("Sin movimientos todavía.", style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                          itemCount: _movimientos.length,
                          itemBuilder: (context, i) {
                            final m = _movimientos[i];
                            final entra = m['es_entrada'] == true;
                            final esTraslado = m['traslado'].toString().isNotEmpty;
                            return Card(
                              child: ListTile(
                                leading: Icon(entra ? Icons.south_west : Icons.north_east, color: entra ? Colors.green : Colors.redAccent),
                                title: Text(m['descripcion'].toString()),
                                subtitle: Text(
                                  "${m['fecha']} · ${m['tipo_nombre']}"
                                  "${(m['referencia'] ?? '').toString().isNotEmpty ? ' · Ref. ${m['referencia']}' : ''}\n"
                                  "${esTraslado ? 'Traslado' : '${m['contrapartida_codigo']} ${m['contrapartida_nombre']}'}"
                                  " · Asiento #${m['asiento_numero'] ?? '-'}"
                                  "${m['registrado_por_contador'] == true ? ' · Contador' : (m['creado_por_nombre'] != null ? ' · ${m['creado_por_nombre']}' : '')}",
                                ),
                                isThreeLine: true,
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text("${entra ? '+' : '-'}${_monto(m['monto'], _moneda)}",
                                      style: TextStyle(fontWeight: FontWeight.bold, color: entra ? Colors.green : Colors.redAccent)),
                                  PopupMenuButton<String>(
                                    onSelected: (v) => v == 'editar' ? _formulario(existente: m) : _eliminar(m),
                                    itemBuilder: (_) => [
                                      if (!esTraslado) const PopupMenuItem(value: 'editar', child: Text("Editar")),
                                      const PopupMenuItem(value: 'eliminar', child: Text("Eliminar")),
                                    ],
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ]),
    );
  }
}

/// Entrada "Bancos" del menú del contador: elige el cliente y abre sus bancos.
Future<void> abrirBancos(BuildContext context) async {
  try {
    final res = ApiService.verificar(await ApiService.get('/negocios/'));
    final negocios = (json.decode(utf8.decode(res.bodyBytes)) as List).map((j) => Negocio.fromJson(j)).toList();
    // Cuentas de cada cliente cuyo mes pasado no está conciliado y cerrado.
    final sinConciliar = <int, int>{};
    try {
      final p = await ApiService.get('/conciliaciones-bancarias/pendientes-contador/');
      if (p.statusCode == 200) {
        for (final f in json.decode(utf8.decode(p.bodyBytes)) as List) {
          if (f['al_dia'] != true) sinConciliar[f['negocio']] = (sinConciliar[f['negocio']] ?? 0) + 1;
        }
      }
    } catch (_) {}
    if (!context.mounted) return;
    if (negocios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todavía no tenés clientes registrados.")));
      return;
    }
    final Negocio? elegido = negocios.length == 1
        ? negocios.first
        : await showDialog<Negocio>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text("¿De qué cliente son los bancos?"),
              children: negocios
                  .map((n) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, n),
                        child: Row(children: [
                          Expanded(child: Text("${n.nombreComercial}  ·  ${n.cedula}")),
                          if (sinConciliar[n.id] != null)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFD97706).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                sinConciliar[n.id] == 1 ? "1 cuenta sin conciliar" : "${sinConciliar[n.id]} cuentas sin conciliar",
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                              ),
                            ),
                        ]),
                      ))
                  .toList(),
            ),
          );
    if (elegido == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BancosScreen(negocioId: elegido.id, negocioNombre: elegido.nombreComercial)));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudieron cargar los clientes: ${ApiService.textoError(e)}")));
  }
}
