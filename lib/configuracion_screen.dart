import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'theme/app_theme.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'negocio.dart';
import 'api_service.dart';
import 'logo_screen.dart';
import 'actividad_economica.dart';
import 'ubicacion_cr.dart';

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
  late bool _avisosPorCorreo;
  bool _cargando = false;
  String? _logoUrl;
  bool _subiendoLlave = false;
  bool _llaveCargadaEnServidor = false;
  // Actividades económicas ADICIONALES a la principal (arriba, Actividad
  // Económica de Alanube) -- un negocio puede tener varias registradas ante
  // Hacienda y elegir cuál aplica al facturar cada venta (ver el selector
  // en FormularioFactura).
  List<ActividadEconomica> _actividades = [];
  bool _cargandoActividades = true;

  // Ubicación exigida por Hacienda desde la v4.4 (Provincia/Cantón/Distrito
  // como código, ver Negocio en el backend) -- se muestra por nombre para
  // que el negocio elija sin tener que saber el código de memoria, pero lo
  // que se guarda y se manda en el XML es el código.
  List<ProvinciaCR> _ubicaciones = [];
  bool _cargandoUbicaciones = true;
  String? _provinciaSel;
  String? _cantonSel;
  String? _distritoSel;

  // Numeración de comprobantes -- para un negocio que ya facturaba
  // electrónicamente con OTRO sistema antes de pasarse a Equilibra: si no
  // adelanta el contador acá, Equilibra reusa un número que Hacienda ya
  // tiene archivado y lo rechaza (ver NegocioViewSet.ajustar_numeracion).
  final _consecutivoFacturaController = TextEditingController();
  final _consecutivoTiqueteController = TextEditingController();
  final _consecutivoNotaCreditoController = TextEditingController();
  int _ultimoConsecutivoFactura = 0;
  int _ultimoConsecutivoTiquete = 0;
  int _ultimoConsecutivoNotaCredito = 0;
  final Set<String> _ajustandoNumeracion = {};

  @override
  void initState() {
    super.initState();
    _cargarActividades();
    _cargarUbicaciones();
    _ultimoConsecutivoFactura = widget.negocio.ultimoConsecutivoFactura;
    _ultimoConsecutivoTiquete = widget.negocio.ultimoConsecutivoTiquete;
    _ultimoConsecutivoNotaCredito = widget.negocio.ultimoConsecutivoNotaCredito;
    _usuarioController = TextEditingController(text: widget.negocio.usuarioApi ?? '');
    _pinController = TextEditingController(text: widget.negocio.pinLlave ?? '');
    _entornoSeleccionado = widget.negocio.entornoHacienda ?? 'STAGING';
    _avisosPorCorreo = widget.negocio.avisosPorCorreo;
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

  Future<void> _cargarActividades() async {
    setState(() => _cargandoActividades = true);
    try {
      final response = await ApiService.get('/actividades-economicas/?negocio=${widget.negocio.id}');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _actividades = data.map((j) => ActividadEconomica.fromJson(j)).toList();
            _cargandoActividades = false;
          });
        }
      } else if (mounted) {
        setState(() => _cargandoActividades = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoActividades = false);
    }
  }

  Future<void> _cargarUbicaciones() async {
    final ubicaciones = await UbicacionCR.cargar();
    if (!mounted) return;
    setState(() {
      _ubicaciones = ubicaciones;
      _provinciaSel = widget.negocio.provincia;
      _cantonSel = widget.negocio.canton;
      _distritoSel = widget.negocio.distrito;
      _cargandoUbicaciones = false;
    });
  }

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

  void _mostrarFormularioActividad() {
    final codigoCtrl = TextEditingController();
    final codigoAlanubeCtrl = TextEditingController();
    final descripcionCtrl = TextEditingController();
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Nueva Actividad Económica"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codigoCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: "Código Actividad (Hacienda) *",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codigoAlanubeCtrl,
                    decoration: const InputDecoration(
                      labelText: "Código CIIU (Alanube, ej: 6820.0)",
                      helperText: "Opcional -- si se deja vacío, se intenta usar el código de Hacienda tal cual",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descripcionCtrl,
                    decoration: const InputDecoration(
                      labelText: "Descripción (opcional)",
                      helperText: "Solo para identificarla en la app, ej: \"Venta de ropa\"",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (codigoCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Ingrese el código de actividad.")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.post('/actividades-economicas/', {
                          'negocio': widget.negocio.id,
                          'codigo_actividad': codigoCtrl.text.trim(),
                          'alanube_economic_activity': codigoAlanubeCtrl.text.trim(),
                          'descripcion': descripcionCtrl.text.trim(),
                        });
                        if (response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarActividades();
                        } else {
                          throw Exception(utf8.decode(response.bodyBytes));
                        }
                      } catch (e) {
                        setStateDialog(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error: $e")));
                        }
                      }
                    },
              child: guardando
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _borrarActividad(ActividadEconomica actividad) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar actividad?"),
        content: Text("Se eliminará \"${actividad.etiqueta}\". Las facturas ya emitidas con esta actividad no cambian."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Borrar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final response = await ApiService.delete('/actividades-economicas/${actividad.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarActividades();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo borrar: $e")));
      }
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
    _consecutivoFacturaController.dispose();
    _consecutivoTiqueteController.dispose();
    _consecutivoNotaCreditoController.dispose();
    super.dispose();
  }

  static const Map<String, String> _etiquetaTipoNumeracion = {
    'factura': 'Factura',
    'tiquete': 'Tiquete Electrónico',
    'nota_credito': 'Nota de Crédito',
  };

  Future<void> _ajustarNumeracion(String tipo, TextEditingController controller) async {
    final valor = controller.text.trim();
    if (valor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingresá el último consecutivo usado.")),
      );
      return;
    }
    setState(() => _ajustandoNumeracion.add(tipo));
    try {
      final response = await ApiService.post(
        '/negocios/${widget.negocio.id}/ajustar-numeracion/',
        {'tipo': tipo, 'ultimo_consecutivo': valor},
      );
      final datos = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200) {
        setState(() {
          final nuevoValor = datos['valor'] as int;
          switch (tipo) {
            case 'factura':
              _ultimoConsecutivoFactura = nuevoValor;
              break;
            case 'tiquete':
              _ultimoConsecutivoTiquete = nuevoValor;
              break;
            case 'nota_credito':
              _ultimoConsecutivoNotaCredito = nuevoValor;
              break;
          }
          controller.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Numeración de ${_etiquetaTipoNumeracion[tipo]} actualizada -- el próximo comprobante va a salir con el número siguiente."),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(datos['detail'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo actualizar: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _ajustandoNumeracion.remove(tipo));
    }
  }

  Widget _filaNumeracion(String tipo, int valorActual, TextEditingController controller) {
    final ajustando = _ajustandoNumeracion.contains(tipo);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: _etiquetaTipoNumeracion[tipo],
              helperText: "Actual en Equilibra: $valorActual",
              hintText: "Ej: 00100002010000000004 o solo 4",
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ajustando
                ? const SizedBox(height: 36, width: 36, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                : ElevatedButton(
                    onPressed: () => _ajustarNumeracion(tipo, controller),
                    child: const Text("Actualizar"),
                  ),
          ),
        ],
      ),
    );
  }

  /// Revisa (sin emitir nada) llave, PIN, vigencia, cédula de la llave y
  /// usuario/clave de la API -- lo que antes se descubría recién cuando la
  /// primera factura fallaba. Usa lo GUARDADO: si hay cambios sin guardar,
  /// hay que guardar primero.
  Future<void> _probarConexionHacienda() async {
    setState(() => _cargando = true);
    try {
      final res = ApiService.verificar(await ApiService.post('/negocios/${widget.negocio.id}/verificar-hacienda/', {}));
      final data = json.decode(utf8.decode(res.bodyBytes));
      final pasos = (data['pasos'] as List).cast<Map>();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(data['listo'] == true ? "Todo listo para facturar" : "Hay cosas por corregir"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in pasos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p['ok'] == true ? Icons.check_circle : Icons.error,
                        color: p['ok'] == true ? Colors.green : Colors.red),
                    title: Text(p['paso'].toString()),
                    subtitle: Text(p['detalle'].toString()),
                  ),
                const SizedBox(height: 4),
                const Text("Se revisa lo que ya está guardado: si cambiaste algo, guardá primero.",
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo probar la conexión: $e")));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
        'provincia': _provinciaSel ?? '',
        'canton': _cantonSel ?? '',
        'distrito': _distritoSel ?? '',
        'telefono': _telefonoController.text.trim(),
        'avisos_por_correo': _avisosPorCorreo,
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
                            helperText: "Señas exactas (ej: 200m norte del parque) -- la provincia/cantón/distrito van abajo",
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_cargandoUbicaciones)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Ubicación exigida por Hacienda",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 8),
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
                      SwitchListTile(
                        value: _avisosPorCorreo,
                        onChanged: (v) => setState(() => _avisosPorCorreo = v),
                        title: const Text("Avisos por correo"),
                        subtitle: const Text(
                          "Certificado por vencer, compras por aceptar ante Hacienda, recordatorio de IVA y resumen semanal los lunes",
                        ),
                        secondary: const Icon(Icons.notifications_active_outlined),
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
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text("Otras actividades del negocio",
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                            ),
                            TextButton.icon(
                              onPressed: _mostrarFormularioActividad,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text("Agregar"),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "Si el negocio tiene más de una actividad registrada ante Hacienda, agregalas acá -- "
                          "al crear una Factura vas a poder elegir cuál aplica a esa venta.",
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_cargandoActividades)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_actividades.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text("Sin otras actividades agregadas.", style: TextStyle(color: Colors.grey[500])),
                        )
                      else
                        ..._actividades.map((a) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.work_outline),
                              title: Text(a.codigoActividad),
                              subtitle: Text(
                                [
                                  if (a.descripcion.isNotEmpty) a.descripcion,
                                  if ((a.alanubeEconomicActivity ?? '').isNotEmpty) "Alanube: ${a.alanubeEconomicActivity}",
                                ].join(" · "),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: "Borrar",
                                onPressed: () => _borrarActividad(a),
                              ),
                            )),
                      const Divider(),
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

              // 🔢 NUMERACIÓN DE COMPROBANTES (migración desde otro sistema)
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🔢 Numeración de Comprobantes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text(
                          "Si este negocio ya facturaba electrónicamente con OTRO sistema antes de pasarse a Equilibra, indicá acá el último "
                          "consecutivo que usó de cada tipo -- así Equilibra arranca después de ese número y nunca choca con uno que Hacienda "
                          "ya tenga archivado (podés pegar el consecutivo completo de 20 dígitos tal como sale impreso, o solo el número).",
                          style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            _filaNumeracion('factura', _ultimoConsecutivoFactura, _consecutivoFacturaController),
                            _filaNumeracion('tiquete', _ultimoConsecutivoTiquete, _consecutivoTiqueteController),
                            _filaNumeracion('nota_credito', _ultimoConsecutivoNotaCredito, _consecutivoNotaCreditoController),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
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
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text("PROBAR CONEXIÓN CON HACIENDA"),
                  onPressed: _cargando ? null : _probarConexionHacienda,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}