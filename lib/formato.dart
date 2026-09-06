/// Formateo de números al estilo de Costa Rica: punto para separar miles,
/// coma para los decimales (ej: 1.234.567,89). Sin depender de paquetes de
/// localización, para evitar fallos por datos de locale no disponibles.
library formato;

/// Da formato "1.234.567,89" a un número. [decimales] controla cuántos
/// dígitos decimales se muestran (2 por defecto).
String formatearNumero(num valor, {int decimales = 2}) {
  final esNegativo = valor < 0;
  final valorAbs = valor.abs();
  final partes = valorAbs.toStringAsFixed(decimales).split('.');
  final enteroStr = partes[0];
  final decimalStr = partes.length > 1 ? partes[1] : '';

  final buffer = StringBuffer();
  final len = enteroStr.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buffer.write('.');
    buffer.write(enteroStr[i]);
  }

  final resultado = decimales > 0 ? '${buffer.toString()},$decimalStr' : buffer.toString();
  return esNegativo ? '-$resultado' : resultado;
}

/// Da formato "₡1.234.567,89" a un monto en colones.
String formatearColones(num valor, {int decimales = 2}) {
  return '₡${formatearNumero(valor, decimales: decimales)}';
}

/// Redondea a 2 decimales. El backend guarda montos como DecimalField con
/// solo 2 decimales; valores con más (comunes al leer XML de Hacienda, que
/// usa hasta 5) hacen que la API los rechace.
double redondear2(num valor) => double.parse(valor.toStringAsFixed(2));
