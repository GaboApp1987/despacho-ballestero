import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'avatar_logo.dart';
import 'firmante_contador.dart';
import 'login.dart';
import 'logo_screen.dart';

/// Pantalla de "Mi Perfil" reutilizable para el usuario que tiene la sesión
/// abierta (despacho, contador o negocio): logo, cambio de contraseña y
/// cerrar sesión, todo en un solo lugar en vez de íconos sueltos en el AppBar.
class PerfilUsuarioScreen extends StatefulWidget {
  final String nombre;
  final String? subtitulo;
  final String logoEndpoint; // ej: '/despachos/1/', '/socios/3/', '/negocios/5/'
  final String? logoUrlInicial;
  final bool esContador;

  const PerfilUsuarioScreen({
    super.key,
    required this.nombre,
    this.subtitulo,
    required this.logoEndpoint,
    this.logoUrlInicial,
    this.esContador = false,
  });

  @override
  State<PerfilUsuarioScreen> createState() => _PerfilUsuarioScreenState();
}

class _PerfilUsuarioScreenState extends State<PerfilUsuarioScreen> {
  String? _logoUrl;
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _ocultarActual = true;
  bool _ocultarNueva = true;
  bool _cambiandoPassword = false;
  bool _whatsappCargando = false;
  Map<String, dynamic>? _whatsappResultado;

  final _carneCtrl = TextEditingController();
  final _especialidadCtrl = TextEditingController();
  final _direccionProfesionalCtrl = TextEditingController();
  final _polizaCtrl = TextEditingController();
  DateTime? _polizaVencimiento;
  bool _cargandoDatosCpa = true;
  bool _guardandoDatosCpa = false;
  bool _firmarConNombreRegistrado = true;
  List<FirmanteContador> _firmantes = [];
  bool _guardandoFirmantes = false;

  final _plantillaCertificacionCtrl = TextEditingController();
  bool _guardandoPlantilla = false;
  bool _cargandoPlantillaDefault = false;

  Color get _colorFondo => widget.esContador ? TemaContador.fondo : AppColors.background;
  Color get _colorSuperficie => widget.esContador ? TemaContador.superficie : AppColors.surface;
  Color get _colorBorde => widget.esContador ? TemaContador.borde : AppColors.border;
  Color get _colorFuerte => widget.esContador ? TemaContador.textoFuerte : AppColors.textStrong;
  Color get _colorAcento => widget.esContador ? TemaContador.acento : AppColors.primary;

  InputDecoration _decoracionCampo(String label, {Widget? suffixIcon}) {
    if (!widget.esContador) {
      return InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: suffixIcon);
    }
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: TemaContador.textoTenue),
      filled: true,
      fillColor: TemaContador.superficie,
      border: const OutlineInputBorder(borderSide: BorderSide(color: TemaContador.borde)),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: TemaContador.borde)),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: TemaContador.acento, width: 1.5)),
      suffixIcon: suffixIcon,
    );
  }

  @override
  void initState() {
    super.initState();
    _logoUrl = widget.logoUrlInicial;
    if (widget.esContador) {
      _cargarDatosCpa();
    } else {
      _cargandoDatosCpa = false;
    }
  }

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    _carneCtrl.dispose();
    _especialidadCtrl.dispose();
    _direccionProfesionalCtrl.dispose();
    _polizaCtrl.dispose();
    _plantillaCertificacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosCpa() async {
    try {
      final response = await ApiService.get(widget.logoEndpoint);
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _carneCtrl.text = data['carne_cpa'] ?? '';
          _especialidadCtrl.text = data['especialidad'] ?? '';
          _direccionProfesionalCtrl.text = data['direccion_profesional'] ?? '';
          _polizaCtrl.text = data['poliza_fidelidad'] ?? '';
          _polizaVencimiento = data['poliza_vencimiento'] != null ? DateTime.tryParse(data['poliza_vencimiento']) : null;
          _firmarConNombreRegistrado = data['firmar_con_nombre_registrado'] ?? true;
          _firmantes = ((data['firmantes'] as List?) ?? []).map((f) => FirmanteContador.fromJson(f)).toList();
          _plantillaCertificacionCtrl.text = data['plantilla_certificacion_ingreso'] ?? '';
        });
      }
    } catch (_) {
      // si falla, el formulario simplemente queda vacío para llenar de cero
    }
    if (mounted) setState(() => _cargandoDatosCpa = false);
  }

  Future<void> _elegirVencimientoPoliza() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _polizaVencimiento ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (elegida != null) setState(() => _polizaVencimiento = elegida);
  }

  Future<void> _guardarDatosCpa() async {
    setState(() => _guardandoDatosCpa = true);
    try {
      final response = await ApiService.patch(widget.logoEndpoint, {
        'carne_cpa': _carneCtrl.text.trim(),
        'especialidad': _especialidadCtrl.text.trim(),
        'direccion_profesional': _direccionProfesionalCtrl.text.trim(),
        'poliza_fidelidad': _polizaCtrl.text.trim(),
        if (_polizaVencimiento != null) 'poliza_vencimiento': _polizaVencimiento!.toIso8601String().split('T').first,
        'firmar_con_nombre_registrado': _firmarConNombreRegistrado,
      });
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Datos profesionales actualizados"), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _guardandoDatosCpa = false);
    }
  }

  Future<void> _guardarPlantillaCertificacion() async {
    setState(() => _guardandoPlantilla = true);
    try {
      final response = await ApiService.patch(widget.logoEndpoint, {
        'plantilla_certificacion_ingreso': _plantillaCertificacionCtrl.text.trim(),
      });
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Plantilla de certificación guardada"), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _guardandoPlantilla = false);
    }
  }

  Future<void> _cargarPlantillaPorDefecto() async {
    if (_plantillaCertificacionCtrl.text.trim().isNotEmpty) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("¿Reemplazar el texto actual?"),
          content: const Text("Esto va a sobreescribir lo que ya escribiste en el cuadro con la redacción por defecto, para que la edités a partir de ahí. No se guarda hasta que toqués \"Guardar plantilla\"."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancelar")),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text("Reemplazar")),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    setState(() => _cargandoPlantillaDefault = true);
    try {
      final response = await ApiService.get('/socios/plantilla-certificacion-default/');
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() => _plantillaCertificacionCtrl.text = data['plantilla'] ?? '');
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _cargandoPlantillaDefault = false);
    }
  }

  Future<void> _abrirFormularioFirmante({FirmanteContador? firmante}) async {
    final nombreCtrl = TextEditingController(text: firmante?.nombre ?? '');
    final carneCtrl = TextEditingController(text: firmante?.carneCpa ?? '');
    final guardado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _colorFondo,
        title: Text(firmante == null ? "Nuevo firmante" : "Editar firmante", style: TextStyle(color: _colorFuerte, fontSize: 17)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreCtrl, style: TextStyle(color: _colorFuerte), decoration: _decoracionCampo("Nombre completo")),
              const SizedBox(height: 12),
              TextField(controller: carneCtrl, style: TextStyle(color: _colorFuerte), decoration: _decoracionCampo("Carné C.P.A.")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _colorAcento, foregroundColor: Colors.white),
            onPressed: () async {
              if (nombreCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text("Ingresá el nombre.")));
                return;
              }
              final body = {'nombre': nombreCtrl.text.trim(), 'carne_cpa': carneCtrl.text.trim()};
              final response = firmante == null
                  ? await ApiService.post('/firmantes-contador/', body)
                  : await ApiService.patch('/firmantes-contador/${firmante.id}/', body);
              if (dialogContext.mounted) Navigator.pop(dialogContext, response.statusCode == 200 || response.statusCode == 201);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
    nombreCtrl.dispose();
    carneCtrl.dispose();
    if (guardado == true) _cargarDatosCpa();
  }

  Future<void> _eliminarFirmante(FirmanteContador firmante) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("¿Eliminar firmante?"),
        content: Text("Se eliminará a ${firmante.nombre} de tu lista de firmantes."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text("Eliminar", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _guardandoFirmantes = true);
    try {
      final r = await ApiService.delete('/firmantes-contador/${firmante.id}/');
      if (r.statusCode == 204) _cargarDatosCpa();
    } catch (_) {}
    if (mounted) setState(() => _guardandoFirmantes = false);
  }

  Future<void> _abrirCambiarLogo() async {
    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LogoScreen(
          titulo: "Mi Logo",
          endpoint: widget.logoEndpoint,
          logoUrlInicial: _logoUrl,
        ),
      ),
    );
    if (actualizado == true) {
      try {
        final response = await ApiService.get(widget.logoEndpoint);
        if (response.statusCode == 200 && mounted) {
          setState(() => _logoUrl = json.decode(utf8.decode(response.bodyBytes))['logo']);
        }
      } catch (_) {
        // si falla, se queda con el logo anterior en pantalla
      }
    }
  }

  Future<void> _cambiarPassword() async {
    if (_actualCtrl.text.isEmpty || _nuevaCtrl.text.isEmpty || _confirmarCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complete los tres campos")),
      );
      return;
    }
    if (_nuevaCtrl.text != _confirmarCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La nueva contraseña y su confirmación no coinciden")),
      );
      return;
    }
    if (_nuevaCtrl.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La nueva contraseña debe tener al menos 8 caracteres")),
      );
      return;
    }

    setState(() => _cambiandoPassword = true);
    try {
      final response = await ApiService.post('/mi-perfil/', {
        'password_actual': _actualCtrl.text,
        'password_nueva': _nuevaCtrl.text,
      });
      if (response.statusCode == 200) {
        _actualCtrl.clear();
        _nuevaCtrl.clear();
        _confirmarCtrl.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Contraseña actualizada"), backgroundColor: Colors.green),
          );
        }
      } else {
        final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'Error desconocido';
        throw Exception(detalle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
      }
    } finally {
      if (mounted) setState(() => _cambiandoPassword = false);
    }
  }

  Future<void> _vincularWhatsApp() async {
    setState(() => _whatsappCargando = true);
    try {
      final response = await ApiService.post('/whatsapp/generar-codigo/', {});
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200) {
        setState(() => _whatsappResultado = data);
      } else {
        throw Exception(data['detail'] ?? 'No se pudo generar el código de vinculación');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
      }
    } finally {
      if (mounted) setState(() => _whatsappCargando = false);
    }
  }

  Future<void> _abrirCodigoEnWhatsApp() async {
    final uri = Uri.parse(_whatsappResultado!['wa_link']);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo abrir WhatsApp.")),
      );
    }
  }

  Future<void> _confirmarCerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Cerrar sesión?"),
        content: const Text("Tendrá que volver a ingresar su usuario y contraseña."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Cerrar sesión")),
        ],
      ),
    );
    if (confirmar != true) return;
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _colorFuerte),
          tooltip: "Volver",
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Mi Perfil", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: _colorFuerte)),
        backgroundColor: _colorSuperficie,
        foregroundColor: _colorFuerte,
        iconTheme: IconThemeData(color: _colorFuerte),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  InkWell(
                    onTap: _abrirCambiarLogo,
                    borderRadius: BorderRadius.circular(50),
                    child: Stack(
                      children: [
                        avatarConLogo(logoUrl: _logoUrl, icono: Icons.account_circle, radius: 50, nombre: widget.nombre),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: _colorSuperficie, shape: BoxShape.circle),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(widget.nombre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.esContador ? _colorFuerte : null)),
                  if (widget.subtitulo != null)
                    Text(widget.subtitulo!, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _abrirCambiarLogo,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text("Cambiar logo"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _colorSuperficie,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _colorBorde),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Cambiar Contraseña", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.esContador ? _colorFuerte : null)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _actualCtrl,
                    obscureText: _ocultarActual,
                    style: widget.esContador ? const TextStyle(color: TemaContador.textoFuerte) : null,
                    decoration: _decoracionCampo(
                      "Contraseña actual",
                      suffixIcon: IconButton(
                        icon: Icon(
                          _ocultarActual ? Icons.visibility_off : Icons.visibility,
                          color: widget.esContador ? TemaContador.textoTenue : null,
                        ),
                        onPressed: () => setState(() => _ocultarActual = !_ocultarActual),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nuevaCtrl,
                    obscureText: _ocultarNueva,
                    style: widget.esContador ? const TextStyle(color: TemaContador.textoFuerte) : null,
                    decoration: _decoracionCampo(
                      "Nueva contraseña",
                      suffixIcon: IconButton(
                        icon: Icon(
                          _ocultarNueva ? Icons.visibility_off : Icons.visibility,
                          color: widget.esContador ? TemaContador.textoTenue : null,
                        ),
                        onPressed: () => setState(() => _ocultarNueva = !_ocultarNueva),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmarCtrl,
                    obscureText: _ocultarNueva,
                    style: widget.esContador ? const TextStyle(color: TemaContador.textoFuerte) : null,
                    decoration: _decoracionCampo("Confirmar nueva contraseña"),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _cambiandoPassword ? null : _cambiarPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _colorAcento,
                        foregroundColor: widget.esContador ? Colors.white : Colors.black,
                      ),
                      child: _cambiandoPassword
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: widget.esContador ? Colors.white : Colors.black),
                            )
                          : Text(
                              "Actualizar Contraseña",
                              style: TextStyle(color: widget.esContador ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _colorSuperficie,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _colorBorde),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_outlined, size: 20, color: widget.esContador ? _colorFuerte : null),
                      const SizedBox(width: 8),
                      Text("WhatsApp", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.esContador ? _colorFuerte : null)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_whatsappResultado == null) ...[
                    const Text(
                      "Vinculá tu WhatsApp para recibir avisos y consultarle cosas al asistente directamente desde ahí.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _whatsappCargando ? null : _vincularWhatsApp,
                        icon: _whatsappCargando
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.link),
                        label: const Text("Vincular WhatsApp"),
                      ),
                    ),
                  ] else if (_whatsappResultado!['telefono'] != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Ya vinculado: ${_whatsappResultado!['telefono']}",
                            style: TextStyle(fontSize: 13, color: widget.esContador ? _colorFuerte : null),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      "Enviá este código desde tu WhatsApp al número indicado para completar la vinculación (vence en ${_whatsappResultado!['vence_en_minutos']} minutos):",
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _colorFondo,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _colorBorde),
                      ),
                      child: Text(
                        _whatsappResultado!['codigo'] ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: widget.esContador ? _colorFuerte : null),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _abrirCodigoEnWhatsApp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _colorAcento,
                          foregroundColor: widget.esContador ? Colors.white : Colors.black,
                        ),
                        icon: Icon(Icons.open_in_new, color: widget.esContador ? Colors.white : Colors.black),
                        label: Text(
                          "Abrir WhatsApp y enviar código",
                          style: TextStyle(color: widget.esContador ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.esContador) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _colorSuperficie,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _colorBorde),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_outlined, size: 20, color: _colorFuerte),
                        const SizedBox(width: 8),
                        Text("Datos profesionales (CPA)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _colorFuerte)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Salen en el encabezado y la firma de las certificaciones que emitís.",
                      style: TextStyle(fontSize: 13, color: widget.esContador ? TemaContador.textoTenue : Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    if (_cargandoDatosCpa)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      TextField(controller: _carneCtrl, style: TextStyle(color: _colorFuerte), decoration: _decoracionCampo("Carné C.P.A.")),
                      const SizedBox(height: 10),
                      TextField(controller: _especialidadCtrl, style: TextStyle(color: _colorFuerte), decoration: _decoracionCampo("Especialidad (ej: Impuestos)")),
                      const SizedBox(height: 10),
                      TextField(controller: _direccionProfesionalCtrl, style: TextStyle(color: _colorFuerte), decoration: _decoracionCampo("Dirección profesional")),
                      const SizedBox(height: 10),
                      TextField(controller: _polizaCtrl, style: TextStyle(color: _colorFuerte), decoration: _decoracionCampo("Póliza de fidelidad No.")),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: _elegirVencimientoPoliza,
                        child: InputDecorator(
                          decoration: _decoracionCampo("Vence el"),
                          child: Text(
                            _polizaVencimiento == null
                                ? "Sin definir"
                                : "${_polizaVencimiento!.day}/${_polizaVencimiento!.month}/${_polizaVencimiento!.year}",
                            style: TextStyle(color: _colorFuerte),
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("Firmar documentos con mi nombre registrado", style: TextStyle(color: _colorFuerte, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          _firmarConNombreRegistrado
                              ? "Certificaciones, atestiguamientos y flujos de caja se firman con tu nombre y carné de arriba."
                              : "Vas a poder elegir, documento por documento, con cuál de tus firmantes se firma.",
                          style: TextStyle(fontSize: 12, color: widget.esContador ? TemaContador.textoTenue : Colors.grey),
                        ),
                        value: _firmarConNombreRegistrado,
                        activeColor: _colorAcento,
                        onChanged: (v) => setState(() => _firmarConNombreRegistrado = v),
                      ),
                      if (!_firmarConNombreRegistrado) ...[
                        const SizedBox(height: 8),
                        Text("Tus firmantes", style: TextStyle(color: _colorFuerte, fontWeight: FontWeight.w700, fontSize: 13.5)),
                        const SizedBox(height: 8),
                        if (_firmantes.isEmpty)
                          Text(
                            "Todavía no agregaste ningún firmante. Agregá al menos uno para poder elegirlo en tus documentos.",
                            style: TextStyle(fontSize: 12.5, color: widget.esContador ? TemaContador.textoTenue : Colors.grey),
                          )
                        else
                          ..._firmantes.map((f) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(color: _colorFondo, borderRadius: BorderRadius.circular(10), border: Border.all(color: _colorBorde)),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: Icon(Icons.badge_outlined, color: _colorAcento, size: 20),
                                  title: Text(f.nombre, style: TextStyle(color: _colorFuerte, fontWeight: FontWeight.w600, fontSize: 13.5)),
                                  subtitle: f.carneCpa.isNotEmpty ? Text("Carné ${f.carneCpa}", style: TextStyle(color: widget.esContador ? TemaContador.textoTenue : Colors.grey, fontSize: 12)) : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(icon: Icon(Icons.edit_outlined, size: 18, color: widget.esContador ? TemaContador.textoTenue : Colors.grey), onPressed: _guardandoFirmantes ? null : () => _abrirFormularioFirmante(firmante: f)),
                                      IconButton(icon: Icon(Icons.delete_outline, size: 18, color: widget.esContador ? TemaContador.textoTenue : Colors.grey), onPressed: _guardandoFirmantes ? null : () => _eliminarFirmante(f)),
                                    ],
                                  ),
                                ),
                              )),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () => _abrirFormularioFirmante(),
                          style: TextButton.styleFrom(foregroundColor: _colorAcento),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text("Agregar firmante"),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _guardandoDatosCpa ? null : _guardarDatosCpa,
                          style: ElevatedButton.styleFrom(backgroundColor: _colorAcento, foregroundColor: Colors.white),
                          child: _guardandoDatosCpa
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text("Guardar datos profesionales", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _colorSuperficie,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _colorBorde),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.description_outlined, size: 20, color: _colorFuerte),
                        const SizedBox(width: 8),
                        Text("Plantilla de Certificación de Ingresos", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _colorFuerte)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Tu propia redacción para el cuerpo del documento. Si la dejás vacía, se usa la redacción por defecto del despacho. Separá cada párrafo con una línea en blanco; un párrafo escrito TODO EN MAYÚSCULAS se muestra como subtítulo.",
                      style: TextStyle(fontSize: 13, color: widget.esContador ? TemaContador.textoTenue : Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Marcadores disponibles: {nombre} {cedula} {nacionalidad} {direccion} {estado_civil} {actividad} {proposito} {dirigido_a} {fecha_inicio} {fecha_fin} {fecha_emision} {lugar_emision} {moneda_simbolo} {ingreso_bruto_promedio} {ingreso_neto_promedio} {anos_ejerciendo_frase}",
                      style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: widget.esContador ? TemaContador.textoTenue : Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    if (_cargandoDatosCpa)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      TextField(
                        controller: _plantillaCertificacionCtrl,
                        style: TextStyle(color: _colorFuerte, fontSize: 13),
                        maxLines: 14,
                        minLines: 6,
                        decoration: _decoracionCampo("Redacción (vacío = usar la de por defecto)"),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _cargandoPlantillaDefault ? null : _cargarPlantillaPorDefecto,
                        style: TextButton.styleFrom(foregroundColor: _colorAcento),
                        icon: _cargandoPlantillaDefault
                            ? SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _colorAcento))
                            : const Icon(Icons.file_download_outlined, size: 18),
                        label: const Text("Cargar la redacción por defecto para editarla"),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _guardandoPlantilla ? null : _guardarPlantillaCertificacion,
                          style: ElevatedButton.styleFrom(backgroundColor: _colorAcento, foregroundColor: Colors.white),
                          child: _guardandoPlantilla
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text("Guardar plantilla", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _confirmarCerrarSesion,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                icon: const Icon(Icons.logout),
                label: const Text("Cerrar Sesión"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
