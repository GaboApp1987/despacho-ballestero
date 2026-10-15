import 'planilla_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';

/// Colaboradores del negocio -- exclusivo del dueño real (ver
/// SoloDuenoDelNegocioMixin y gestion/colaboradores.py en el backend):
/// ventas y comisión de cada uno en el período, su ficha (ventas por día,
/// facturas, turnos de caja, actividad), permisos por sección, contraseña
/// nueva y activar/desactivar.
class Empleado {
  final int id;
  final String nombre;
  final String rol; // 'cajero' | 'completo' | 'medida'
  final bool activo;
  final List<String> permisos;
  final double comision;
  final String telefono;
  final String usuario;
  final String? horaEntrada; // 'HH:MM' o null
  // Planilla (planilla_screen.dart).
  final double salario;
  final String cedula;
  final int hijos;
  final bool conyuge;
  final String jornada;
  final int diasVacaciones;
  final DateTime? fechaIngreso;

  Empleado({
    required this.id,
    required this.nombre,
    required this.rol,
    required this.activo,
    this.permisos = const [],
    this.comision = 0,
    this.telefono = '',
    this.usuario = '',
    this.horaEntrada,
    this.salario = 0,
    this.cedula = '',
    this.hijos = 0,
    this.conyuge = false,
    this.jornada = 'completa',
    this.diasVacaciones = 12,
    this.fechaIngreso,
  });

  factory Empleado.fromJson(Map<String, dynamic> json) {
    return Empleado(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      rol: json['rol'] ?? 'cajero',
      activo: json['activo'] == true,
      permisos: [for (final p in (json['permisos'] as List? ?? [])) p.toString()],
      comision: double.tryParse(json['comision']?.toString() ?? '') ?? 0,
      telefono: json['telefono'] ?? '',
      usuario: json['usuario_login'] ?? '',
      horaEntrada: (json['hora_entrada'] as String?)?.substring(0, 5),
      salario: double.tryParse(json['salario']?.toString() ?? '') ?? 0,
      cedula: json['cedula'] ?? '',
      hijos: json['hijos'] ?? 0,
      conyuge: json['conyuge'] == true,
      jornada: json['jornada'] ?? 'completa',
      diasVacaciones: json['dias_vacaciones'] ?? 12,
      fechaIngreso: json['fecha_ingreso'] == null ? null : DateTime.tryParse(json['fecha_ingreso']),
    );
  }
}

const Map<String, String> nombresRol = {
  'cajero': 'Cajero',
  'completo': 'Acceso completo',
  'medida': 'A la medida',
  'dueno': 'Dueño',
  'sin_dato': 'Sin dato',
};

const Map<String, String> _descripcionRol = {
  'cajero': 'Solo factura, cotiza y crea clientes. No ve montos de caja ni reportes.',
  'completo': 'Puede todo, menos administrar colaboradores.',
  'medida': 'Vos elegís qué secciones puede usar.',
};

// Si el backend no los manda (no debería pasar), los de siempre.
const List<(String, String)> _permisosRespaldo = [
  ('facturar', 'Facturar, cotizar y crear clientes'),
  ('clientes', 'Editar y borrar clientes'),
  ('cobros', 'Cuentas por cobrar y abonos'),
  ('notas', 'Notas de crédito y débito, editar o borrar facturas'),
  ('inventario', 'Productos, categorías y recetas'),
  ('compras', 'Compras, proveedores y cuentas por pagar'),
  ('gastos', 'Gastos e ingresos'),
  ('caja', 'Ver los montos de la caja y todos los cierres'),
  ('bancos', 'Bancos y conciliación'),
  ('reportes', 'Reportes, impuestos y propinas'),
  ('prestamos', 'Préstamos'),
  ('vehiculos', 'Vehículos'),
  ('restaurante', 'Mesas, plano y anular cuentas del restaurante'),
  ('ajustes', 'Ajustes del negocio, lealtad y add-ons'),
];

String _fecha(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// (desde, hasta, etiqueta) de los períodos que se pueden elegir.
List<(DateTime, DateTime, String)> _periodos() {
  final hoy = DateTime.now();
  final inicioMes = DateTime(hoy.year, hoy.month, 1);
  final mesPasado = DateTime(hoy.year, hoy.month - 1, 1);
  return [
    (DateTime(hoy.year, hoy.month, hoy.day), hoy, 'Hoy'),
    (hoy.subtract(Duration(days: hoy.weekday - 1)), hoy, 'Esta semana'),
    (inicioMes, hoy, 'Este mes'),
    (mesPasado, inicioMes.subtract(const Duration(days: 1)), 'Mes pasado'),
  ];
}

String _iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  return (partes.first[0] + (partes.length > 1 ? partes[1][0] : '')).toUpperCase();
}

// Último uso de la app (no confundir con la entrada de asistencia).
String _haceCuanto(String? iso) {
  if (iso == null) return 'Nunca ha usado la app';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final dif = DateTime.now().difference(d);
  if (dif.inMinutes < 60) return 'Usó la app hace ${dif.inMinutes < 1 ? 1 : dif.inMinutes} min';
  if (dif.inHours < 24) return 'Usó la app hace ${dif.inHours} h';
  if (dif.inDays < 30) return 'Usó la app hace ${dif.inDays} ${dif.inDays == 1 ? 'día' : 'días'}';
  return 'Usó la app el ${d.day}/${d.month}/${d.year}';
}

/// 7.58 -> "7 h 35 min".
String _horasTexto(num horas) {
  final minutos = (horas * 60).round();
  final h = minutos ~/ 60, m = minutos % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String _dosDigitos(int n) => n.toString().padLeft(2, '0');
String _horaDe(DateTime d) => '${_dosDigitos(d.hour)}:${_dosDigitos(d.minute)}';
const _diasSemana = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

class EmpleadosScreen extends StatefulWidget {
  final Negocio negocio;
  const EmpleadosScreen({super.key, required this.negocio});

  @override
  State<EmpleadosScreen> createState() => _EmpleadosScreenState();
}

class _EmpleadosScreenState extends State<EmpleadosScreen> {
  bool _cargando = true;
  String? _error;
  List<Empleado> _empleados = [];
  Map<String, dynamic>? _resumen;
  int _periodo = 2;
  bool _verPlanilla = false;

  List<(String, String)> get _permisos {
    final lista = _resumen?['permisos_disponibles'] as List?;
    if (lista == null || lista.isEmpty) return _permisosRespaldo;
    return [for (final p in lista) (p['clave'].toString(), p['nombre'].toString())];
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final (desde, hasta, _) = _periodos()[_periodo];
    try {
      final respuestas = await Future.wait([
        ApiService.get('/empleados/?negocio=${widget.negocio.id}'),
        ApiService.get('/colaboradores/?negocio=${widget.negocio.id}&desde=${_fecha(desde)}&hasta=${_fecha(hasta)}'),
      ]);
      for (final r in respuestas) {
        ApiService.verificar(r);
      }
      if (!mounted) return;
      setState(() {
        _empleados = [for (final j in json.decode(utf8.decode(respuestas[0].bodyBytes)) as List) Empleado.fromJson(j)];
        _resumen = Map<String, dynamic>.from(json.decode(utf8.decode(respuestas[1].bodyBytes)));
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiService.textoError(e);
          _cargando = false;
        });
      }
    }
  }

  Empleado? _empleado(int? id) => id == null ? null : _empleados.where((e) => e.id == id).firstOrNull;

  Future<void> _formulario({Empleado? empleado}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _FormularioColaborador(negocio: widget.negocio, empleado: empleado, permisos: _permisos),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _alternarActivo(Empleado e) async {
    try {
      ApiService.verificar(await ApiService.patch('/empleados/${e.id}/', {'activo': !e.activo}));
      _cargar();
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(err)), backgroundColor: Colors.red));
    }
  }

  void _abrirFicha(Map<String, dynamic> fila) async {
    final (desde, hasta, etiqueta) = _periodos()[_periodo];
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FichaColaborador(
          negocio: widget.negocio,
          fila: fila,
          empleado: _empleado(fila['empleado_id'] as int?),
          desde: desde,
          hasta: hasta,
          etiquetaPeriodo: etiqueta,
          permisos: _permisos,
        ),
      ),
    );
    if (cambio == true) _cargar();
  }

  Widget _tarjetaTotal(String titulo, String valor, IconData icono, {String? nota}) => Container(
    width: 220,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icono, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(valor, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (nota != null) Text(nota, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _dato(String titulo, String valor, {Color? color}) => Padding(
    padding: const EdgeInsets.only(right: 18, top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        Text(
          valor,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    ),
  );

  Widget _tarjetaPersona(Map<String, dynamic> f) {
    final e = _empleado(f['empleado_id'] as int?);
    final rol = f['rol'] as String;
    final activo = f['activo'] == true;
    final diferencia = (f['diferencia_efectivo'] as num?) ?? 0;
    final asistencia = f['asistencia'] as Map<String, dynamic>?;
    final trabajando = asistencia?['trabajando'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: rol == 'sin_dato' ? null : () => _abrirFicha(f),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: (activo ? AppColors.primary : Colors.grey).withValues(alpha: 0.15),
                    child: rol == 'sin_dato'
                        ? Icon(Icons.history, color: AppColors.textMuted, size: 20)
                        : Text(
                            _iniciales(f['nombre']),
                            style: TextStyle(color: activo ? AppColors.primary : Colors.grey, fontWeight: FontWeight.w700),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(
                              f['nombre'],
                              style: TextStyle(fontWeight: FontWeight.w700, color: activo ? null : AppColors.textMuted),
                            ),
                          ),
                          if (trabajando)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                              child: Text('Trabajando', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
                            ),
                        ]),
                        Text(
                          [nombresRol[rol] ?? rol, if (!activo) 'Inactivo', if (e != null) _haceCuanto(f['ultimo_acceso'])].join(' · '),
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (e != null) Switch(value: e.activo, onChanged: (_) => _alternarActivo(e), activeThumbColor: AppColors.primary),
                  if (rol != 'sin_dato') Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Wrap(
                  children: [
                    _dato('Ventas', '${f['ventas']}'),
                    _dato('Vendido', formatearColones(f['total'] as num, decimales: 0)),
                    if ((f['ventas'] as int) > 0) _dato('Ticket promedio', formatearColones(f['ticket_promedio'] as num, decimales: 0)),
                    if ((f['comision_pct'] as num) > 0)
                      _dato(
                        'Comisión ${formatearNumero(f['comision_pct'] as num, decimales: (f['comision_pct'] as num) % 1 == 0 ? 0 : 1)}%',
                        formatearColones(f['comision'] as num),
                      ),
                    if ((f['turnos'] as int) > 0)
                      _dato(
                        'Caja (${f['turnos']} ${f['turnos'] == 1 ? 'cierre' : 'cierres'})',
                        diferencia == 0 ? 'Cuadrada' : '${diferencia > 0 ? 'Sobró' : 'Faltó'} ${formatearColones(diferencia.abs())}',
                        color: diferencia < 0 ? Colors.red.shade700 : (diferencia > 0 ? Colors.orange.shade800 : Colors.green.shade700),
                      ),
                    if (asistencia != null && (asistencia['dias'] as int) > 0) ...[
                      _dato('Horas (${asistencia['dias']} ${asistencia['dias'] == 1 ? 'día' : 'días'})', _horasTexto(asistencia['horas'] as num)),
                      if ((asistencia['tardias'] as int) > 0)
                        _dato('Llegadas tarde', '${asistencia['tardias']} · ${_horasTexto((asistencia['minutos_tarde'] as num) / 60)}',
                            color: Colors.orange.shade800),
                      if ((asistencia['sin_salida'] as int) > 0)
                        _dato('Sin marcar salida', '${asistencia['sin_salida']}', color: Colors.red.shade700),
                    ],
                  ],
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
    final filas = [for (final f in (_resumen?['colaboradores'] as List? ?? [])) Map<String, dynamic>.from(f as Map)];
    final activos = _empleados.where((e) => e.activo).length;
    final angosto = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: angosto && !_verPlanilla
          ? FloatingActionButton.extended(
              onPressed: () => _formulario(),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Nuevo'),
            )
          : null,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.badge_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Colaboradores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (!_verPlanilla)
                DropdownButton<int>(
                  value: _periodo,
                  underline: const SizedBox(),
                  items: [for (final (i, p) in _periodos().indexed) DropdownMenuItem(value: i, child: Text(p.$3))],
                  onChanged: (v) {
                    setState(() => _periodo = v ?? 2);
                    _cargar();
                  },
                ),
                if (!angosto && !_verPlanilla) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _formulario(),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Nuevo colaborador'),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.groups_outlined), label: Text('Equipo')),
                  ButtonSegment(value: true, icon: Icon(Icons.payments_outlined), label: Text('Planilla')),
                ],
                selected: {_verPlanilla},
                onSelectionChanged: (v) {
                  setState(() => _verPlanilla = v.first);
                  if (!_verPlanilla) _cargar();
                },
              ),
            ),
          ),
          if (_verPlanilla) Expanded(child: PlanillaTab(negocio: widget.negocio)) else
          Expanded(
            child: _cargando && _resumen == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _resumen == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      children: [
                        if (_cargando) const LinearProgressIndicator(minHeight: 2),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _tarjetaTotal(
                              'Vendido por el equipo',
                              formatearColones(_resumen?['total_ventas'] ?? 0, decimales: 0),
                              Icons.point_of_sale_outlined,
                            ),
                            _tarjetaTotal(
                              'Comisiones a pagar',
                              formatearColones(_resumen?['total_comisiones'] ?? 0),
                              Icons.payments_outlined,
                              nota: 'Sobre lo vendido sin IVA',
                            ),
                            _tarjetaTotal(
                              'Horas trabajadas',
                              _horasTexto((_resumen?['total_horas'] as num?) ?? 0),
                              Icons.schedule_outlined,
                              nota: ((_resumen?['trabajando_ahora'] as num?) ?? 0) > 0
                                  ? '${_resumen!['trabajando_ahora']} trabajando ahora'
                                  : 'Según las marcas de entrada y salida',
                            ),
                            _tarjetaTotal(
                              'Colaboradores activos',
                              '$activos',
                              Icons.groups_outlined,
                              nota: _empleados.length > activos ? '${_empleados.length - activos} inactivos' : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (_empleados.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(18),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                            child: const Text(
                              'Todavía no tenés colaboradores. Creales un usuario para que facturen desde su celular o la caja: '
                              'cada factura queda a su nombre, ves cuánto vendió cada uno y calculás su comisión.',
                            ),
                          ),
                        ...filas.map(_tarjetaPersona),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Crear o editar un colaborador: datos, rol (con casillas si es 'A la
/// medida') y comisión. El usuario y la contraseña solo se piden al crear.
class _FormularioColaborador extends StatefulWidget {
  final Negocio negocio;
  final Empleado? empleado;
  final List<(String, String)> permisos;
  const _FormularioColaborador({required this.negocio, this.empleado, required this.permisos});

  @override
  State<_FormularioColaborador> createState() => _FormularioColaboradorState();
}

class _FormularioColaboradorState extends State<_FormularioColaborador> {
  late final _nombre = TextEditingController(text: widget.empleado?.nombre ?? '');
  late final _telefono = TextEditingController(text: widget.empleado?.telefono ?? '');
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  late final _salario = TextEditingController(
    text: (widget.empleado?.salario ?? 0) == 0 ? '' : formatearNumero(widget.empleado!.salario, decimales: 0),
  );
  late final _cedula = TextEditingController(text: widget.empleado?.cedula ?? '');
  late int _hijos = widget.empleado?.hijos ?? 0;
  late bool _conyuge = widget.empleado?.conyuge ?? false;
  late String _jornada = widget.empleado?.jornada ?? 'completa';
  late int _diasVacaciones = widget.empleado?.diasVacaciones ?? 12;
  late DateTime? _fechaIngreso = widget.empleado?.fechaIngreso;
  late final _comision = TextEditingController(
    text: (widget.empleado?.comision ?? 0) == 0
        ? ''
        : formatearNumero(widget.empleado!.comision, decimales: widget.empleado!.comision % 1 == 0 ? 0 : 2),
  );
  late String _rol = widget.empleado?.rol ?? 'cajero';
  late TimeOfDay? _horaEntrada = widget.empleado?.horaEntrada == null
      ? null
      : TimeOfDay(
          hour: int.parse(widget.empleado!.horaEntrada!.substring(0, 2)),
          minute: int.parse(widget.empleado!.horaEntrada!.substring(3, 5)),
        );
  late final Set<String> _elegidos = {
    ...(widget.empleado?.permisos ?? const ['facturar']),
  };
  bool _guardando = false;
  bool _verClave = false;

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _usuario, _clave, _comision, _salario, _cedula]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final nuevo = widget.empleado == null;
    if (_nombre.text.trim().isEmpty || (nuevo && (_usuario.text.trim().isEmpty || _clave.text.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completá nombre, usuario y contraseña.')));
      return;
    }
    if (_rol == 'medida' && _elegidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elegí al menos una sección.')));
      return;
    }
    final comision = double.tryParse(_comision.text.trim().replaceAll(',', '.').replaceAll('%', '')) ?? 0;
    final datos = {
      'negocio': widget.negocio.id,
      'nombre': _nombre.text.trim(),
      'telefono': _telefono.text.trim(),
      'rol': _rol,
      'permisos': _rol == 'medida'
          ? [
              for (final (k, _) in widget.permisos)
                if (_elegidos.contains(k)) k,
            ]
          : <String>[],
      'comision': comision.toStringAsFixed(2),
      'salario': (double.tryParse(_salario.text.trim().replaceAll('.', '').replaceAll(',', '.').replaceAll('₡', '')) ?? 0)
          .toStringAsFixed(2),
      'cedula': _cedula.text.trim(),
      'hijos': _hijos,
      'conyuge': _conyuge,
      'jornada': _jornada,
      'dias_vacaciones': _diasVacaciones,
      'fecha_ingreso': _fechaIngreso == null ? null : _fecha(_fechaIngreso!),
      'hora_entrada': _horaEntrada == null ? null : '${_dosDigitos(_horaEntrada!.hour)}:${_dosDigitos(_horaEntrada!.minute)}',
      if (nuevo) ...{'username': _usuario.text.trim(), 'password': _clave.text},
    };
    setState(() => _guardando = true);
    try {
      ApiService.verificar(nuevo ? await ApiService.post('/empleados/', datos) : await ApiService.patch('/empleados/${widget.empleado!.id}/', datos));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
      }
    }
  }

  InputDecoration _deco(String etiqueta, {String? ayuda, Widget? sufijo}) =>
      InputDecoration(labelText: etiqueta, helperText: ayuda, isDense: true, border: const OutlineInputBorder(), suffixIcon: sufijo);

  @override
  Widget build(BuildContext context) {
    final nuevo = widget.empleado == null;
    return AlertDialog(
      title: Text(nuevo ? 'Nuevo colaborador' : 'Editar a ${widget.empleado!.nombre}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _nombre, decoration: _deco('Nombre completo')),
              const SizedBox(height: 12),
              TextField(controller: _telefono, keyboardType: TextInputType.phone, decoration: _deco('Teléfono (opcional)')),
              if (nuevo) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _usuario,
                  decoration: _deco('Usuario para entrar', ayuda: 'Ej. ana.tienda (sin espacios)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clave,
                  obscureText: !_verClave,
                  decoration: _deco(
                    'Contraseña',
                    sufijo: IconButton(
                      icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _verClave = !_verClave),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Qué puede hacer', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              RadioGroup<String>(
                groupValue: _rol,
                onChanged: (v) => setState(() => _rol = v!),
                child: Column(children: [
                  for (final rol in ['cajero', 'completo', 'medida'])
                    RadioListTile<String>(
                      value: rol,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(nombresRol[rol]!),
                      subtitle: Text(_descripcionRol[rol]!, style: const TextStyle(fontSize: 12)),
                    ),
                ]),
              ),
              if (_rol == 'medida')
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      for (final (clave, nombre) in widget.permisos)
                        CheckboxListTile(
                          value: _elegidos.contains(clave),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(nombre, style: const TextStyle(fontSize: 13.5)),
                          onChanged: (v) => setState(() => v == true ? _elegidos.add(clave) : _elegidos.remove(clave)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _comision,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _deco('Comisión sobre sus ventas (%)', ayuda: 'Opcional. Se calcula sobre lo vendido sin IVA, menos notas de crédito.'),
              ),
              const SizedBox(height: 18),
              const Text('Planilla', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _salario,
                    keyboardType: TextInputType.number,
                    decoration: _deco('Salario mensual bruto (₡)', ayuda: 'Vacío = no va en la planilla'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _cedula, decoration: _deco('Cédula'))),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Expanded(child: Text('Hijos (crédito del impuesto)', style: TextStyle(fontSize: 13.5))),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _hijos == 0 ? null : () => setState(() => _hijos--),
                ),
                Text('$_hijos', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _hijos++)),
              ]),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _conyuge,
                onChanged: (v) => setState(() => _conyuge = v),
                title: const Text('Cónyuge (crédito del impuesto)', style: TextStyle(fontSize: 13.5)),
              ),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'completa', label: Text('Jornada completa')),
                  ButtonSegment(value: 'parcial', label: Text('Jornada parcial')),
                ],
                selected: {_jornada},
                onSelectionChanged: (v) => setState(() => _jornada = v.first),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  _jornada == 'completa'
                      ? 'La CCSS se cobra como mínimo sobre la base mínima contributiva.'
                      : 'Parcial: la CCSS se calcula sobre lo que gana. Coordiná con la CCSS la base reducida.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _fechaIngreso ?? DateTime.now(),
                        firstDate: DateTime(1980),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _fechaIngreso = d);
                    },
                    child: InputDecorator(
                      decoration: _deco('Fecha de ingreso', ayuda: 'Para vacaciones'),
                      child: Text(_fechaIngreso == null
                          ? 'Sin fecha'
                          : '${_fechaIngreso!.day}/${_fechaIngreso!.month}/${_fechaIngreso!.year}'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    initialValue: '$_diasVacaciones',
                    keyboardType: TextInputType.number,
                    decoration: _deco('Vacaciones/año', ayuda: 'Días'),
                    onChanged: (t) => _diasVacaciones = int.tryParse(t.trim()) ?? _diasVacaciones,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: _deco(
                  'Hora de entrada',
                  ayuda: 'Opcional. Si marca la entrada más de 10 min después, cuenta como llegada tarde.',
                  sufijo: _horaEntrada == null
                      ? null
                      : IconButton(
                          tooltip: 'Sin hora fija',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _horaEntrada = null),
                        ),
                ),
                child: InkWell(
                  onTap: () async {
                    final hora = await showTimePicker(
                      context: context,
                      initialTime: _horaEntrada ?? const TimeOfDay(hour: 8, minute: 0),
                    );
                    if (hora != null) setState(() => _horaEntrada = hora);
                  },
                  child: Row(children: [
                    Icon(Icons.schedule_outlined, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Text(_horaEntrada == null ? 'Sin hora fija' : _horaEntrada!.format(context)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(nuevo ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

/// Ficha de una persona: cifras del período, ventas por día, sus facturas,
/// sus cierres de caja y su actividad; y para un colaborador, editar,
/// contraseña nueva y eliminar.
class FichaColaborador extends StatefulWidget {
  final Negocio negocio;
  final Map<String, dynamic> fila;
  final Empleado? empleado;
  final DateTime desde;
  final DateTime hasta;
  final String etiquetaPeriodo;
  final List<(String, String)> permisos;

  const FichaColaborador({
    super.key,
    required this.negocio,
    required this.fila,
    required this.empleado,
    required this.desde,
    required this.hasta,
    required this.etiquetaPeriodo,
    required this.permisos,
  });

  @override
  State<FichaColaborador> createState() => _FichaColaboradorState();
}

class _FichaColaboradorState extends State<FichaColaborador> {
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(
        await ApiService.get(
          '/colaboradores/${widget.fila['usuario_id']}/?negocio=${widget.negocio.id}&desde=${_fecha(widget.desde)}&hasta=${_fecha(widget.hasta)}',
        ),
      );
      if (mounted) setState(() => _datos = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  Future<void> _editar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _FormularioColaborador(negocio: widget.negocio, empleado: widget.empleado, permisos: widget.permisos),
    );
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _claveNueva() async {
    final ctrl = TextEditingController();
    final clave = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Contraseña nueva para ${widget.empleado!.nombre}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Usuario: ${widget.empleado!.usuario}', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Contraseña nueva', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              const Text('Dásela en persona o por WhatsApp. La anterior deja de servir.', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Cambiar')),
        ],
      ),
    );
    ctrl.dispose();
    if (clave == null || clave.isEmpty || !mounted) return;
    try {
      ApiService.verificar(await ApiService.post('/empleados/${widget.empleado!.id}/clave/', {'password': clave}));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña cambiada.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
    }
  }

  Future<void> _eliminar() async {
    final e = widget.empleado!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar colaborador'),
        content: Text(
          '¿Eliminar a "${e.nombre}"? Se borra su usuario. Sus facturas se conservan.\n\n'
          'Si solo querés quitarle el acceso, mejor desactivalo: así queda el historial a su nombre.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.delete('/empleados/${e.id}/'));
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(err)), backgroundColor: Colors.red));
    }
  }

  Future<void> _editarMarca({Map<String, dynamic>? marca}) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoMarca(marca: marca, nombre: widget.fila['nombre']),
    );
    if (resultado == null || !mounted) return;
    try {
      if (resultado['borrar'] == true) {
        ApiService.verificar(await ApiService.delete('/asistencia/marcas/${marca!['id']}/'));
      } else if (marca == null) {
        ApiService.verificar(await ApiService.post('/asistencia/marcas/', {
          'negocio': widget.negocio.id,
          'usuario': widget.fila['usuario_id'],
          ...resultado,
        }));
      } else {
        ApiService.verificar(await ApiService.patch('/asistencia/marcas/${marca['id']}/', resultado));
      }
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
    }
  }

  Widget _filaMarca(Map<String, dynamic> m) {
    final entrada = DateTime.parse(m['entrada']).toLocal();
    final salida = m['salida'] == null ? null : DateTime.parse(m['salida']).toLocal();
    final tarde = (m['minutos_tarde'] as num?) ?? 0;
    final estado = m['abierta'] == true
        ? Text('Trabajando', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600))
        : m['sin_salida'] == true
            ? Text('No marcó salida', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600))
            : Text(_horasTexto(m['horas'] as num), style: const TextStyle(fontWeight: FontWeight.w600));
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => _editarMarca(marca: m),
      title: Text('${_diasSemana[entrada.weekday - 1]} ${entrada.day}/${entrada.month} · '
          '${_horaDe(entrada)} – ${salida == null ? '…' : _horaDe(salida)}'),
      subtitle: Text(
        [
          if (tarde > 0) '$tarde min tarde',
          if (m['corregida'] == true) 'Corregida',
          if ((m['nota'] ?? '').toString().isNotEmpty) m['nota'],
        ].join(' · '),
        style: TextStyle(color: tarde > 0 ? Colors.orange.shade800 : AppColors.textMuted, fontSize: 12),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        estado,
        const SizedBox(width: 4),
        Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted),
      ]),
    );
  }

  Widget _seccion(String titulo, List<Widget> hijos, {String? vacio}) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        if (hijos.isEmpty && vacio != null) Text(vacio, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ...hijos,
      ],
    ),
  );

  Widget _cifra(String titulo, String valor) => SizedBox(
    width: 150,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );

  Widget _barras(List dias) {
    if (dias.isEmpty) return const SizedBox();
    final maximo = dias.map((d) => (d['total'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in dias.length > 31 ? dias.sublist(dias.length - 31) : dias)
            Expanded(
              child: Tooltip(
                message: '${d['fecha']}: ${d['ventas']} ventas, ${formatearColones(d['total'] as num, decimales: 0)}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: maximo == 0 ? 2 : 2 + 84 * (d['total'] as num) / maximo,
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(height: 4),
                    Text('${DateTime.parse(d['fecha']).day}', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _hora(String iso) {
    final d = DateTime.parse(iso).toLocal();
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.empleado;
    final d = _datos;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.fila['nombre']),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          if (e != null) ...[
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: _editar),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'clave' ? _claveNueva() : _eliminar(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'clave',
                  child: ListTile(leading: Icon(Icons.key_outlined), title: Text('Contraseña nueva')),
                ),
                PopupMenuItem(
                  value: 'eliminar',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Eliminar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: d == null
          ? Center(
              child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator(),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (e != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Chip(label: Text(nombresRol[e.rol] ?? e.rol), avatar: const Icon(Icons.shield_outlined, size: 16)),
                            Chip(label: Text('Usuario: ${e.usuario}'), avatar: const Icon(Icons.person_outline, size: 16)),
                            if (e.telefono.isNotEmpty) Chip(label: Text(e.telefono), avatar: const Icon(Icons.phone_outlined, size: 16)),
                            if (!e.activo) const Chip(label: Text('Inactivo'), avatar: Icon(Icons.block, size: 16)),
                          ],
                        ),
                      ),
                    if (e != null && e.rol == 'medida')
                      _seccion('Puede usar', [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final (clave, nombre) in widget.permisos)
                              if (e.permisos.contains(clave))
                                Chip(
                                  label: Text(nombre, style: const TextStyle(fontSize: 12)),
                                  visualDensity: VisualDensity.compact,
                                ),
                          ],
                        ),
                      ]),
                    _seccion(widget.etiquetaPeriodo, [
                      Wrap(
                        children: [
                          _cifra('Ventas', '${d['ventas']}'),
                          _cifra('Vendido', formatearColones(d['total'] as num, decimales: 0)),
                          _cifra('Ticket promedio', formatearColones(d['ticket_promedio'] as num, decimales: 0)),
                          _cifra('Sin IVA, menos notas', formatearColones(d['neto'] as num, decimales: 0)),
                          if ((d['comision_pct'] as num) > 0)
                            _cifra('Comisión (${formatearNumero(d['comision_pct'] as num, decimales: 1)}%)', formatearColones(d['comision'] as num)),
                        ],
                      ),
                      _barras(d['por_dia'] as List),
                    ]),
                    _seccion('Asistencia', [
                      Wrap(
                        children: [
                          _cifra('Horas trabajadas', _horasTexto((d['resumen_asistencia']?['horas'] as num?) ?? 0)),
                          _cifra('Días', '${d['resumen_asistencia']?['dias'] ?? 0}'),
                          _cifra(
                            'Llegadas tarde',
                            d['hora_entrada'] == null
                                ? 'Sin hora fija'
                                : '${d['resumen_asistencia']?['tardias'] ?? 0} (entra ${d['hora_entrada']})',
                          ),
                        ],
                      ),
                      for (final m in d['asistencia'] as List) _filaMarca(Map<String, dynamic>.from(m)),
                      if ((d['asistencia'] as List).isEmpty)
                        Text(
                          e == null
                              ? 'No hay marcas en este período.'
                              : 'No hay marcas en este período. ${e.nombre} marca su entrada y salida con el botón '
                                  '"Marcar entrada" de arriba en la app.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _editarMarca(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar marca'),
                        ),
                      ),
                    ]),
                    _seccion('Sus facturas', [
                      for (final f in d['facturas'] as List)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(f['cliente']),
                          subtitle: Text('${f['tipo'] == '04' ? 'Tiquete' : 'Factura'} ${f['consecutivo'] ?? ''} · ${_hora(f['fecha'])}'),
                          trailing: Text(formatearColones(f['total'] as num), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                    ], vacio: 'No emitió facturas en este período.'),
                    _seccion('Sus cierres de caja', [
                      for (final t in d['turnos'] as List)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Cierre ${_hora(t['cerrado_en'])}'),
                          subtitle: Text('Ventas ${formatearColones(t['total_ventas'] as num, decimales: 0)}'),
                          trailing: Text(
                            (t['diferencia_efectivo'] as num) == 0
                                ? 'Cuadrada'
                                : '${(t['diferencia_efectivo'] as num) > 0 ? 'Sobró' : 'Faltó'} ${formatearColones((t['diferencia_efectivo'] as num).abs())}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: (t['diferencia_efectivo'] as num) < 0 ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                        ),
                    ], vacio: 'No cerró la caja en este período.'),
                    _seccion('Actividad reciente', [
                      for (final a in d['actividad'] as List)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.history, size: 18, color: AppColors.textMuted),
                          title: Text(a['accion']),
                          subtitle: Text('${_hora(a['fecha'])}${(a['detalle'] ?? '').toString().isEmpty ? '' : ' · ${a['detalle']}'}'),
                        ),
                    ], vacio: 'Sin actividad registrada.'),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Agregar o corregir una marca de asistencia (lo hace el dueño). Devuelve
/// {entrada, salida, nota} para el backend, o {borrar: true}.
class _DialogoMarca extends StatefulWidget {
  final Map<String, dynamic>? marca;
  final String nombre;
  const _DialogoMarca({required this.marca, required this.nombre});

  @override
  State<_DialogoMarca> createState() => _DialogoMarcaState();
}

class _DialogoMarcaState extends State<_DialogoMarca> {
  late DateTime _dia;
  late TimeOfDay _entrada;
  TimeOfDay? _salida;
  late final _nota = TextEditingController(text: widget.marca?['nota'] ?? '');

  @override
  void initState() {
    super.initState();
    final m = widget.marca;
    final entrada = m == null ? DateTime.now() : DateTime.parse(m['entrada']).toLocal();
    _dia = DateTime(entrada.year, entrada.month, entrada.day);
    _entrada = m == null ? const TimeOfDay(hour: 8, minute: 0) : TimeOfDay.fromDateTime(entrada);
    if (m?['salida'] != null) _salida = TimeOfDay.fromDateTime(DateTime.parse(m!['salida']).toLocal());
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  DateTime _en(TimeOfDay t, {bool diaSiguiente = false}) =>
      DateTime(_dia.year, _dia.month, _dia.day + (diaSiguiente ? 1 : 0), t.hour, t.minute);

  Future<void> _elegirHora({required bool entrada}) async {
    final hora = await showTimePicker(
      context: context,
      initialTime: entrada ? _entrada : (_salida ?? const TimeOfDay(hour: 17, minute: 0)),
    );
    if (hora != null) setState(() => entrada ? _entrada = hora : _salida = hora);
  }

  Widget _campo(String etiqueta, String valor, VoidCallback onTap, {Widget? sufijo}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: etiqueta, isDense: true, border: const OutlineInputBorder(), suffixIcon: sufijo),
        child: Text(valor),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final nueva = widget.marca == null;
    final entrada = _en(_entrada);
    // Salida antes que la entrada = turno que pasa la medianoche.
    final cruza = _salida != null && (_salida!.hour * 60 + _salida!.minute) <= (_entrada.hour * 60 + _entrada.minute);
    final salida = _salida == null ? null : _en(_salida!, diaSiguiente: cruza);
    return AlertDialog(
      title: Text(nueva ? 'Agregar marca de ${widget.nombre}' : 'Corregir marca'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _campo('Día', '${_diasSemana[_dia.weekday - 1]} ${_dia.day}/${_dia.month}/${_dia.year}', () async {
              final dia = await showDatePicker(
                context: context,
                initialDate: _dia,
                firstDate: DateTime.now().subtract(const Duration(days: 400)),
                lastDate: DateTime.now(),
              );
              if (dia != null) setState(() => _dia = dia);
            }),
            Row(children: [
              Expanded(child: _campo('Entrada', _entrada.format(context), () => _elegirHora(entrada: true))),
              const SizedBox(width: 10),
              Expanded(
                child: _campo(
                  'Salida',
                  _salida == null ? 'Sin salida' : _salida!.format(context),
                  () => _elegirHora(entrada: false),
                  sufijo: _salida == null
                      ? null
                      : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _salida = null)),
                ),
              ),
            ]),
            if (salida != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Total: ${_horasTexto(salida.difference(entrada).inMinutes / 60)}${cruza ? ' (sale al día siguiente)' : ''}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ),
            TextField(
              controller: _nota,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)', hintText: 'Ej: se le olvidó marcar', isDense: true, border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        if (!nueva)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, {'borrar': true}),
            child: const Text('Borrar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'entrada': entrada.toUtc().toIso8601String(),
            'salida': salida?.toUtc().toIso8601String(),
            'nota': _nota.text.trim(),
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
