import 'package:flutter/material.dart';

/// Lista de requisitos de una contraseña nueva que se van marcando con un
/// check mientras se escribe. Son las mismas reglas del servidor
/// (AUTH_PASSWORD_VALIDATORS en settings.py): al menos 8 caracteres, que no
/// sea solo números, que no se parezca al usuario/nombre/correo y que no
/// sea una contraseña común. El servidor sigue siendo el que decide; esto
/// es para que la persona vea qué le falta antes de enviar.
class RequisitosContrasena extends StatelessWidget {
  final TextEditingController controller;

  /// Lo que no se le puede parecer (usuario, nombre, correo): controllers
  /// del mismo formulario o textos fijos.
  final List<TextEditingController> parecidosA;
  final List<String> textosParecidos;

  const RequisitosContrasena({super.key, required this.controller, this.parecidosA = const [], this.textosParecidos = const []});

  static const largoMinimo = 8;

  // Las más usadas (la lista del servidor tiene 20.000; estas son las que
  // la gente de verdad intenta).
  static const _comunes = {
    '12345678', '123456789', '1234567890', '87654321', '11111111', '00000000', '12341234', '11223344',
    'password', 'password1', 'contraseña', 'contrasena', 'qwerty123', 'qwertyui', 'abc12345', 'abcd1234',
    'iloveyou', 'equilibra', 'costarica', 'admin123', 'welcome1', 'bienvenido', 'superman', 'princesa',
  };

  static bool cumpleLargo(String c) => c.length >= largoMinimo;
  static bool noSoloNumeros(String c) => c.isNotEmpty && !RegExp(r'^\d+$').hasMatch(c);
  static bool noComun(String c) => c.isNotEmpty && !_comunes.contains(c.toLowerCase());

  /// Parecido como lo mide el servidor (UserAttributeSimilarityValidator,
  /// 0.7): se compara con cada valor y con cada parte (ana.tienda -> ana, tienda).
  static bool noParecida(String c, Iterable<String> valores) {
    if (c.isEmpty) return false;
    final clave = c.toLowerCase();
    for (final valor in valores) {
      final v = valor.trim().toLowerCase();
      if (v.isEmpty) continue;
      for (final parte in [v, ...v.split(RegExp(r'\W+'))]) {
        if (parte.length < 3) continue;
        if (_parecido(clave, parte) >= 0.7) return false;
      }
    }
    return true;
  }

  /// 2·(subcadena común más larga) / (largo a + largo b): una aproximación
  /// simple al SequenceMatcher de Python.
  static double _parecido(String a, String b) {
    var mejor = 0;
    final previo = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      var diagonal = 0;
      for (var j = 1; j <= b.length; j++) {
        final arriba = previo[j];
        previo[j] = a[i - 1] == b[j - 1] ? diagonal + 1 : 0;
        if (previo[j] > mejor) mejor = previo[j];
        diagonal = arriba;
      }
    }
    return 2 * mejor / (a.length + b.length);
  }

  /// true si cumple todo (para no dejar enviar el formulario).
  static bool esValida(String c, {Iterable<String> parecidos = const []}) =>
      cumpleLargo(c) && noSoloNumeros(c) && noComun(c) && noParecida(c, parecidos);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ...parecidosA]),
      builder: (context, _) {
        final c = controller.text;
        final parecidos = [...parecidosA.map((x) => x.text), ...textosParecidos];
        final requisitos = [
          (cumpleLargo(c), "Al menos $largoMinimo caracteres"),
          (noSoloNumeros(c), "No solo números"),
          (noParecida(c, parecidos), "Que no se parezca al usuario, nombre o correo"),
          (noComun(c), "Que no sea una contraseña muy común"),
        ];
        final tema = Theme.of(context);
        final apagado = tema.colorScheme.onSurfaceVariant;
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (cumple, texto) in requisitos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          cumple ? Icons.check_circle : Icons.radio_button_unchecked,
                          key: ValueKey(cumple),
                          size: 16,
                          color: cumple ? Colors.green.shade500 : apagado,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          texto,
                          style: TextStyle(fontSize: 12.5, color: cumple ? Colors.green.shade600 : apagado),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
