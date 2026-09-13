import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'certificaciones_screen.dart';

/// Punto de entrada de "Certificaciones" en la sidebar del contador: un
/// menú con los distintos documentos que puede emitir (certificación de
/// ingresos ya armada; atestiguamientos y flujo de caja proyectado
/// pendientes de formato real -- ver _ProximamenteScreen).
class DocumentosContadorScreen extends StatelessWidget {
  const DocumentosContadorScreen({super.key});

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
            subtitulo: "Próximamente",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const _ProximamenteScreen(titulo: "Atestiguamientos")),
            ),
          ),
          const SizedBox(height: 12),
          _opcion(
            context,
            icono: Icons.trending_up,
            titulo: "Flujo de Caja Proyectado",
            subtitulo: "Próximamente",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const _ProximamenteScreen(titulo: "Flujo de Caja Proyectado")),
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
        trailing: const Icon(Icons.chevron_right, color: TemaContador.acento),
        onTap: onTap,
      ),
    );
  }
}

class _ProximamenteScreen extends StatelessWidget {
  final String titulo;

  const _ProximamenteScreen({required this.titulo});

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
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemaContador.textoFuerte)),
        iconTheme: const IconThemeData(color: TemaContador.textoFuerte),
        backgroundColor: TemaContador.fondo,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text("$titulo -- todavía en construcción", style: const TextStyle(fontWeight: FontWeight.bold, color: TemaContador.textoFuerte)),
              const SizedBox(height: 8),
              const Text(
                "Compartí un ejemplo real de este documento (igual que hiciste con la certificación de ingresos) para armarlo con el formato exacto que usás.",
                textAlign: TextAlign.center,
                style: TextStyle(color: TemaContador.textoTenue, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
