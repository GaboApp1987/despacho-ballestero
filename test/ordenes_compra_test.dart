import 'package:despacho_app/compra_model.dart';
import 'package:despacho_app/ordenes_compra.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final papa = InsumoCompra(id: 1, nombre: 'Papa', unidad: 'kg', costo: 800);
  final aceite = InsumoCompra(id: 2, nombre: 'Aceite', unidad: 'l', costo: 2000);
  final sal = InsumoCompra(id: 3, nombre: 'Sal', unidad: 'kg');

  OrdenCompra orden({double papaFacturada = 0, double papaRecibida = 0}) => OrdenCompra(
        id: 7,
        proveedorId: 1,
        nombreProveedor: 'Verdulería',
        numero: 1,
        estado: 'enviada',
        lineas: [
          LineaOrden(id: 1, insumoId: 1, nombre: 'Papa', unidad: 'kg', cantidad: 50, precio: 800, tarifa: 13,
              facturado: papaFacturada, recibido: papaRecibida),
          LineaOrden(id: 2, insumoId: 2, nombre: 'Aceite', unidad: 'L', cantidad: 10, precio: 2000, tarifa: 13),
        ],
      );

  test('factura igual a la orden: sin diferencias', () {
    final dif = compararConOrden(orden(), [
      LineaCompra(insumo: papa, cantidad: 50, precioCosto: 800, tarifa: 13),
      LineaCompra(insumo: aceite, cantidad: 10, precioCosto: 2000, tarifa: 13),
    ]);
    expect(dif, isEmpty);
  });

  test('cobran más caro, facturan de más y traen algo no pedido', () {
    final dif = compararConOrden(orden(), [
      LineaCompra(insumo: papa, cantidad: 55, precioCosto: 900, tarifa: 13),
      LineaCompra(insumo: aceite, cantidad: 10, precioCosto: 2000, tarifa: 13),
      LineaCompra(insumo: sal, cantidad: 1, precioCosto: 500, tarifa: 1),
    ]);
    expect(dif.where((d) => d.alerta).length, 3);
    expect(dif.map((d) => d.texto).join('\n'), allOf(contains('Papa: facturan 55'), contains('+12,5 %'), contains('Sal: no estaba')));
  });

  test('entrega parcial y recepción contada', () {
    // Ya se facturaron 20 de papa y al recibir se contaron 40 en total.
    final dif = compararConOrden(orden(papaFacturada: 20, papaRecibida: 40), [
      LineaCompra(insumo: papa, cantidad: 25, precioCosto: 800, tarifa: 13),
    ]);
    final textos = dif.map((d) => d.texto).toList();
    // 25 de 30 pendientes (informativo), pero solo llegaron 20 sin facturar (alerta).
    expect(dif.where((d) => !d.alerta).map((d) => d.texto), contains(contains('quedan 5')));
    expect(dif.where((d) => d.alerta).single.texto, contains('se contaron 20'));
    expect(textos.any((t) => t.startsWith('Aceite: faltan 10')), isTrue);
  });

  test('lo pendiente de la orden se carga como líneas de compra', () {
    final lineas = lineasPendientesDeOrden(orden(papaFacturada: 20), [], [papa, aceite]);
    expect(lineas.map((l) => (l.nombre, l.cantidad, l.precioCosto)), [('Papa', 30.0, 800.0), ('Aceite', 10.0, 2000.0)]);
  });
}
