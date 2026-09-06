import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'addon.dart';
import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';

class AddonsScreen extends StatefulWidget {
  final Negocio negocio;
  const AddonsScreen({super.key, required this.negocio});

  @override
  State<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends State<AddonsScreen> {
  bool _cargando = true;
  List<Addon> _catalogo = [];
  Map<int, NegocioAddon> _contratados = {}; // addonId -> NegocioAddon

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final respuestas = await Future.wait([
        ApiService.get('/addons/'),
        ApiService.get('/negocio-addons/?negocio=${widget.negocio.id}'),
      ]);
      if (respuestas[0].statusCode == 200) {
        final data = json.decode(utf8.decode(respuestas[0].bodyBytes)) as List;
        _catalogo = data.map((j) => Addon.fromJson(j)).toList();
      }
      if (respuestas[1].statusCode == 200) {
        final data = json.decode(utf8.decode(respuestas[1].bodyBytes)) as List;
        final lista = data.map((j) => NegocioAddon.fromJson(j)).toList();
        _contratados = {for (var na in lista) na.addonId: na};
      }
    } catch (_) {
      // Si falla, se muestra el catálogo vacío.
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _alternarAddon(Addon addon, bool activar) async {
    final existente = _contratados[addon.id];
    try {
      final response = existente == null
          ? await ApiService.post('/negocio-addons/', {'negocio': widget.negocio.id, 'addon': addon.id, 'activo': activar})
          : await ApiService.patch('/negocio-addons/${existente.id}/', {'activo': activar});
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cargarDatos();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo actualizar: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _registrarEnvio(NegocioAddon negocioAddon) async {
    final destinatarioCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Registrar mensaje enviado"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Se sumará ${formatearColones(negocioAddon.precioPorMensaje)} al consumo de este mes de \"${negocioAddon.addonNombre}\".",
            ),
            const SizedBox(height: 12),
            TextField(
              controller: destinatarioCtrl,
              decoration: const InputDecoration(labelText: "Destinatario (opcional)", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Registrar")),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final response = await ApiService.post('/negocio-addons/${negocioAddon.id}/registrar-envio/', {
        'destinatario': destinatarioCtrl.text.trim(),
      });
      if (response.statusCode == 201) {
        _cargarDatos();
      } else {
        final detalle = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? utf8.decode(response.bodyBytes);
        throw Exception(detalle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo registrar: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSubtle,
      child: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Icon(Icons.extension_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text("Add-ons", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos, tooltip: "Actualizar"),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  "Funciones opcionales que se cobran por mensaje enviado, además de tu plan base.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (_catalogo.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("No hay add-ons disponibles todavía.", style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._catalogo.map((addon) => _tarjetaAddon(addon)),
              ],
            ),
    );
  }

  Widget _tarjetaAddon(Addon addon) {
    final contratado = _contratados[addon.id];
    final activo = contratado?.activo ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.chat_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(addon.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(addon.descripcion, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: activo,
                activeColor: AppColors.primary,
                onChanged: (v) => _alternarAddon(addon, v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Precio: ${formatearColones(addon.precioPorMensaje)} por mensaje",
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
                if (activo && contratado != null) ...[
                  Text(
                    "${contratado.mensajesEsteMes} mensaje(s) este mes · ${formatearColones(contratado.costoEsteMes)}",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => _registrarEnvio(contratado),
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text("Registrar envío", style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
