import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'formato.dart';
import 'login.dart';
import 'onvo_cobro_automatico_screen.dart';
import 'plan.dart';
import 'theme/app_theme.dart';

/// Alta pública desde el login (sin sesión previa): despacho contable,
/// contador independiente, o negocio directo. Los tres necesitan elegir un
/// plan y pagarlo (vía OnvoCobroAutomaticoScreen) antes de poder usar el
/// sistema -- ver RegistroPublicoView, que ya los crea con la suscripción
/// en "suspendido" independientemente de esto.
class RegistroPublicoScreen extends StatefulWidget {
  const RegistroPublicoScreen({super.key});

  @override
  State<RegistroPublicoScreen> createState() => _RegistroPublicoScreenState();
}

/// Normaliza los 3 catalogos de plan distintos (Plan/PlanContador/
/// PlanDespacho, cada uno con su propio campo de limite) a una sola forma
/// que la UI puede mostrar sin importarle cual es.
class _PlanOption {
  final int id;
  final String nombre;
  final double? precioMensual;
  final String textoLimite;
  _PlanOption({required this.id, required this.nombre, required this.precioMensual, required this.textoLimite});
}

class _RegistroPublicoScreenState extends State<RegistroPublicoScreen> {
  String _tipo = 'negocio'; // 'despacho' | 'contador' | 'negocio'
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _correoHaciendaCtrl = TextEditingController();
  final _codigoActividadCtrl = TextEditingController();
  String _tipoCedula = '02';

  bool _cargandoPlanes = true;
  List<_PlanOption> _planes = [];
  int? _planSeleccionadoId;
  bool _enviando = false;
  // Si esta marcado, se registra igual eligiendo un plan (para saber que
  // va a pagar despues), pero se salta el pago inmediato -- ver
  // RegistroPublicoView.DIAS_PRUEBA_GRATIS en el backend.
  bool _pruebaGratis = false;

  // Los tres tipos pagan un plan propio (ver RegistroPublicoView) -- un
  // contador que se engancha a un despacho existente no pasa por acá, eso
  // lo hace el despacho desde su panel, y no paga aparte.
  bool get _requierePago => true;

  String get _endpointPlanes {
    switch (_tipo) {
      case 'despacho':
        return '/planes-despacho/';
      case 'contador':
        return '/planes-contador/';
      default:
        return '/planes/';
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarPlanes();
  }

  Future<void> _cambiarTipo(String nuevoTipo) {
    setState(() {
      _tipo = nuevoTipo;
      _planSeleccionadoId = null;
      _cargandoPlanes = true;
    });
    return _cargarPlanes();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _telefonoCtrl.dispose();
    _cedulaCtrl.dispose();
    _correoHaciendaCtrl.dispose();
    _codigoActividadCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarPlanes() async {
    try {
      final response = await ApiService.get(_endpointPlanes);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List datos = json.decode(utf8.decode(response.bodyBytes));
        final planes = datos.map((j) => _planOptionDesde(j)).toList();
        setState(() {
          _planes = planes;
          _cargandoPlanes = false;
          if (_planes.isNotEmpty) _planSeleccionadoId ??= _planes.first.id;
        });
      } else {
        setState(() => _cargandoPlanes = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoPlanes = false);
    }
  }

  _PlanOption _planOptionDesde(Map<String, dynamic> json) {
    switch (_tipo) {
      case 'despacho':
        final p = PlanDespacho.fromJson(json);
        return _PlanOption(
          id: p.id, nombre: p.nombre, precioMensual: p.precioMensual,
          textoLimite: p.limiteContadores != null ? "${p.limiteContadores} contadores" : "Contadores ilimitados",
        );
      case 'contador':
        final p = PlanContador.fromJson(json);
        return _PlanOption(
          id: p.id, nombre: p.nombre, precioMensual: p.precioMensual,
          textoLimite: p.limiteNegocios != null ? "${p.limiteNegocios} negocios" : "Negocios ilimitados",
        );
      default:
        final p = Plan.fromJson(json);
        return _PlanOption(
          id: p.id, nombre: p.nombre, precioMensual: p.precioMensual,
          textoLimite: "${p.limiteFacturasMensual} facturas/mes",
        );
    }
  }

  Future<void> _registrarse() async {
    if (!_formKey.currentState!.validate()) return;
    if (_requierePago && _planSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Elegí un plan.")));
      return;
    }

    setState(() => _enviando = true);
    final body = {
      'tipo': _tipo,
      'nombre': _nombreCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'username': _usernameCtrl.text.trim(),
      'password': _passwordCtrl.text,
      if (_requierePago) ...{
        'plan': _planSeleccionadoId,
        'telefono': _telefonoCtrl.text.trim(),
        'prueba_gratis': _pruebaGratis,
      },
      if (_tipo == 'negocio') ...{
        'cedula': _cedulaCtrl.text.trim(),
        'tipo_cedula': _tipoCedula,
        'correo_hacienda': _correoHaciendaCtrl.text.trim(),
        'codigo_actividad': _codigoActividadCtrl.text.trim(),
      },
    };

    try {
      final response = await ApiService.post('/registro/', body);
      final datos = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 201) {
        throw Exception(datos['detail'] ?? 'No se pudo completar el registro.');
      }

      await ApiService.saveTokens(access: datos['access'], refresh: datos['refresh']);

      if (!mounted) return;
      if (_requierePago && !_pruebaGratis) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OnvoCobroAutomaticoScreen(
              tipo: _tipo,
              suscripcionId: datos['suscripcion_id'],
              nombreTitular: _nombreCtrl.text.trim(),
            ),
          ),
        );
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Crear cuenta"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("¿Cómo querés registrarte?", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _SelectorTipo(
                      tipo: _tipo,
                      onChanged: _cambiarTipo,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: InputDecoration(
                        labelText: _tipo == 'despacho' ? "Nombre del despacho" : (_tipo == 'negocio' ? "Nombre comercial" : "Tu nombre"),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? "Requerido" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: "Correo electrónico", border: OutlineInputBorder()),
                      validator: (v) => (v == null || !v.contains('@')) ? "Correo inválido" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(labelText: "Nombre de usuario", border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? "Requerido" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "Contraseña", border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.length < 6) ? "Mínimo 6 caracteres" : null,
                    ),
                    if (_requierePago) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: "Teléfono", border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty) ? "Requerido" : null,
                      ),
                    ],
                    if (_tipo == 'negocio') ...[
                      const SizedBox(height: 20),
                      const Text("Datos para facturar", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _cedulaCtrl,
                              decoration: const InputDecoration(labelText: "Cédula", border: OutlineInputBorder()),
                              validator: (v) => (v == null || v.trim().isEmpty) ? "Requerido" : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _tipoCedula,
                              decoration: const InputDecoration(labelText: "Tipo", border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: '01', child: Text("Física")),
                                DropdownMenuItem(value: '02', child: Text("Jurídica")),
                                DropdownMenuItem(value: '03', child: Text("DIMEX")),
                                DropdownMenuItem(value: '04', child: Text("NITE")),
                              ],
                              onChanged: (v) => setState(() => _tipoCedula = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _correoHaciendaCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: "Correo registrado ante Hacienda", border: OutlineInputBorder()),
                        validator: (v) => (v == null || !v.contains('@')) ? "Correo inválido" : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _codigoActividadCtrl,
                        decoration: const InputDecoration(labelText: "Código de actividad económica (Hacienda)", border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty) ? "Requerido" : null,
                      ),
                    ],
                    if (_requierePago) ...[
                      const SizedBox(height: 20),
                      const Text("Elegí tu plan", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _cargandoPlanes
                          ? const Center(child: CircularProgressIndicator())
                          : _planes.isEmpty
                              ? const Text("No hay planes disponibles en este momento.", style: TextStyle(color: Colors.red))
                              : Column(
                                  children: _planes.map((p) {
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: _planSeleccionadoId == p.id ? AppColors.primary : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: RadioListTile<int>(
                                        value: p.id,
                                        groupValue: _planSeleccionadoId,
                                        onChanged: (v) => setState(() => _planSeleccionadoId = v),
                                        title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text(
                                          "${p.textoLimite}"
                                          "${p.precioMensual != null ? ' · ${formatearColones(p.precioMensual!)}/mes' : ''}",
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                      const SizedBox(height: 12),
                      Card(
                        margin: EdgeInsets.zero,
                        color: _pruebaGratis ? AppColors.primary.withOpacity(0.08) : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: _pruebaGratis ? AppColors.primary : Colors.transparent, width: 2),
                        ),
                        child: CheckboxListTile(
                          value: _pruebaGratis,
                          onChanged: (v) => setState(() => _pruebaGratis = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text("Empezar con 8 días de prueba gratis", style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text("Usás Equilibra ya mismo y pagás la tarjeta más adelante, antes de que se acaben los 8 días."),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pruebaGratis
                            ? "No te vamos a cobrar nada todavía."
                            : "Vas a poder pagar con tarjeta justo después de crear la cuenta.",
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _enviando ? null : _registrarse,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: _enviando
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_requierePago && !_pruebaGratis ? "Continuar al pago" : "Crear cuenta"),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectorTipo extends StatelessWidget {
  final String tipo;
  final ValueChanged<String> onChanged;
  const _SelectorTipo({required this.tipo, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const opciones = [
      ('negocio', 'Negocio', Icons.storefront_outlined),
      ('despacho', 'Despacho contable', Icons.account_balance_outlined),
      ('contador', 'Contador independiente', Icons.badge_outlined),
    ];
    return Column(
      children: opciones.map((o) {
        final seleccionado = tipo == o.$1;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: seleccionado ? AppColors.primary.withOpacity(0.1) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: seleccionado ? AppColors.primary : Colors.transparent, width: 2),
          ),
          child: ListTile(
            leading: Icon(o.$3, color: seleccionado ? AppColors.primary : AppColors.textMuted),
            title: Text(o.$2, style: TextStyle(fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal)),
            onTap: () => onChanged(o.$1),
          ),
        );
      }).toList(),
    );
  }
}
