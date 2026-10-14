import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'login.dart';
import 'perfil_sesion.dart';
import 'theme/app_theme.dart';
import 'widgets/asistente_flotante.dart';

/// Varias cédulas con un mismo usuario (gestion/cedulas.py): cada cédula es
/// su propio negocio con su plan y su cobro; las cuentas vinculadas se
/// escogen al entrar (ElegirCedulaScreen) y se cambian desde la barra de
/// arriba (abrirCambiarCedula) sin volver a escribir la contraseña.
class Cedula {
  final int usuarioId;
  final int negocioId;
  final String nombre;
  final String cedula;
  final String tipoCedula;
  final String? logo;
  final bool actual;
  final bool suspendida;

  const Cedula({
    required this.usuarioId,
    required this.negocioId,
    required this.nombre,
    required this.cedula,
    this.tipoCedula = '',
    this.logo,
    this.actual = false,
    this.suspendida = false,
  });

  factory Cedula.fromJson(Map<String, dynamic> j) => Cedula(
    usuarioId: j['usuario_id'],
    negocioId: j['negocio_id'],
    nombre: j['nombre'] ?? '',
    cedula: j['cedula'] ?? '',
    tipoCedula: j['tipo_cedula'] ?? '',
    logo: j['logo'],
    actual: j['actual'] == true,
    suspendida: j['suspendida'] == true,
  );

  String get tipo => const {'01': 'Física', '02': 'Jurídica', '03': 'DIMEX', '04': 'NITE'}[tipoCedula] ?? 'Cédula';
}

List<Cedula> _desdeRespuesta(String cuerpo) =>
    [for (final c in (json.decode(cuerpo)['cedulas'] as List? ?? [])) Cedula.fromJson(Map<String, dynamic>.from(c))];

/// Las cédulas con las que puede trabajar el usuario (la actual primero).
/// Vacía si no es dueño de negocio o si falla la red.
Future<List<Cedula>> cargarCedulas() async {
  try {
    final r = await ApiService.get('/cedulas/');
    if (r.statusCode != 200) return [];
    return _desdeRespuesta(utf8.decode(r.bodyBytes));
  } catch (_) {
    return [];
  }
}

/// Pide la sesión de [destino] y la deja guardada. Lanza si no se pudo.
Future<void> tomarSesionDe(Cedula destino) async {
  final r = ApiService.verificar(await ApiService.post('/cedulas/cambiar/', {'usuario_id': destino.usuarioId}));
  final datos = json.decode(utf8.decode(r.bodyBytes));
  PerfilSesion.limpiar();
  AsistenteFlotante.limpiar();
  await ApiService.saveTokens(access: datos['access'], refresh: datos['refresh']);
}

/// Cambia a otra cédula y vuelve a abrir la app en ella (el login restaura
/// la sesión nueva y enruta a ese negocio).
Future<void> cambiarACedula(BuildContext context, Cedula destino) async {
  final mensajes = ScaffoldMessenger.of(context);
  final navegador = Navigator.of(context);
  try {
    await tomarSesionDe(destino);
    navegador.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    mensajes.showSnackBar(SnackBar(content: Text("Ahora trabajás con ${destino.nombre} (${destino.cedula})")));
  } catch (e) {
    mensajes.showSnackBar(SnackBar(content: Text(ApiService.textoError(e)), backgroundColor: Colors.red));
  }
}

Widget _avatar(Cedula c, {double radio = 22}) {
  final iniciales = c.nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
  return CircleAvatar(
    radius: radio,
    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
    backgroundImage: c.logo != null ? NetworkImage(c.logo!) : null,
    child: c.logo == null
        ? Text(iniciales.isEmpty ? '?' : iniciales, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))
        : null,
  );
}

Widget _tarjetaCedula(Cedula c, {required VoidCallback onTap, Widget? fin}) => Card(
  margin: const EdgeInsets.only(bottom: 10),
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: BorderSide(color: c.actual ? AppColors.primary : AppColors.border, width: c.actual ? 1.6 : 1),
  ),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    onTap: onTap,
    leading: _avatar(c),
    title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      [
        '${c.tipo} ${c.cedula}',
        if (c.suspendida) 'Suspendida por falta de pago',
      ].join(' · '),
      style: TextStyle(color: c.suspendida ? Colors.red.shade700 : AppColors.textMuted),
    ),
    trailing: fin ?? Icon(Icons.chevron_right, color: AppColors.textMuted),
  ),
);

/// Al entrar con un usuario que tiene varias cédulas: escoge con cuál
/// trabajar. Devuelve la elegida.
class ElegirCedulaScreen extends StatelessWidget {
  final List<Cedula> cedulas;
  const ElegirCedulaScreen({super.key, required this.cedulas});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              shrinkWrap: true,
              children: [
                Icon(Icons.badge_outlined, size: 40, color: AppColors.primary),
                const SizedBox(height: 12),
                const Text("¿Con cuál cédula querés trabajar?",
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  "Todo lo que hagas (facturas, compras, inventario) queda en la cédula que escojás. "
                  "Te podés cambiar cuando querás desde la barra de arriba.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 20),
                for (final c in cedulas) _tarjetaCedula(c, onTap: () => Navigator.pop(context, c)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desde la barra de arriba: ver las cédulas, cambiarse, vincular otra o
/// desvincular.
Future<void> abrirCambiarCedula(BuildContext context) async {
  final elegida = await showModalBottomSheet<Cedula>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => const _HojaCedulas(),
  );
  if (elegida != null && context.mounted) await cambiarACedula(context, elegida);
}

class _HojaCedulas extends StatefulWidget {
  const _HojaCedulas();

  @override
  State<_HojaCedulas> createState() => _HojaCedulasState();
}

class _HojaCedulasState extends State<_HojaCedulas> {
  List<Cedula>? _cedulas;

  @override
  void initState() {
    super.initState();
    cargarCedulas().then((l) {
      if (mounted) setState(() => _cedulas = l);
    });
  }

  Future<void> _vincular() async {
    final lista = await showDialog<List<Cedula>>(context: context, builder: (_) => const _DialogoVincular());
    if (lista != null && mounted) setState(() => _cedulas = lista);
  }

  Future<void> _desvincular(Cedula c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Desvincular cédula"),
        content: Text(
          "${c.nombre} (${c.cedula}) deja de aparecer para cambiarte. La cuenta, sus facturas y su plan siguen igual; "
          "para volver a entrar a ella usá su usuario y contraseña o vinculala de nuevo.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Desvincular")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = ApiService.verificar(await ApiService.post('/cedulas/desvincular/', {'usuario_id': c.usuarioId}));
      if (mounted) setState(() => _cedulas = _desdeRespuesta(utf8.decode(r.bodyBytes)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cedulas = _cedulas;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            const Text("Tus cédulas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("Cada cédula tiene su propio plan, sus facturas y su inventario.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            if (cedulas == null)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in cedulas)
                      _tarjetaCedula(
                        c,
                        onTap: () => Navigator.pop(context, c.actual ? null : c),
                        fin: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (c.actual)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                              child: Text("Abierta", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            )
                          else
                            Icon(Icons.swap_horiz, color: AppColors.textMuted),
                          if (cedulas.length > 1)
                            PopupMenuButton<String>(
                              tooltip: "Más",
                              onSelected: (_) => _desvincular(c),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'desvincular', child: Text("Desvincular")),
                              ],
                            ),
                        ]),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _vincular,
              icon: const Icon(Icons.add_link),
              label: const Text("Vincular otra cédula"),
            ),
          ],
        ),
      ),
    );
  }
}

/// Usuario y contraseña de la otra cédula (una sola vez).
class _DialogoVincular extends StatefulWidget {
  const _DialogoVincular();

  @override
  State<_DialogoVincular> createState() => _DialogoVincularState();
}

class _DialogoVincularState extends State<_DialogoVincular> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _enviando = false;
  bool _verClave = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_usuario.text.trim().isEmpty || _clave.text.isEmpty) {
      setState(() => _error = "Escribí el usuario y la contraseña de la otra cédula.");
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = ApiService.verificar(
        await ApiService.post('/cedulas/vincular/', {'username': _usuario.text.trim(), 'password': _clave.text}),
      );
      if (mounted) Navigator.pop(context, _desdeRespuesta(utf8.decode(r.bodyBytes)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiService.textoError(e);
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Vincular otra cédula"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Escribí el usuario y la contraseña con que entrás a la otra cédula. Se piden solo esta vez: "
              "después te cambiás con un toque. Cada cédula sigue con su propio plan y su cobro.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _usuario,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Usuario de la otra cédula", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _clave,
              obscureText: !_verClave,
              onSubmitted: (_) => _enviar(),
              decoration: InputDecoration(
                labelText: "Contraseña",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _verClave = !_verClave),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _enviando ? null : () => Navigator.pop(context), child: const Text("Cancelar")),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Vincular"),
        ),
      ],
    );
  }
}
