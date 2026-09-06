import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'negocio.dart';

class Empleado {
  final int id;
  final String nombre;
  final String rol; // 'cajero' | 'completo'
  final bool activo;

  Empleado({required this.id, required this.nombre, required this.rol, required this.activo});

  factory Empleado.fromJson(Map<String, dynamic> json) {
    return Empleado(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      rol: json['rol'] ?? 'cajero',
      activo: json['activo'] == true,
    );
  }
}

/// Gestion de logins de empleados (cajero / acceso completo) de un negocio
/// -- exclusivo del dueño real (ver SoloDuenoDelNegocioMixin en el backend).
class EmpleadosScreen extends StatefulWidget {
  final Negocio negocio;
  const EmpleadosScreen({super.key, required this.negocio});

  @override
  State<EmpleadosScreen> createState() => _EmpleadosScreenState();
}

class _EmpleadosScreenState extends State<EmpleadosScreen> {
  bool _isLoading = true;
  List<Empleado> _empleados = [];

  @override
  void initState() {
    super.initState();
    _cargarEmpleados();
  }

  Future<void> _cargarEmpleados() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/empleados/?negocio=${widget.negocio.id}');
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as List;
        setState(() {
          _empleados = data.map((j) => Empleado.fromJson(j)).toList();
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar empleados: $e")));
      }
    }
  }

  void _mostrarDialogoNuevoEmpleado() {
    final nombreCtrl = TextEditingController();
    final usuarioCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String rol = 'cajero';
    bool guardando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Nuevo Empleado"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: "Nombre", border: OutlineInputBorder()),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usuarioCtrl,
                  decoration: const InputDecoration(labelText: "Usuario (para iniciar sesión)", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Contraseña", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: rol,
                  decoration: const InputDecoration(labelText: "Rol", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'cajero', child: Text("Cajero (solo facturar/cotizar)")),
                    DropdownMenuItem(value: 'completo', child: Text("Acceso Completo")),
                  ],
                  onChanged: (v) => setStateDialog(() => rol = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty || usuarioCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Complete todos los campos")));
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.post('/empleados/', {
                          'negocio': widget.negocio.id,
                          'nombre': nombreCtrl.text.trim(),
                          'username': usuarioCtrl.text.trim(),
                          'password': passwordCtrl.text,
                          'rol': rol,
                        });
                        if (response.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _cargarEmpleados();
                        } else {
                          final data = json.decode(utf8.decode(response.bodyBytes));
                          String mensaje = "Error desconocido";
                          if (data is Map) {
                            mensaje = data.values.first is List ? data.values.first.join(' ') : data.values.first.toString();
                          }
                          throw Exception(mensaje);
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
                  : const Text("Crear"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _alternarActivo(Empleado empleado) async {
    try {
      final response = await ApiService.patch('/empleados/${empleado.id}/', {'activo': !empleado.activo});
      if (response.statusCode == 200) {
        _cargarEmpleados();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _eliminarEmpleado(Empleado empleado) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar Empleado"),
        content: Text("¿Seguro que querés eliminar el acceso de \"${empleado.nombre}\"? Esto borra su login permanentemente."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final response = await ApiService.delete('/empleados/${empleado.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarEmpleados();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text("Empleados", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _mostrarDialogoNuevoEmpleado,
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: const Text("Nuevo Empleado", style: TextStyle(color: Colors.black)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _empleados.isEmpty
                    ? const Center(child: Text("No hay empleados registrados todavía."))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _empleados.length,
                        itemBuilder: (context, index) {
                          final e = _empleados[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withOpacity(0.12),
                                child: Icon(e.rol == 'completo' ? Icons.verified_user_outlined : Icons.point_of_sale_outlined, color: AppColors.primary),
                              ),
                              title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(e.rol == 'completo' ? "Acceso Completo" : "Cajero", style: TextStyle(color: Colors.grey[600])),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: e.activo,
                                    onChanged: (_) => _alternarActivo(e),
                                    activeThumbColor: AppColors.primary,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: "Eliminar",
                                    onPressed: () => _eliminarEmpleado(e),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
