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

/// Costa Rica no usa horario de verano: es UTC-6 todo el año. El backend
/// (USE_TZ=True) guarda y manda fecha_emision en UTC -- hay que restar 6
/// horas explícitamente en vez de usar DateTime.toLocal(), que depende de
/// la zona horaria del dispositivo (puede no ser la de Costa Rica, como al
/// probar desde otro país). Si el string no trae información de zona
/// (no debería pasar con la API, pero por robustez) se asume que ya es CR.
DateTime aFechaCostaRica(String fechaIso) {
  final dt = DateTime.parse(fechaIso);
  return (dt.isUtc ? dt : dt.toUtc()).subtract(const Duration(hours: 6));
}

/// "HH:mm" de una fecha_emision en hora de Costa Rica.
String horaCostaRica(String fechaIso) {
  if (!fechaIso.contains('T')) return '';
  try {
    final cr = aFechaCostaRica(fechaIso);
    final hh = cr.hour.toString().padLeft(2, '0');
    final mm = cr.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  } catch (_) {
    return '';
  }
}
