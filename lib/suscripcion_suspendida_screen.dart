import 'package:flutter/material.dart';
import 'api_service.dart';
import 'login.dart';
import 'onvo_cobro_automatico_screen.dart';
import 'theme/app_theme.dart';

/// Se muestra en vez de dejar entrar cuando MiPerfilView responde 402 (la
/// suscripción del negocio o despacho está suspendida por falta de pago).
/// A diferencia del comportamiento anterior (cerrar sesión y mostrar un
/// SnackBar), acá se mantiene la sesión para que el propio dueño pueda
/// reactivarse pagando de nuevo -- sin depender de que el administrador de
/// la plataforma lo haga por él.
class SuscripcionSuspendidaScreen extends StatelessWidget {
  final String tipo; // 'negocio' o 'despacho'
  final int? suscripcionId;
  final String nombre;
  final String motivo;

  const SuscripcionSuspendidaScreen({
    super.key,
    required this.tipo,
    required this.suscripcionId,
    required this.nombre,
    required this.motivo,
  });

  Future<void> _reactivar(BuildContext context) async {
    if (suscripcionId == null) return;
    final activado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OnvoCobroAutomaticoScreen(
          tipo: tipo,
          suscripcionId: suscripcionId!,
          nombreTitular: nombre,
        ),
      ),
    );
    if (activado == true && context.mounted) {
      // Vuelve al login, que al restaurar la sesión ya va a ver la
      // suscripción activa y va a entrar directo a la pantalla normal.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    await ApiService.logout();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pause_circle_outline, size: 72, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    nombre,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(motivo, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 28),
                  if (suscripcionId != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.credit_card),
                      label: const Text("Reactivar pagando de nuevo"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () => _reactivar(context),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _cerrarSesion(context),
                    child: const Text("Cerrar sesión"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
