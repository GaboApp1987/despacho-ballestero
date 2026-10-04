import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'cliente.dart';
import 'negocio.dart';

class CrearClienteScreen extends StatefulWidget {
  final Negocio negocio;
  /// Si se pasa, la pantalla edita este cliente en vez de crear uno nuevo.
  final Cliente? clienteExistente;

  const CrearClienteScreen({super.key, required this.negocio, this.clienteExistente});

  @override
  State<CrearClienteScreen> createState() => _CrearClienteScreenState();
}

class _CrearClienteScreenState extends State<CrearClienteScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto
  late final _nombreController = TextEditingController(text: widget.clienteExistente?.nombre ?? '');
  late final _cedulaController = TextEditingController(text: widget.clienteExistente?.cedula ?? '');
  late final _correoController = TextEditingController(text: widget.clienteExistente?.correo ?? '');
  late final _correoCopiaController = TextEditingController(text: widget.clienteExistente?.correoCopia ?? '');
  late final _telefonoController = TextEditingController(text: widget.clienteExistente?.telefono ?? '');
  late final _direccionController = TextEditingController(text: widget.clienteExistente?.direccion ?? '');
  late final _actividadController = TextEditingController(text: widget.clienteExistente?.codigoActividad ?? '');

  late String _tipoCedulaSeleccionada = widget.clienteExistente?.tipoCedula ?? '01';
  bool _isLoading = false;

  bool get _esEdicion => widget.clienteExistente != null;

  // ---- Búsqueda en Hacienda por cédula (GET /consultar-cedula/, ver
  // hacienda_cedula.py en el backend): al terminar de escribir la cédula
  // se cargan solos el nombre, el tipo y la actividad económica.
  Timer? _esperaBusqueda;
  bool _buscando = false;
  String? _cedulaConsultada;
  Map<String, dynamic>? _hacienda; // respuesta con encontrado=true
  String? _avisoBusqueda; // no encontrada / Hacienda caída
  // Lo que se cargó solo: si la persona lo cambió a mano, no se pisa.
  String? _nombreCargado;
  String? _actividadCargada;

  String get _soloDigitos => _cedulaController.text.replaceAll(RegExp(r'\D'), '');

  void _alCambiarCedula(String _) {
    _esperaBusqueda?.cancel();
    final digitos = _soloDigitos;
    if (digitos.length < 9 || digitos.length > 12 || digitos == _cedulaConsultada) return;
    _esperaBusqueda = Timer(const Duration(milliseconds: 700), _buscarEnHacienda);
  }

  Future<void> _buscarEnHacienda() async {
    final digitos = _soloDigitos;
    if (digitos.length < 9 || digitos.length > 12) {
      setState(() => _avisoBusqueda = "La cédula debe tener entre 9 y 12 dígitos.");
      return;
    }
    setState(() {
      _buscando = true;
      _avisoBusqueda = null;
      _cedulaConsultada = digitos;
    });
    try {
      final r = await ApiService.get('/consultar-cedula/?cedula=$digitos');
      final data = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (!mounted || digitos != _soloDigitos) return; // la cambiaron mientras tanto
      if (r.statusCode != 200) {
        setState(() {
          _hacienda = null;
          _avisoBusqueda = data['detail']?.toString() ?? "No se pudo consultar Hacienda.";
        });
        return;
      }
      if (data['encontrado'] != true) {
        setState(() {
          _hacienda = null;
          _avisoBusqueda = "Hacienda no tiene registrada esa cédula. Podés escribir el nombre a mano.";
        });
        return;
      }
      setState(() {
        _hacienda = data;
        final nombre = (data['nombre'] ?? '').toString();
        final actual = _nombreController.text.trim();
        if (nombre.isNotEmpty && (actual.isEmpty || actual == _nombreCargado)) {
          _nombreController.text = nombre;
          _nombreCargado = nombre;
        }
        final tipo = (data['tipo_cedula'] ?? '').toString();
        if (const ['01', '02', '03', '04'].contains(tipo)) _tipoCedulaSeleccionada = tipo;
        final principal = data['actividad_principal'] as Map<String, dynamic>?;
        final actividadActual = _actividadController.text.trim();
        if (principal != null && _esCiiu(principal['codigo']) && (actividadActual.isEmpty || actividadActual == _actividadCargada)) {
          _actividadController.text = principal['codigo'];
          _actividadCargada = principal['codigo'];
        }
      });
    } catch (e) {
      if (mounted) setState(() => _avisoBusqueda = "No se pudo consultar Hacienda ($e).");
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  bool _esCiiu(dynamic codigo) => RegExp(r'^[0-9]{4}\.[0-9]$').hasMatch('${codigo ?? ''}');

  List<Map<String, dynamic>> get _actividadesActivas => ((_hacienda?['actividades'] as List?) ?? [])
      .cast<Map<String, dynamic>>()
      .where((a) => a['activa'] == true && _esCiiu(a['codigo']))
      .toList();

  Widget _tarjetaHacienda() {
    if (_hacienda == null && _avisoBusqueda == null) return const SizedBox.shrink();
    if (_hacienda == null) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(_avisoBusqueda!, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
    }
    final h = _hacienda!;
    final detalles = [h['tipo_texto'], h['estado'], h['regimen']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ');
    final actividades = _actividadesActivas;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text("${h['nombre']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
            ],
          ),
          if (detalles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text("Datos de Hacienda: $detalles", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          if (actividades.length > 1) ...[
            const SizedBox(height: 10),
            Text("Actividad económica (tocá la que corresponda):", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in actividades)
                  ChoiceChip(
                    label: Text("${a['codigo']} · ${a['descripcion']}${a['principal'] == true ? ' (principal)' : ''}",
                        style: const TextStyle(fontSize: 12)),
                    selected: _actividadController.text.trim() == a['codigo'],
                    onSelected: (_) => setState(() {
                      _actividadController.text = a['codigo'];
                      _actividadCargada = a['codigo'];
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _esperaBusqueda?.cancel();
    _nombreController.dispose();
    _cedulaController.dispose();
    _correoController.dispose();
    _correoCopiaController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _actividadController.dispose();
    super.dispose();
  }

  Future<void> _guardarCliente() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> bodyPayload = {
        'negocio': widget.negocio.id,
        'nombre': _nombreController.text.trim(),
        'tipo_cedula': _tipoCedulaSeleccionada,
        'cedula': _cedulaController.text.trim(),
        'correo': _correoController.text.trim(),
        'correo_copia': _correoCopiaController.text.trim(),
        'telefono': _telefonoController.text.trim(),
        'direccion': _direccionController.text.trim(),
        'codigo_actividad': _actividadController.text.trim(),
      };

      final response = _esEdicion
          ? await ApiService.patch('/clientes/${widget.clienteExistente!.id}/', bodyPayload)
          : await ApiService.post('/clientes/', bodyPayload);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_esEdicion ? "Cliente actualizado con éxito" : "Cliente creado con éxito"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Retornamos true para recargar el listado
        }
      } else {
        String mensajeDetallado = "";
        try {
          final Map<String, dynamic> errorData =
          jsonDecode(utf8.decode(response.bodyBytes));
          errorData.forEach((key, value) {
            mensajeDetallado += "$key: $value\n";
          });
        } catch (_) {
          mensajeDetallado = utf8.decode(response.bodyBytes);
        }

        throw Exception("Error ${response.statusCode}:\n$mensajeDetallado");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? "Editar Cliente" : "Nuevo Cliente"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(_esEdicion ? Icons.edit : Icons.person_add, size: 50, color: AppColors.primary),
              const SizedBox(height: 20),

              // Cédula primero: al escribirla se buscan en Hacienda el
              // nombre, el tipo y la actividad económica.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _tipoCedulaSeleccionada,
                      decoration: const InputDecoration(
                        labelText: "Tipo",
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: '01', child: Text("Física")),
                        DropdownMenuItem(value: '02', child: Text("Jurídica")),
                        DropdownMenuItem(value: '03', child: Text("DIMEX")),
                        DropdownMenuItem(value: '04', child: Text("NITE")),
                      ],
                      onChanged: (v) => setState(() => _tipoCedulaSeleccionada = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cedulaController,
                      keyboardType: TextInputType.number,
                      onChanged: _alCambiarCedula,
                      onFieldSubmitted: (_) => _buscarEnHacienda(),
                      decoration: InputDecoration(
                        labelText: "Cédula",
                        helperText: "Se buscan solos el nombre y la actividad",
                        border: const OutlineInputBorder(),
                        suffixIcon: _buscando
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: "Buscar en Hacienda",
                                onPressed: _buscarEnHacienda,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              _tarjetaHacienda(),
              const SizedBox(height: 15),

              // Nombre Completo
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: "Nombre Completo",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                v == null || v.trim().isEmpty ? "El nombre es obligatorio" : null,
              ),
              const SizedBox(height: 15),

              // Correo Electrónico
              TextFormField(
                controller: _correoController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Correo Electrónico",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 15),

              // Otro destinatario que recibe copia de cada factura (ej. su contador).
              TextFormField(
                controller: _correoCopiaController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Otro correo (copia de facturas)",
                  helperText: "Opcional: también recibe cada factura que se le envíe",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.forward_to_inbox),
                ),
              ),
              const SizedBox(height: 15),

              // Teléfono
              TextFormField(
                controller: _telefonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Teléfono",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 15),

              // Dirección
              TextFormField(
                controller: _direccionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Dirección",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 15),

              // Actividad económica (Hacienda la exige en ciertas facturas,
              // ej. crédito fiscal a otro contribuyente)
              TextFormField(
                controller: _actividadController,
                decoration: const InputDecoration(
                  labelText: "Actividad Económica CIIU (opcional)",
                  helperText: "Formato CIIU con decimales, ej. 6820.0 -- Hacienda la pide para "
                      "clientes con crédito fiscal. NO es el código de 6 dígitos de Hacienda.",
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_center_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final formatoCiiu = RegExp(r'^[0-9]{4}\.[0-9]$');
                  return formatoCiiu.hasMatch(v.trim()) ? null : "Formato inválido, debe ser NNNN.N (ej. 6820.0)";
                },
              ),
              const SizedBox(height: 30),

              // Botón Guardar
              ElevatedButton(
                onPressed: _isLoading ? null : _guardarCliente,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
                    : Text(
                  _esEdicion ? "GUARDAR CAMBIOS" : "GUARDAR CLIENTE",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}