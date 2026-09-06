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
  late final _telefonoController = TextEditingController(text: widget.clienteExistente?.telefono ?? '');
  late final _direccionController = TextEditingController(text: widget.clienteExistente?.direccion ?? '');
  late final _actividadController = TextEditingController(text: widget.clienteExistente?.codigoActividad ?? '');

  late String _tipoCedulaSeleccionada = widget.clienteExistente?.tipoCedula ?? '01';
  bool _isLoading = false;

  bool get _esEdicion => widget.clienteExistente != null;

  @override
  void dispose() {
    _nombreController.dispose();
    _cedulaController.dispose();
    _correoController.dispose();
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

              // Tipo de Cédula y Número
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
                      decoration: const InputDecoration(
                        labelText: "Cédula",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
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