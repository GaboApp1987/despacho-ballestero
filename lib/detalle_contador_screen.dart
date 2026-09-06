import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'avatar_logo.dart';
import 'negocio.dart';
import 'resumen_fiscal_screen.dart';
import 'socio.dart';

/// Lo que ve el dueño del despacho al entrar a uno de sus contadores: sus
/// datos, la cartera de clientes que le pertenecen (filtrada, no mezclada
/// con la de los demás contadores) y accesos para editar su info o
/// resetearle la contraseña.
class DetalleContadorScreen extends StatefulWidget {
  final Socio socio;
  const DetalleContadorScreen({super.key, required this.socio});

  @override
  State<DetalleContadorScreen> createState() => _DetalleContadorScreenState();
}

class _DetalleContadorScreenState extends State<DetalleContadorScreen> {
  late Socio _socio;
  bool _cargando = true;
  List<Negocio> _negocios = [];

  @override
  void initState() {
    super.initState();
    _socio = widget.socio;
    _cargarNegocios();
  }

  Future<void> _cargarNegocios() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final response = await ApiService.get('/negocios/?socio=${_socio.id}');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _negocios = data.map((j) => Negocio.fromJson(j)).toList();
            _cargando = false;
          });
        }
      } else {
        if (mounted) setState(() => _cargando = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar clientes: $e")));
      }
    }
  }

  void _mostrarFormularioEditar() {
    final nombreCtrl = TextEditingController(text: _socio.nombre);
    final emailCtrl = TextEditingController(text: _socio.email);
    final passwordCtrl = TextEditingController();
    bool cambiarPassword = false;
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Editar Contador"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: "Nombre *", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: "Correo *", border: OutlineInputBorder()),
                  ),
                  const Divider(height: 30),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Resetear contraseña", style: TextStyle(fontSize: 14)),
                    subtitle: const Text("Define una nueva contraseña de acceso para este contador", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    value: cambiarPassword,
                    onChanged: (v) => setStateDialog(() => cambiarPassword = v),
                  ),
                  if (cambiarPassword) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "Nueva contraseña *", border: OutlineInputBorder()),
                    ),
                  ],
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
                      if (nombreCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Complete nombre y correo")),
                        );
                        return;
                      }
                      if (cambiarPassword && passwordCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Ingrese la nueva contraseña")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.patch('/socios/${_socio.id}/', {
                          'nombre': nombreCtrl.text.trim(),
                          'email': emailCtrl.text.trim(),
                          if (cambiarPassword) 'password': passwordCtrl.text,
                        });
                        if (response.statusCode == 200) {
                          final data = json.decode(utf8.decode(response.bodyBytes));
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            setState(() => _socio = Socio.fromJson(data));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(cambiarPassword ? "Datos y contraseña actualizados" : "Datos actualizados")),
                            );
                          }
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

  Future<void> _mostrarDialogoReasignar() async {
    if (_negocios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Este contador no tiene clientes para reasignar.")),
      );
      return;
    }

    List<Socio> otros = [];
    try {
      final response = await ApiService.get('/socios/');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        otros = data.map((j) => Socio.fromJson(j)).where((s) => s.id != _socio.id).toList();
      }
    } catch (_) {
      // si falla, otros se queda vacío y se avisa abajo
    }
    if (!mounted) return;
    if (otros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay otro contador en el despacho para reasignar los clientes.")),
      );
      return;
    }

    final Set<int> seleccionados = _negocios.map((n) => n.id).toSet();
    Socio? destino;
    bool guardando = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Reasignar Cartera"),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Selecciona los clientes a traspasar (por defecto, toda la cartera):", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  ..._negocios.map((n) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(n.nombreComercial),
                        value: seleccionados.contains(n.id),
                        onChanged: (v) => setStateDialog(() {
                          if (v == true) {
                            seleccionados.add(n.id);
                          } else {
                            seleccionados.remove(n.id);
                          }
                        }),
                      )),
                  const Divider(height: 24),
                  DropdownButtonFormField<Socio>(
                    value: destino,
                    decoration: const InputDecoration(labelText: "Contador destino *", border: OutlineInputBorder()),
                    items: otros.map((s) => DropdownMenuItem(value: s, child: Text(s.nombre))).toList(),
                    onChanged: (v) => setStateDialog(() => destino = v),
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
                      if (seleccionados.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Seleccione al menos un cliente.")),
                        );
                        return;
                      }
                      if (destino == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Seleccione el contador destino.")),
                        );
                        return;
                      }
                      setStateDialog(() => guardando = true);
                      try {
                        final response = await ApiService.post('/socios/${_socio.id}/reasignar-negocios/', {
                          'negocio_ids': seleccionados.toList(),
                          'nuevo_socio_id': destino!.id,
                        });
                        if (response.statusCode == 200) {
                          final cantidad = seleccionados.length;
                          final nombreDestino = destino!.nombre;
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("$cantidad cliente(s) reasignado(s) a $nombreDestino")),
                            );
                            _cargarNegocios();
                          }
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
                  : const Text("Reasignar"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEliminar() async {
    if (_negocios.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("No se puede eliminar"),
          content: Text(
            "Este contador tiene ${_negocios.length} cliente(s) asignados. Reasígnalos a otro contador antes de eliminarlo.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _mostrarDialogoReasignar();
              },
              child: const Text("Reasignar ahora"),
            ),
          ],
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Eliminar contador?"),
        content: Text("Se eliminará a \"${_socio.nombre}\" y su acceso a la app. Esta acción no se puede deshacer."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final response = await ApiService.delete('/socios/${_socio.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else {
        final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? utf8.decode(response.bodyBytes);
        throw Exception(detalle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo eliminar: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: "Volver",
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_socio.nombre),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: "Reasignar cartera",
            onPressed: _mostrarDialogoReasignar,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: "Editar contador",
            onPressed: _mostrarFormularioEditar,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarNegocios),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: "Eliminar contador",
            onPressed: _confirmarEliminar,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                avatarConLogo(logoUrl: _socio.logoUrl, icono: Icons.badge_outlined, radius: 26, color: AppColors.primary, fondo: AppColors.primary.withOpacity(0.12), nombre: _socio.nombre),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_socio.nombre, style: TextStyle(color: AppColors.textStrong, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(_socio.email, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              "Clientes a cargo (${_negocios.length})",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textStrong),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _negocios.isEmpty
                    ? const Center(child: Text("Este contador todavía no tiene clientes asignados.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _negocios.length,
                        itemBuilder: (context, index) {
                          final n = _negocios[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: avatarConLogo(logoUrl: n.logoUrl, icono: Icons.business_center, nombre: n.nombreComercial),
                              title: Text(n.nombreComercial, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("Cédula: ${n.cedula}"),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => ResumenFiscalNegocioScreen(negocio: n)),
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
