import 'formato.dart';

class Impuesto {
  final int id;
  final String nombre;
  final double porcentaje;
  final String codigoHacienda;

  Impuesto({
    required this.id,
    required this.nombre,
    required this.porcentaje,
    required this.codigoHacienda,
  });

  factory Impuesto.fromJson(Map<String, dynamic> json) {
    return Impuesto(
      id: json['id'],
      nombre: json['nombre'],
      porcentaje: double.tryParse(json['porcentaje'].toString()) ?? 0.0,
      codigoHacienda: json['codigo_hacienda'] ?? '01',
    );
  }

  @override
  String toString() => "$nombre (${formatearNumero(porcentaje)}%)";
}

/// Códigos oficiales de tarifa de Hacienda (v4.3) más comunes en Costa Rica.
const Map<String, String> codigosTarifaHacienda = {
  '01': 'Tarifa 0% (Exento)',
  '02': 'Tarifa reducida 1%',
  '03': 'Tarifa reducida 2%',
  '04': 'Tarifa reducida 4%',
  '05': 'Transitorio 0%',
  '06': 'Transitorio 4%',
  '07': 'Transitorio 8%',
  '08': 'Tarifa general 13%',
  '09': 'Tarifa reducida 0.5%',
};