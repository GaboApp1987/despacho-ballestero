import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';

/// Pantalla genérica para subir/reemplazar el logo de un Negocio, Socio
/// (contador) o Despacho — los tres usan el mismo patrón de API
/// (PATCH multipart al endpoint de detalle con el campo 'logo').
class LogoScreen extends StatefulWidget {
  final String titulo;
  final String endpoint; // ej: '/negocios/5/', '/socios/3/', '/despachos/1/'
  final String? logoUrlInicial;

  const LogoScreen({
    super.key,
    required this.titulo,
    required this.endpoint,
    this.logoUrlInicial,
  });

  @override
  State<LogoScreen> createState() => _LogoScreenState();
}

class _LogoScreenState extends State<LogoScreen> {
  Uint8List? _bytesSeleccionados;
  String? _nombreSeleccionado;
  String? _logoUrl;
  bool _cargandoInicial = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _logoUrl = widget.logoUrlInicial;
    _cargarActual();
  }

  Future<void> _cargarActual() async {
    if (widget.logoUrlInicial != null) {
      setState(() => _cargandoInicial = false);
      return;
    }
    try {
      final response = await ApiService.get(widget.endpoint);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) setState(() => _logoUrl = data['logo']);
      }
    } catch (_) {
      // Si falla, simplemente no se precarga el logo actual.
    } finally {
      if (mounted) setState(() => _cargandoInicial = false);
    }
  }

  Future<void> _elegirImagen() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // fuerza a traer los bytes: en Web no existe una ruta real.
    );
    if (resultado != null && resultado.files.single.bytes != null) {
      setState(() {
        _bytesSeleccionados = resultado.files.single.bytes;
        _nombreSeleccionado = resultado.files.single.name;
      });
    }
  }

  Future<void> _guardar() async {
    if (_bytesSeleccionados == null) return;
    setState(() => _guardando = true);
    try {
      final response = await ApiService.uploadBytes(widget.endpoint, 'logo', _bytesSeleccionados!, _nombreSeleccionado ?? 'logo.png');
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _logoUrl = data['logo'];
            _bytesSeleccionados = null;
          });
          // Para el Negocio, el backend intenta sincronizar el logo con
          // Hacienda (Alanube) para que aparezca tambien en el PDF de las
          // facturas -- si esa sincronizacion falla, antes quedaba solo en
          // los logs del servidor y nadie se enteraba. Ahora, si vino ese
          // aviso en la respuesta, se lo mostramos aca en vez del mensaje
          // generico de "Logo actualizado".
          final avisoAlanube = data['alanube_logo_info'] as String?;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(avisoAlanube ?? "Logo actualizado"),
              backgroundColor: (avisoAlanube != null && avisoAlanube.contains("no se pudo"))
                  ? Colors.orange
                  : Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al subir el logo: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _cargandoInicial
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _bytesSeleccionados != null
                            ? Image.memory(_bytesSeleccionados!, fit: BoxFit.contain)
                            : (_logoUrl != null && _logoUrl!.isNotEmpty)
                                ? Image.network(
                                    _logoUrl!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.broken_image_outlined, size: 64, color: Colors.grey),
                                  )
                                : const Icon(Icons.image_outlined, size: 64, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _guardando ? null : _elegirImagen,
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text("Elegir Imagen"),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_guardando || _bytesSeleccionados == null) ? null : _guardar,
                          icon: _guardando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: Text(_guardando ? "Guardando..." : "Guardar Logo"),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
