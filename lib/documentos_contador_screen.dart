import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'certificaciones_screen.dart';
import 'atestiguamientos_screen.dart';
import 'flujo_caja_screen.dart';
import 'solicitudes_certificacion_screen.dart';
import 'descarga_navegador_stub.dart' if (dart.library.html) 'descarga_navegador_web.dart';

/// Descarga cualquiera de los documentos del contador (certificación de
/// ingresos, atestiguamiento, flujo de caja) en PDF o Word -- comparten el
/// mismo patrón de endpoint /{recurso}/{id}/{formato}/.
Future<void> descargarDocumento(BuildContext context, String endpointBase, int id, String formato, String prefijoArchivo) async {
  try {
    final response = await ApiService.get('/$endpointBase/$id/$formato/');
    if (response.statusCode == 200) {
      final nombreArchivo = "${prefijoArchivo}_$id.${formato == 'pdf' ? 'pdf' : 'docx'}";
      if (kIsWeb) {
        descargarBytesEnNavegador(response.bodyBytes, nombreArchivo);
      } else {
        await FilePicker.platform.saveFile(fileName: nombreArchivo, bytes: response.bodyBytes);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo descargar (HTTP ${response.statusCode}).")));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo descargar: $e")));
    }
  }
}

/// Punto de entrada de "Certificaciones" en la sidebar del contador: un
/// menú con los distintos documentos que puede emitir.
class DocumentosContadorScreen extends StatefulWidget {
  const DocumentosContadorScreen({super.key});

  @override
  State<DocumentosContadorScreen> createState() => _DocumentosContadorScreenState();
}

class _DocumentosContadorScreenState extends State<DocumentosContadorScreen> {
  int? _pendientes;

  @override
  void initState() {
    super.initState();
    _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    try {
      final r = await ApiService.get('/solicitudes-certificacion/?estado=pendiente');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        if (mounted) setState(() => _pendientes = data.length);
      }
    } catch (_) {}
  }

  Future<void> _abrirSolicitudes() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => const SolicitudesCertificacionScreen()));
    _cargarPendientes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaContador.fondo,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: TemaContador.textoFuerte),
          tooltip: "Volver",
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Certificaciones", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _opcion(
            context,
            icono: Icons.mark_email_unread_outlined,
            titulo: "Solicitudes de Certificación",
            subtitulo: "Pedidos que tus clientes te mandaron desde tu link público, sin login.",
            badge: _pendientes != null && _pendientes! > 0 ? _pendientes.toString() : null,
            onTap: _abrirSolicitudes,
          ),
          const SizedBox(height: 12),
          _opcion(
            context,
            icono: Icons.badge_outlined,
            titulo: "Certificación de Ingresos",
            subtitulo: "Carta de certificación + hoja de trabajo de 12 meses, con extracción por IA.",
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CertificacionesScreen())),
          ),
          const SizedBox(height: 12),
          _opcion(
            context,
            icono: Icons.verified_outlined,
            titulo: "Atestiguamientos",
            subtitulo: "Informe de certificación genérico (Circular 02-2022 del Colegio de CPA).",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AtestiguamientosScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _opcion(
            context,
            icono: Icons.trending_up,
            titulo: "Flujo de Caja Proyectado",
            subtitulo: "Información financiera prospectiva (NITA 3400 / Circular 21-2010).",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const FlujoCajaScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _opcion(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Card(
      color: TemaContador.superficie,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: TemaContador.borde)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(backgroundColor: TemaContador.acento.withOpacity(0.12), child: Icon(icono, color: TemaContador.acento)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, color: TemaContador.textoFuerte)),
        subtitle: Text(subtitulo, style: const TextStyle(color: TemaContador.textoTenue, fontSize: 12.5)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right, color: TemaContador.acento),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

