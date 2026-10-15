import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'theme/app_theme.dart';

/// Módulos por plan (gestion/modulos.py): el administrador decide qué
/// secciones trae cada plan y, si quiere, las de un negocio puntual. Sin
/// definir = todos. Lo básico (Dashboard, Clientes, Facturas, Ajustes) no es
/// un módulo.

/// Sección del menú del negocio (id de DetalleNegocio._menuItems) -> módulo.
const Map<int, String> moduloPorSeccion = {
  3: 'inventario', 4: 'cotizaciones', 6: 'cobros', 16: 'cobros', 19: 'cobros', 15: 'notas',
  8: 'compras', 13: 'compras', 17: 'compras', 9: 'gastos', 18: 'gastos', 22: 'caja', 20: 'bancos',
  10: 'reportes', 7: 'reportes', 11: 'lealtad', 14: 'colaboradores', 21: 'restaurante', 23: 'prestamos',
  24: 'vehiculos', 12: 'addons',
};

// Por si el backend no responde: los mismos de gestion/modulos.py.
const List<(String, String)> _catalogoRespaldo = [
  ('inventario', 'Inventario'),
  ('cotizaciones', 'Cotizaciones'),
  ('cobros', 'Cuentas por cobrar, recibos y pagos en línea'),
  ('notas', 'Notas de crédito y débito'),
  ('compras', 'Compras, cuentas por pagar y correos de compra'),
  ('gastos', 'Gastos e ingresos'),
  ('caja', 'Caja (aperturas y cierres)'),
  ('bancos', 'Bancos y conciliación'),
  ('reportes', 'Reportes e impuestos'),
  ('lealtad', 'Tarjeta de lealtad'),
  ('colaboradores', 'Colaboradores (usuarios, comisiones, asistencia)'),
  ('restaurante', 'Restaurante (mesas, comandas, cocina)'),
  ('prestamos', 'Préstamos'),
  ('vehiculos', 'Inventario de vehículos'),
  ('addons', 'Add-ons'),
];

Future<List<(String, String)>> cargarCatalogoModulos() async {
  try {
    final r = await ApiService.get('/modulos/');
    if (r.statusCode != 200) return _catalogoRespaldo;
    return [
      for (final m in json.decode(utf8.decode(r.bodyBytes))['modulos'] as List) (m['clave'].toString(), m['nombre'].toString()),
    ];
  } catch (_) {
    return _catalogoRespaldo;
  }
}

/// Casillas de módulos. [elegidos] null = "Todos los módulos" marcado.
class SelectorModulos extends StatelessWidget {
  final List<(String, String)> catalogo;
  final Set<String>? elegidos;
  final ValueChanged<Set<String>?> onCambio;
  final String textoTodos;

  const SelectorModulos({
    super.key,
    required this.catalogo,
    required this.elegidos,
    required this.onCambio,
    this.textoTodos = "Todos los módulos",
  });

  @override
  Widget build(BuildContext context) {
    final todos = elegidos == null;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        SwitchListTile(
          dense: true,
          value: todos,
          title: Text(textoTodos, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: todos ? const Text("Incluye lo que se agregue más adelante.", style: TextStyle(fontSize: 12)) : null,
          onChanged: (v) => onCambio(v ? null : {for (final m in catalogo) m.$1}),
        ),
        if (!todos) ...[
          const Divider(height: 1),
          for (final (clave, nombre) in catalogo)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: elegidos!.contains(clave),
              title: Text(nombre, style: const TextStyle(fontSize: 13.5)),
              onChanged: (v) => onCambio(v == true ? ({...elegidos!, clave}) : ({...elegidos!}..remove(clave))),
            ),
        ],
      ]),
    );
  }
}

/// El administrador fija los módulos de un negocio puntual (mandan sobre
/// los del plan) o lo deja con los de su plan.
Future<void> abrirModulosNegocio(BuildContext context, {required int negocioId, required String nombre}) async {
  await showDialog(context: context, builder: (_) => _DialogoModulosNegocio(negocioId: negocioId, nombre: nombre));
}

class _DialogoModulosNegocio extends StatefulWidget {
  final int negocioId;
  final String nombre;
  const _DialogoModulosNegocio({required this.negocioId, required this.nombre});

  @override
  State<_DialogoModulosNegocio> createState() => _DialogoModulosNegocioState();
}

class _DialogoModulosNegocioState extends State<_DialogoModulosNegocio> {
  Map<String, dynamic>? _datos;
  bool _propios = false;
  Set<String>? _elegidos;
  bool _guardando = false;
  String? _error;

  List<(String, String)> get _catalogo => [
    for (final m in (_datos?['catalogo'] as List? ?? [])) (m['clave'].toString(), m['nombre'].toString()),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aplicar(Map<String, dynamic> d) {
    _datos = d;
    final propios = d['modulos_propios'] as List?;
    _propios = propios != null;
    _elegidos = propios == null ? null : {for (final m in propios) m.toString()};
  }

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get('/modulos/negocio/${widget.negocioId}/'));
      if (mounted) setState(() => _aplicar(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final modulos = !_propios ? null : (_elegidos == null ? [for (final m in _catalogo) m.$1] : _elegidos!.toList());
      final r = ApiService.verificar(await ApiService.post('/modulos/negocio/${widget.negocioId}/', {'modulos': modulos}));
      if (!mounted) return;
      setState(() => _aplicar(json.decode(utf8.decode(r.bodyBytes))));
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Módulos de ${widget.nombre} guardados")));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String _resumenPlan() {
    final plan = _datos?['plan'];
    final delPlan = _datos?['modulos_plan'] as List?;
    if (plan == null) return "No tiene plan: tiene todos los módulos.";
    if (delPlan == null) return "Su plan $plan trae todos los módulos.";
    final nombres = {for (final m in _catalogo) m.$1: m.$2};
    return "Su plan $plan trae: ${delPlan.isEmpty ? 'ninguno (solo lo básico)' : delPlan.map((m) => nombres[m] ?? m).join(', ')}.";
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return AlertDialog(
      title: Text("Módulos de ${widget.nombre}"),
      content: SizedBox(
        width: 460,
        child: d == null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Dashboard, Clientes, Facturas y Ajustes los tienen todos. Lo que se apaga se oculta y no deja crear "
                      "registros nuevos; lo que ya tenía no se borra.",
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    RadioGroup<bool>(
                      groupValue: _propios,
                      onChanged: (v) => setState(() {
                        _propios = v ?? false;
                        if (_propios && _elegidos == null) {
                          final delPlan = d['modulos_plan'] as List?;
                          _elegidos = delPlan == null ? null : {for (final m in delPlan) m.toString()};
                        }
                      }),
                      child: Column(children: [
                        RadioListTile<bool>(
                          value: false,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Usar los de su plan"),
                          subtitle: Text(_resumenPlan(), style: const TextStyle(fontSize: 12)),
                        ),
                        RadioListTile<bool>(
                          value: true,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Elegir para este negocio"),
                          subtitle: const Text("Manda sobre el plan, por ejemplo para darle algo de cortesía.", style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                    ),
                    if (_propios) ...[
                      const SizedBox(height: 8),
                      SelectorModulos(
                        catalogo: _catalogo,
                        elegidos: _elegidos,
                        onCambio: (v) => setState(() => _elegidos = v),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
        if (d != null)
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Guardar"),
          ),
      ],
    );
  }
}
