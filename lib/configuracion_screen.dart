import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'theme/app_theme.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'negocio.dart';
import 'api_service.dart';
import 'logo_screen.dart';

class ConfiguracionScreen extends StatefulWidget {
  final Negocio negocio;
  final VoidCallback? onGuardado;
  const ConfiguracionScreen({super.key, required this.negocio, this.onGuardado});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _usuarioController;
  late TextEditingController _passwordController;
  late TextEditingController _pinController;
  late TextEditingController _nombreComercialController;
  late TextEditingController _direccionController;
  late TextEditingController _telefonoController;
  late TextEditingController _correoController;
  late TextEditingController _alanubeActividadController;
  late String _entornoSeleccionado;
  bool _cargando = false;
  String? _logoUrl;
  bool _subiendoLlave = false;
  bool _llaveCargadaEnServidor = false;

  @override
  void initState() {
    super.initState();
    _usuarioController = TextEditingController(text: widget.negocio.usuarioApi ?? '');
    _pinController = TextEditingController(text: widget.negocio.pinLlave ?? '');
    _entornoSeleccionado = widget.negocio.entornoHacienda ?? 'STAGING';
    _passwordController = TextEditingController();
    _nombreComercialController = TextEditingController(text: widget.negocio.nombreComercial);
    _direccionController = TextEditingController(text: widget.negocio.direccion ?? '');
    _telefonoController = TextEditingController(text: widget.negocio.telefono ?? '');
    _correoController = TextEditingController(text: widget.negocio.correoHacienda ?? '');
    _alanubeActividadController = TextEditingController(text: widget.negocio.alanubeEconomicActivity ?? '');
    _logoUrl = widget.negocio.logoUrl;
    _llaveCargadaEnServidor = widget.negocio.llaveCriptografica != null;
  }

  Future<void> _cambiarLlave() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['p12'],
      withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
    );
    if (resultado == null || resultado.files.single.bytes == null) return;

    setState(() => _subiendoLlave = true);
    try {
      final response = await ApiService.uploadBytes(
        '/negocios/${widget.negocio.id}/',
        'llave_criptografica',
        resultado.files.single.bytes!,
        resultado.files.single.name,
      );
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() => _llaveCargadaEnServidor = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Llave criptográfica actualizada"), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al subir la llave: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoLlave = false);
    }
  }

  Future<void> _abrirLogo() async {
    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LogoScreen(
          titulo: "Logo del Negocio",
          endpoint: '/negocios/${widget.negocio.id}/',
          logoUrlInicial: _logoUrl,
        ),
      ),
    );
    if (actualizado == true && mounted) {
      try {
        final response = await ApiService.get('/negocios/${widget.negocio.id}/');
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          setState(() => _logoUrl = data['logo']);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    _nombreComercialController.dispose();
    _direccionController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _alanubeActividadController.dispose();
    super.dispose();
  }

  // 🌐 FUNCIÓN DE RED DIRECTA A TU VIEWSET PARCIAL DE DJANGO
  Future<void> _actualizarConfiguracionHacienda() async {
    setState(() {
      _cargando = true;
    });

    try {
      // Mapeamos los campos con guion bajo idénticos a tu models.py real
      final Map<String, dynamic> datosModificados = {
        'usuario_api': _usuarioController.text.trim(),
        'pin_llave': _pinController.text.trim(),
        'entorno_hacienda': _entornoSeleccionado,
        'nombre_comercial': _nombreComercialController.text.trim(),
        'direccion': _direccionController.text.trim(),
        'telefono': _telefonoController.text.trim(),
        'correo_hacienda': _correoController.text.trim(),
        'alanube_economic_activity': _alanubeActividadController.text.trim(),
      };

      if (_passwordController.text.isNotEmpty) {
        datosModificados['clave_api'] = _passwordController.text.trim();
      }

      final response = await ApiService.patch('/negocios/${widget.negocio.id}/', datosModificados);

      if (response.statusCode == 200) {
        widget.onGuardado?.call();
        // Si cambio el nombre comercial, el backend intenta sincronizarlo
        // con Hacienda (Alanube) para que tambien aparezca bien en el PDF
        // -- si eso falla, viene explicado aca en vez de quedar invisible
        // en los logs del servidor (mismo patron que el logo, ver
        // LogoScreen).
        final data = json.decode(utf8.decode(response.bodyBytes));
        final avisoAlanube = data['alanube_nombre_info'] as String?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(avisoAlanube ?? "✅ ¡Configuración guardada con éxito en Django!"),
            backgroundColor: (avisoAlanube != null && avisoAlanube.contains("no se pudo"))
                ? Colors.orange
                : Colors.green,
          ),
        );
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error al guardar: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Configuración General",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const Text("Administra las credenciales de comunicación con el Ministerio de Hacienda.",
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),

              // 👤 SECCIÓN 1: PERFIL
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("👤 Perfil de la Empresa", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: TextFormField(
                          controller: _nombreComercialController,
                          decoration: const InputDecoration(
                            labelText: "Nombre Comercial",
                            prefixIcon: Icon(Icons.business),
                            border: OutlineInputBorder(),
                            helperText: "El que se muestra en la app y en la factura al cliente.",
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.badge, color: Colors.grey),
                        title: const Text("Cédula"),
                        subtitle: Text(widget.negocio.cedula),
                      ),
                      ListTile(
                        leading: Icon(Icons.mark_email_read_outlined, color: AppColors.primary),
                        title: const Text("Correo para facturas de compra"),
                        subtitle: Text("${widget.negocio.cedula}@facturas.equilibracr.com"),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: "Copiar",
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: "${widget.negocio.cedula}@facturas.equilibracr.com"));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Correo copiado")),
                            );
                          },
                        ),
                        subtitleTextStyle: const TextStyle(fontWeight: FontWeight.w600),
                        // La ayuda de arriba explica para qué sirve, ya que no es un
                        // dato editable como el resto de esta pantalla.
                        isThreeLine: false,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          "Dale esta dirección a tus proveedores para que te manden la factura electrónica de tus compras directo por correo -- Equilibra la recibe sola y la deja lista para revisar en Compras.",
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: TextFormField(
                          controller: _direccionController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: "Dirección",
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: TextFormField(
                          controller: _telefonoController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: "Teléfono",
                            prefixIcon: Icon(Icons.phone_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: TextFormField(
                          controller: _correoController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: "Correo del Negocio",
                            helperText: "Se envía a Hacienda en cada factura electrónica",
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: TextFormField(
                          controller: _alanubeActividadController,
                          decoration: const InputDecoration(
                            labelText: "Actividad Económica (Alanube)",
                            helperText: "Código CIIU que exige Alanube al facturar (ej: 6820.0), no el código de 6 dígitos de Hacienda",
                            prefixIcon: Icon(Icons.work_outline),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (_logoUrl != null && _logoUrl!.isNotEmpty)
                              ? Image.network(
                                  _logoUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.image_outlined, color: Colors.grey),
                                )
                              : const Icon(Icons.image_outlined, color: Colors.grey),
                        ),
                        title: const Text("Logo del Negocio"),
                        subtitle: Text(_logoUrl != null && _logoUrl!.isNotEmpty ? "Logo cargado" : "Sin logo"),
                        trailing: TextButton(onPressed: _abrirLogo, child: const Text("Cambiar")),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 🔑 SECCIÓN 2: DATOS HACIENDA (ATV)
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🔑 Credenciales de Llave Criptográfica", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      const Divider(),
                      const SizedBox(height: 10),

                      DropdownButtonFormField<String>(
                        value: _entornoSeleccionado,
                        decoration: const InputDecoration(labelText: "Entorno de Facturación", border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'STAGING', child: Text("Pruebas / Sandbox (Hacienda)")),
                          DropdownMenuItem(value: 'PRODUCTION', child: Text("🔴 Producción / Facturación Real")),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _entornoSeleccionado = val!;
                          });
                        },
                      ),
                      const SizedBox(height: 15),

                      TextFormField(
                        controller: _usuarioController,
                        decoration: const InputDecoration(
                          labelText: "Usuario API de Hacienda (usuario_api)",
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: "Nueva Contraseña API (Dejar vacío para no cambiar)",
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder()
                        ),
                      ),
                      const SizedBox(height: 15),

                      TextFormField(
                        controller: _pinController,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: "PIN de la Llave Criptográfica (pin_llave)",
                          prefixIcon: Icon(Icons.password),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border)
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.file_present, color: AppColors.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Archivo de Llave (.p12)", style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(_llaveCargadaEnServidor
                                      ? "Llave cargada en el servidor"
                                      : "Ningún archivo seleccionado",
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                            _subiendoLlave
                                ? const SizedBox(
                                    height: 18, width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : TextButton(onPressed: _cambiarLlave, child: const Text("Cambiar")),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 25),

              // 💾 BOTÓN REPROGRAMADO CON SALTO DE VALIDACIÓN DIRECTO
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: _cargando
                      ? null
                      : () {
                    // Forzamos la ejecución directa ignorando bloqueos fantasma del estado del form
                    _actualizarConfiguracionHacienda();
                  },
                  child: _cargando
                      ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  )
                      : const Text("GUARDAR CONFIGURACIONES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}