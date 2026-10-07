import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Lee el estado de cuenta del banco (Excel .xlsx o CSV) y devuelve las
/// filas para la conciliación: {fecha (yyyy-mm-dd), descripcion,
/// referencia, monto} con monto positivo = entra, negativo = sale.
///
/// Cada banco exporta distinto, así que las columnas se reconocen por el
/// encabezado: Fecha; Descripción/Concepto/Detalle; Referencia/Documento/
/// Comprobante; y un Monto con signo o Débito + Crédito por separado.
List<Map<String, dynamic>> leerEstadoDeCuenta(Uint8List bytes, String nombreArchivo) {
  final tabla = nombreArchivo.toLowerCase().endsWith('.csv') ? _tablaCsv(bytes) : _tablaExcel(bytes);
  int? filaEncabezado;
  final col = <String, int>{};
  for (var i = 0; i < tabla.length && i < 30; i++) {
    final celdas = tabla[i].map(_normalizar).toList();
    if (celdas.any((c) => c.startsWith('fecha')) &&
        celdas.any((c) => c.contains('monto') || c.contains('debito') || c.contains('credito') || c.contains('importe'))) {
      filaEncabezado = i;
      for (var j = 0; j < celdas.length; j++) {
        final c = celdas[j];
        if (c.startsWith('fecha') && !col.containsKey('fecha')) {
          col['fecha'] = j;
        } else if (c.contains('debito') || c.contains('cargo') || c == 'retiros') {
          col['debito'] = j;
        } else if (c.contains('credito') || c.contains('abono') || c == 'depositos') {
          col['credito'] = j;
        } else if (c.contains('monto') || c.contains('importe')) {
          col['monto'] = j;
        } else if (c.contains('referencia') || c.contains('documento') || c.contains('comprobante') || c.startsWith('n.') || c == 'numero') {
          col['referencia'] = j;
        } else if (c.contains('descripcion') || c.contains('concepto') || c.contains('detalle') || c.contains('movimiento')) {
          col['descripcion'] = j;
        }
      }
      break;
    }
  }
  if (filaEncabezado == null || !col.containsKey('fecha') ||
      !(col.containsKey('monto') || col.containsKey('debito') || col.containsKey('credito'))) {
    throw Exception("No encontré los encabezados del estado de cuenta: hace falta una columna \"Fecha\" y "
        "\"Monto\" (o \"Débito\" y \"Crédito\").");
  }
  final filas = <Map<String, dynamic>>[];
  for (var i = filaEncabezado + 1; i < tabla.length; i++) {
    final fila = tabla[i];
    String celda(String clave) {
      final j = col[clave];
      return (j == null || j >= fila.length) ? '' : fila[j].trim();
    }

    final fecha = _fecha(celda('fecha'));
    if (fecha == null) continue; // totales, saldos, filas vacías
    double monto;
    if (col.containsKey('monto')) {
      monto = _numero(celda('monto'));
    } else {
      monto = _numero(celda('credito')).abs() - _numero(celda('debito')).abs();
    }
    if (monto == 0) continue;
    filas.add({
      'fecha': fecha,
      'descripcion': celda('descripcion'),
      'referencia': celda('referencia'),
      'monto': monto.toStringAsFixed(2),
    });
  }
  if (filas.isEmpty) throw Exception("El archivo no tiene movimientos debajo de los encabezados.");
  return filas;
}

List<List<String>> _tablaExcel(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) throw Exception("El archivo no tiene hojas.");
  return excel.tables.values.first.rows.map((fila) => fila.map((c) {
        final v = c?.value;
        if (v is DateCellValue) {
          return "${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}";
        }
        if (v is DateTimeCellValue) {
          return "${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}";
        }
        return v?.toString() ?? '';
      }).toList()).toList();
}

List<List<String>> _tablaCsv(Uint8List bytes) {
  var texto = utf8.decode(bytes, allowMalformed: true);
  if (texto.startsWith('﻿')) texto = texto.substring(1);
  final lineas = texto.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lineas.isEmpty) return [];
  // Separador: el que más aparezca en el encabezado (Excel en español usa ";").
  final muestra = lineas.take(5).join();
  final sep = ';'.allMatches(muestra).length > ','.allMatches(muestra).length ? ';' : ',';
  return lineas.map((l) => _partirCsv(l, sep)).toList();
}

List<String> _partirCsv(String linea, String sep) {
  final campos = <String>[];
  final actual = StringBuffer();
  var entreComillas = false;
  for (var i = 0; i < linea.length; i++) {
    final ch = linea[i];
    if (ch == '"') {
      entreComillas = !entreComillas;
    } else if (ch == sep && !entreComillas) {
      campos.add(actual.toString());
      actual.clear();
    } else {
      actual.write(ch);
    }
  }
  campos.add(actual.toString());
  return campos;
}

String _normalizar(String texto) => texto
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úù]'), 'u')
    .trim();

/// "31/12/2026", "31-12-2026", "2026-12-31" o "2026-12-31 00:00:00" ->
/// "2026-12-31"; null si no es fecha.
String? _fecha(String texto) {
  final t = texto.trim();
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  if (m != null) return "${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}";
  m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})').firstMatch(t);
  if (m != null) {
    var anio = m[3]!;
    if (anio.length == 2) anio = '20$anio';
    return "$anio-${m[2]!.padLeft(2, '0')}-${m[1]!.padLeft(2, '0')}";
  }
  return null;
}

/// "₡1.234.567,89", "1,234,567.89", "-1500", "(1 500,00)" -> número.
double _numero(String texto) {
  var t = texto.replaceAll(RegExp(r'[^\d,.\-()]'), '');
  if (t.isEmpty) return 0;
  final negativo = t.startsWith('-') || (t.startsWith('(') && t.endsWith(')'));
  t = t.replaceAll(RegExp(r'[\-()]'), '');
  final ultimaComa = t.lastIndexOf(',');
  final ultimoPunto = t.lastIndexOf('.');
  if (ultimaComa > ultimoPunto) {
    // Coma decimal: "1.234,56"
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', '');
  }
  final v = double.tryParse(t) ?? 0;
  return negativo ? -v : v;
}
