import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'instalar_app_interop_stub.dart' if (dart.library.js_interop) 'instalar_app_interop_web.dart';

const _prefOcultar = 'ocultar_banner_instalar_app';

/// Banner que sugiere instalar Equilibra como app (PWA) cuando el
/// navegador detecta que se puede -- Chrome/Edge en Windows o Android
/// disparan el evento `beforeinstallprompt` (ver web/index.html); en
/// iOS Safari, apps nativas, o si el usuario ya la instaló, nunca
/// aparece. Si el usuario lo cierra con la X, no vuelve a aparecer
/// (se guarda en shared_preferences).
class InstalarAppBanner extends StatefulWidget {
  const InstalarAppBanner({super.key});

  @override
  State<InstalarAppBanner> createState() => _InstalarAppBannerState();
}

class _InstalarAppBannerState extends State<InstalarAppBanner> {
  bool _visible = false;
  String? _plataforma;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefOcultar) == true || !mounted) return;
    // El navegador dispara `beforeinstallprompt` en cualquier momento
    // después de cargar la página, así que se revisa cada segundo hasta
    // que aparezca (o hasta que el widget se destruya).
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!puedeInstalarApp()) return;
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _visible = true;
          _plataforma = plataformaSugeridaInstalacion();
        });
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _cerrar() async {
    setState(() => _visible = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefOcultar, true);
  }

  void _instalar() {
    instalarApp();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final esWindows = _plataforma == 'windows';
    final titulo = esWindows ? 'Instalá Equilibra en tu computadora' : 'Instalá Equilibra en tu teléfono';
    final detalle = esWindows
        ? 'Accedé más rápido con un ícono en el escritorio, como una app normal.'
        : 'Agregala a tu pantalla de inicio y usala como una app.';
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(esWindows ? Icons.desktop_windows_outlined : Icons.phone_android, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.textStrong)),
                Text(detalle, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          TextButton(
            onPressed: _instalar,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: const Text('Instalar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
          ),
          IconButton(
            onPressed: _cerrar,
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'No volver a mostrar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }
}
