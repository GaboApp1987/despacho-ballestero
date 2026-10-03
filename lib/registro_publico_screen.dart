import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'analitica.dart';
import 'api_service.dart';
import 'formato.dart';
import 'login.dart';
import 'plan.dart';
import 'theme/app_theme.dart';
import 'widgets/tarjeta_plan_negocio.dart';
import 'ubicacion_cr.dart';
import 'widgets/campo_cedula_hacienda.dart';

/// Alta pública desde el login (sin sesión previa): despacho contable,
/// contador independiente, o negocio directo. La cuenta queda creada pero
/// INACTIVA hasta que confirmen el correo (ver VerificacionCorreo en el
/// backend) -- recién después de confirmar y entrar pueden elegir un plan
/// y pagarlo (vía OnvoCobroAutomaticoScreen, ofrecido desde
/// SuscripcionSuspendidaScreen apenas entran con la suscripción sin pagar).
class RegistroPublicoScreen extends StatefulWidget {
  /// Tipo de cuenta preseleccionado ('negocio' | 'contador' | 'despacho')
  /// y código promocional precargado -- vienen del link directo del
  /// landing (equilibracr.com/app/?registro=negocio&promo=BIENVENIDA15,
  /// ver main.dart). Null = comportamiento de siempre.
  final String? tipoInicial;
  final String? codigoPromocionalInicial;
  /// true = "Empezar con días de prueba gratis" ya marcado (link del
  /// landing con ?prueba=1).
  final bool pruebaGratisInicial;

  const RegistroPublicoScreen({super.key, this.tipoInicial, this.codigoPromocionalInicial, this.pruebaGratisInicial = false});

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
  /// Solo en planes de negocio: el plan completo, para la tarjeta detallada.
  final Plan? planNegocio;
  _PlanOption({required this.id, required this.nombre, required this.precioMensual, required this.textoLimite, this.planNegocio});
}

class _RegistroPublicoScreenState extends State<RegistroPublicoScreen> {
  String _tipo = 'negocio'; // 'despacho' | 'contador' | 'negocio'
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmarPasswordCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _correoHaciendaCtrl = TextEditingController();
  final _codigoActividadCtrl = TextEditingController();
  final _codigoPromocionalCtrl = TextEditingController();
  String _tipoCedula = '02';
  // Cargados de Hacienda con la cédula (ver CampoCedulaHacienda).
  String _nombreLegal = '';
  String _actividadAlanube = '';

  // Ubicación exigida por Hacienda (Provincia/Cantón/Distrito) -- opcional
  // acá igual que correo_hacienda/codigo_actividad: quien ya la tiene a
  // mano deja la cuenta completa de una vez, quien no, la completa después
  // desde Ajustes (ver configuracion_screen.dart).
  List<ProvinciaCR> _ubicaciones = [];
  bool _cargandoUbicaciones = true;
  String? _provinciaSel;
  String? _cantonSel;
  String? _distritoSel;

  List<CantonCR> get _cantonesDisponibles {
    if (_provinciaSel == null) return [];
    final prov = _ubicaciones.where((p) => p.codigo == _provinciaSel);
    return prov.isEmpty ? [] : prov.first.cantones;
  }

  List<DistritoCR> get _distritosDisponibles {
    if (_cantonSel == null) return [];
    final cant = _cantonesDisponibles.where((c) => c.codigo == _cantonSel);
    return cant.isEmpty ? [] : cant.first.distritos;
  }

  bool _cargandoPlanes = true;
  List<_PlanOption> _planes = [];
  int? _planSeleccionadoId;
  bool _enviando = false;
  // Si esta marcado, se registra igual eligiendo un plan (para saber que
  // va a pagar despues), pero se salta el pago inmediato -- ver
  // RegistroPublicoView.DIAS_PRUEBA_GRATIS en el backend.
  bool _pruebaGratis = false;
  bool _aceptaTerminos = false;

  // Para que no se le olvide el usuario, se precarga con el correo mientras
  // no se escriba uno distinto a mano.
  String _ultimoCorreoAutocopiado = '';

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
    if (const ['negocio', 'contador', 'despacho'].contains(widget.tipoInicial)) {
      _tipo = widget.tipoInicial!;
    }
    _pruebaGratis = widget.pruebaGratisInicial;
    Analitica.evento('registro_abierto', detalle: _tipo);
    final promo = widget.codigoPromocionalInicial?.trim() ?? '';
    if (promo.isNotEmpty) _codigoPromocionalCtrl.text = promo.toUpperCase();
    _cargarPlanes();
    UbicacionCR.cargar().then((u) {
      if (mounted) setState(() { _ubicaciones = u; _cargandoUbicaciones = false; });
    });
    _emailCtrl.addListener(() {
      final correo = _emailCtrl.text.trim();
      final usernameActual = _usernameCtrl.text.trim();
      if (usernameActual.isEmpty || usernameActual == _ultimoCorreoAutocopiado) {
        _usernameCtrl.text = correo;
        _ultimoCorreoAutocopiado = correo;
      }
    });
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
    _confirmarPasswordCtrl.dispose();
    _telefonoCtrl.dispose();
    _cedulaCtrl.dispose();
    _correoHaciendaCtrl.dispose();
    _codigoActividadCtrl.dispose();
    _codigoPromocionalCtrl.dispose();
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
          if (_planes.isNotEmpty) {
            final destacado = _planes.where((p) => p.planNegocio?.destacado == true);
            _planSeleccionadoId ??= (destacado.isNotEmpty ? destacado.first : _planes.first).id;
          }
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
          textoLimite: p.resumenLimites,
          planNegocio: p,
        );
    }
  }

  Future<void> _registrarse() async {
    if (!_formKey.currentState!.validate()) return;
    if (_requierePago && _planSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Elegí un plan.")));
      return;
    }
    if (!_aceptaTerminos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tenés que aceptar los Términos y la Política de Privacidad para continuar.")),
      );
      return;
    }

    setState(() => _enviando = true);
    Analitica.evento('registro_enviado', detalle: _tipo);
    final body = {
      'tipo': _tipo,
      // Mismo ID anónimo del landing -- el backend lo guarda con la cuenta
      // para completar el embudo (ver EventoAnalitica).
      'visitante': Analitica.visitante,
      'origen': Analitica.origen,
      'nombre': _nombreCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'username': _usernameCtrl.text.trim(),
      'password': _passwordCtrl.text,
      if (_requierePago) ...{
        'plan': _planSeleccionadoId,
        'telefono': _telefonoCtrl.text.trim(),
        'prueba_gratis': _pruebaGratis,
        'codigo_promocional': _codigoPromocionalCtrl.text.trim(),
      },
      if (_tipo == 'negocio') ...{
        'cedula': _cedulaCtrl.text.trim(),
        'tipo_cedula': _tipoCedula,
        if (_nombreLegal.isNotEmpty) 'nombre_legal': _nombreLegal,
        if (_actividadAlanube.isNotEmpty) 'alanube_economic_activity': _actividadAlanube,
        'correo_hacienda': _correoHaciendaCtrl.text.trim(),
        'codigo_actividad': _codigoActividadCtrl.text.trim(),
        if (_provinciaSel != null) 'provincia': _provinciaSel,
        if (_cantonSel != null) 'canton': _cantonSel,
        if (_distritoSel != null) 'distrito': _distritoSel,
      },
    };

    try {
      final response = await ApiService.post('/registro/', body);
      final datos = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 201) {
        throw Exception(datos['detail'] ?? 'No se pudo completar el registro.');
      }

      // La cuenta queda creada pero INACTIVA hasta que confirmen el correo
      // (ver VerificacionCorreo en el backend -- AUDITORIA.md, incidente de
      // bots del 2026-09-23) -- ya no hay tokens que guardar ni con qué
      // autenticar la configuración del cobro automático todavía. Si hace
      // falta pagar, lo van a poder hacer apenas entren después de
      // confirmar (SuscripcionSuspendidaScreen ofrece el mismo camino).
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text("¡Ya casi!"),
          content: Text(
            datos['detail'] ?? "Te enviamos un correo para confirmar tu cuenta. Revisá tu bandeja de entrada (y spam) y hacé clic en el link para activarla.",
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Entendido"),
            ),
          ],
        ),
      );
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
        // Si se llegó por el link directo del landing, esta pantalla es la
        // raíz (no hay flecha de "atrás") -- se ofrece ir al login.
        actions: [
          if (!Navigator.canPop(context))
            TextButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text("Ya tengo cuenta"),
            ),
        ],
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
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
                                children: [
                                  const TextSpan(
                                    text: "Si ya tenés todos los datos que pide Hacienda (certificado, cédula, "
                                        "actividad económica, etc.), completalos de una vez y quedás listo para "
                                        "facturar hoy mismo.\n\n",
                                  ),
                                  TextSpan(
                                    text: "Si todavía no los tenés a mano",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong),
                                  ),
                                  const TextSpan(
                                    text: ", no hay problema: registrate solo con usuario, cédula, contraseña y "
                                        "correo, y empezá a conocer la app ya mismo — para facturar de verdad vas "
                                        "a necesitar completar esos datos más adelante, cuando los tengas. Si no "
                                        "sabés cómo conseguirlos, preguntale a ",
                                  ),
                                  TextSpan(
                                    text: "Equilibra",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                  const TextSpan(text: " en el chat de soporte y te ayuda."),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_tipo == 'negocio') ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: CampoCedulaHacienda(
                              controller: _cedulaCtrl,
                              nombreController: _nombreCtrl,
                              labelText: "Cédula del negocio",
                              validator: (v) => (v == null || v.trim().isEmpty) ? "Requerido" : null,
                              onEncontrado: (datos) => setState(() {
                                final tipo = (datos['tipo_cedula'] ?? '').toString();
                                if (const ['01', '02', '03', '04'].contains(tipo)) _tipoCedula = tipo;
                                _nombreLegal = (datos['nombre'] ?? '').toString();
                                final principal = datos['actividad_principal'] as Map?;
                                _actividadAlanube = (principal?['codigo'] ?? '').toString();
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_tipoCedula),
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
                    ],
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
                      validator: (v) => (v == null || v.length < 8) ? "Mínimo 8 caracteres" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmarPasswordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "Confirmar contraseña", border: OutlineInputBorder()),
                      validator: (v) => (v != _passwordCtrl.text) ? "Las contraseñas no coinciden" : null,
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
                      if (_actividadAlanube.isNotEmpty) ...[
                        Text("Actividad económica de Hacienda: $_actividadAlanube (ya queda guardada para facturar)",
                            style: const TextStyle(fontSize: 12, color: Colors.green)),
                        const SizedBox(height: 10),
                      ],
                      TextFormField(
                        controller: _correoHaciendaCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "Correo registrado ante Hacienda (opcional)",
                          helperText: "Si no lo tenés a mano, lo completás después desde el perfil del negocio",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v != null && v.trim().isNotEmpty && !v.contains('@')) ? "Correo inválido" : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _codigoActividadCtrl,
                        decoration: const InputDecoration(
                          labelText: "Código de actividad económica (Hacienda) (opcional)",
                          helperText: "Si no lo tenés a mano, lo completás después desde el perfil del negocio",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Ubicación (opcional -- Provincia, Cantón y Distrito que exige Hacienda)",
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 8),
                      if (_cargandoUbicaciones)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _provinciaSel,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Provincia", border: OutlineInputBorder()),
                          items: _ubicaciones
                              .map((p) => DropdownMenuItem(value: p.codigo, child: Text("${p.codigo} - ${p.nombre}")))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _provinciaSel = v;
                            _cantonSel = null;
                            _distritoSel = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _cantonSel,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Cantón", border: OutlineInputBorder()),
                          items: _cantonesDisponibles
                              .map((c) => DropdownMenuItem(value: c.codigo, child: Text("${c.codigo} - ${c.nombre}")))
                              .toList(),
                          onChanged: _provinciaSel == null
                              ? null
                              : (v) => setState(() {
                                    _cantonSel = v;
                                    _distritoSel = null;
                                  }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _distritoSel,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Distrito", border: OutlineInputBorder()),
                          items: _distritosDisponibles
                              .map((d) => DropdownMenuItem(value: d.codigo, child: Text("${d.codigo} - ${d.nombre}")))
                              .toList(),
                          onChanged: _cantonSel == null ? null : (v) => setState(() => _distritoSel = v),
                        ),
                      ],
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
                                    if (p.planNegocio != null) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: TarjetaPlanNegocio(
                                          plan: p.planNegocio!,
                                          compacta: true,
                                          seleccionada: _planSeleccionadoId == p.id,
                                          onTap: () => setState(() => _planSeleccionadoId = p.id),
                                        ),
                                      );
                                    }
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
                          title: const Text("Empezar con 10 días de prueba gratis", style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text("Usás Equilibra ya mismo y pagás la tarjeta más adelante, antes de que se acaben los 10 días."),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pruebaGratis
                            ? "No te vamos a cobrar nada todavía."
                            : "Vas a poder pagar con tarjeta justo después de crear la cuenta.",
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _codigoPromocionalCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: "Código promocional (opcional)",
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.card_giftcard, size: 20),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _aceptaTerminos,
                          onChanged: (v) => setState(() => _aceptaTerminos = v ?? false),
                        ),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text("Acepto los "),
                              _EnlaceLegal(texto: "Términos y Condiciones", url: "https://equilibracr.com/terminos.html"),
                              const Text(" y la "),
                              _EnlaceLegal(texto: "Política de Privacidad", url: "https://equilibracr.com/privacidad.html"),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _enviando ? null : _registrarse,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: _enviando
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Crear cuenta"),
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

/// Link clickeable a Términos/Privacidad dentro del texto de aceptación del
/// registro -- abre en el navegador (o la app de navegador del celular),
/// nunca dentro de la propia app.
class _EnlaceLegal extends StatelessWidget {
  final String texto;
  final String url;
  const _EnlaceLegal({required this.texto, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(
        texto,
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
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
