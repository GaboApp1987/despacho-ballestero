import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'cuenta_contable.dart';
import 'cuentas_contables_screen.dart';
import 'negocio.dart';

/// Nivel de cada cuenta en el árbol del catálogo (0 = sin cuenta de mayor),
/// siguiendo la cadena de cuenta_padre.
Map<int, int> nivelesCatalogo(List<CuentaContable> cuentas) {
  final porId = {for (final c in cuentas) if (c.id != null) c.id!: c};
  final niveles = <int, int>{};
  int nivel(CuentaContable c, [int guardia = 0]) {
    if (c.id != null && niveles.containsKey(c.id)) return niveles[c.id]!;
    final padre = c.cuentaPadre != null ? porId[c.cuentaPadre] : null;
    // guardia: una cadena circular mal cargada no cuelga la pantalla.
    final n = (padre == null || guardia > 12) ? 0 : nivel(padre, guardia + 1) + 1;
    if (c.id != null) niveles[c.id!] = n;
    return n;
  }

  for (final c in cuentas) {
    nivel(c);
  }
  return niveles;
}

/// Siguiente código libre para una subcuenta de [padre], siguiendo el
/// formato que ya usa el catálogo:
/// - Si ya tiene subcuentas, la última + 1 manteniendo el largo
///   ("1105" -> "1106", "1.1.09" -> "1.1.10").
/// - Si no tiene: "1100" -> "1101" (mayor que termina en 00, como el
///   catálogo estándar de CR), "1.1" -> "1.1.01", "11" -> "1101".
String siguienteCodigo(CuentaContable? padre, List<CuentaContable> cuentas) {
  final usados = cuentas.map((c) => c.codigo).toSet();
  final hermanas = cuentas.where((c) => c.cuentaPadre == padre?.id).map((c) => c.codigo).toList()..sort();
  String candidato;
  if (hermanas.isNotEmpty) {
    candidato = _incrementar(hermanas.last);
  } else if (padre == null) {
    return '';
  } else {
    final p = padre.codigo;
    if (RegExp(r'^\d+00$').hasMatch(p)) {
      candidato = (int.parse(p) + 1).toString().padLeft(p.length, '0');
    } else if (p.contains('.') || p.contains('-')) {
      candidato = '$p${p.contains('.') ? '.' : '-'}01';
    } else {
      candidato = '${p}01';
    }
  }
  var guardia = 0;
  while (usados.contains(candidato) && guardia++ < 500) {
    candidato = _incrementar(candidato);
  }
  return candidato;
}

String _incrementar(String codigo) {
  final m = RegExp(r'^(.*?)(\d+)$').firstMatch(codigo);
  if (m == null) return '${codigo}1';
  final numero = m.group(2)!;
  return '${m.group(1)}${(int.parse(numero) + 1).toString().padLeft(numero.length, '0')}';
}

String _normalizar(String texto) => texto
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úù]'), 'u')
    .trim();

/// Lee un catálogo desde Excel. Busca la fila de encabezados (la primera que
/// tenga "Código" y "Nombre") y reconoce las columnas por nombre, así sirve
/// el formato que exporta Equilibra y uno parecido de otro sistema.
/// Columnas: Código, Nombre, Tipo, Naturaleza (opcional), Es detalle
/// (opcional), Código cuenta de mayor (opcional).
List<Map<String, dynamic>> leerCatalogoExcel(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) throw Exception("El archivo no tiene hojas.");
  final hoja = excel.tables.values.first;
  int? filaEncabezado;
  final columnas = <String, int>{};
  for (var i = 0; i < hoja.rows.length && i < 15; i++) {
    final celdas = hoja.rows[i].map((c) => _normalizar(c?.value?.toString() ?? '')).toList();
    if (celdas.any((c) => c.startsWith('codigo')) && celdas.any((c) => c.startsWith('nombre'))) {
      filaEncabezado = i;
      for (var j = 0; j < celdas.length; j++) {
        final c = celdas[j];
        if (c.contains('mayor') || c.contains('padre')) {
          columnas['codigo_padre'] = j;
        } else if (c.startsWith('codigo')) {
          columnas.putIfAbsent('codigo', () => j);
        } else if (c.startsWith('nombre') || c.startsWith('descripcion')) {
          columnas['nombre'] = j;
        } else if (c.startsWith('tipo')) {
          columnas['tipo'] = j;
        } else if (c.startsWith('naturaleza')) {
          columnas['naturaleza'] = j;
        } else if (c.contains('detalle') || c.contains('movimiento')) {
          columnas['es_detalle'] = j;
        }
      }
      break;
    }
  }
  if (filaEncabezado == null || !columnas.containsKey('codigo') || !columnas.containsKey('nombre') || !columnas.containsKey('tipo')) {
    throw Exception("No encontré los encabezados. La primera hoja necesita columnas \"Código\", \"Nombre\" y \"Tipo\".");
  }
  final filas = <Map<String, dynamic>>[];
  for (var i = filaEncabezado + 1; i < hoja.rows.length; i++) {
    final fila = hoja.rows[i];
    String celda(String clave) {
      final j = columnas[clave];
      if (j == null || j >= fila.length) return '';
      final v = fila[j]?.value;
      if (v == null) return '';
      // Los códigos numéricos llegan como 1101.0 desde Excel.
      final t = v.toString().trim();
      return RegExp(r'^\d+\.0$').hasMatch(t) ? t.substring(0, t.length - 2) : t;
    }

    final codigo = celda('codigo');
    if (codigo.isEmpty && celda('nombre').isEmpty) continue;
    filas.add({
      'codigo': codigo,
      'nombre': celda('nombre'),
      'tipo': celda('tipo'),
      if (celda('naturaleza').isNotEmpty) 'naturaleza': celda('naturaleza'),
      if (celda('es_detalle').isNotEmpty) 'es_detalle': celda('es_detalle'),
      if (celda('codigo_padre').isNotEmpty) 'codigo_padre': celda('codigo_padre'),
    });
  }
  if (filas.isEmpty) throw Exception("El archivo no tiene cuentas debajo de los encabezados.");
  return filas;
}

/// Entrada "Catálogo de cuentas" del menú del contador: elige el cliente
/// (directo si solo hay uno) y abre su catálogo.
Future<void> abrirCatalogoCuentas(BuildContext context) async {
  try {
    final res = ApiService.verificar(await ApiService.get('/negocios/'));
    final negocios = (json.decode(utf8.decode(res.bodyBytes)) as List).map((j) => Negocio.fromJson(j)).toList();
    if (!context.mounted) return;
    if (negocios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todavía no tenés clientes registrados.")));
      return;
    }
    Negocio? elegido = negocios.length == 1 ? negocios.first : null;
    elegido ??= await showDialog<Negocio>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("¿De qué cliente es el catálogo?"),
        children: negocios
            .map((n) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, n),
                  child: Text("${n.nombreComercial}  ·  ${n.cedula}"),
                ))
            .toList(),
      ),
    );
    if (elegido == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CuentasContablesScreen(negocioId: elegido!.id, negocioNombre: elegido.nombreComercial)),
    );
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudieron cargar los clientes: $e")));
  }
}
