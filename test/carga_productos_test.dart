import 'dart:convert';
import 'dart:typed_data';

import 'package:despacho_app/carga_productos.dart';
import 'package:despacho_app/impuesto.dart';
import 'package:despacho_app/producto.dart';
import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el inventario exportado se vuelve a leer igual (ida y vuelta)', () {
    final excel = armarExcelProductos([
      Producto(
        id: 7,
        nombre: 'Arroz 1kg',
        codigoCabys: '2399999000000',
        precioUnitario: 1250.5,
        costo: 900,
        stock: 30,
        nombreCategoria: 'Granos',
        impuesto: Impuesto(id: 2, nombre: '1%', porcentaje: 1, codigoHacienda: '02'),
      ),
    ]);
    final filas = leerArchivoProductos(Uint8List.fromList(excel.encode()!), 'inventario.xlsx')!;
    expect(filas, hasLength(1));
    final f = filas.single;
    expect(f['id'], 7);
    expect(f['nombre'], 'Arroz 1kg');
    expect(f['cabys'], '2399999000000');
    expect(f['precio'], 1250.5);
    expect(f['stock'], 30);
    expect(f['iva'], 1.0);
    expect(f['categoria'], 'Granos');
  });

  test('un Excel ajeno con otros encabezados y una fila de título', () {
    final excel = Excel.createExcel();
    final hoja = excel['Sheet1'];
    hoja.appendRow([TextCellValue('Lista de precios octubre')]);
    hoja.appendRow([TextCellValue('Descripción'), TextCellValue('Precio de compra'), TextCellValue('Precio de venta'), TextCellValue('Stock')]);
    hoja.appendRow([TextCellValue('Martillo'), IntCellValue(3000), IntCellValue(5000), IntCellValue(4)]);
    final filas = leerArchivoProductos(Uint8List.fromList(excel.encode()!), 'lista.xlsx')!;
    expect(filas.single, {'nombre': 'Martillo', 'costo': 3000, 'precio': 5000, 'stock': 4});
  });

  test('CSV con punto y coma, comillas y acentos', () {
    final csv = 'Nombre;Precio;IVA\r\n"Café, molido";"₡2.500";13\r\nTé;800;exento\r\n';
    final filas = leerArchivoProductos(Uint8List.fromList(utf8.encode(csv)), 'p.csv')!;
    expect(filas, [
      {'nombre': 'Café, molido', 'precio': '₡2.500', 'iva': '13'},
      {'nombre': 'Té', 'precio': '800', 'iva': 'exento'},
    ]);
  });

  test('sin encabezados reconocibles lo deja para la IA', () {
    final csv = 'a,b\n1,2\n';
    expect(leerArchivoProductos(Uint8List.fromList(utf8.encode(csv)), 'x.csv'), isNull);
    expect(leerArchivoProductos(Uint8List.fromList([1, 2, 3]), 'foto.jpg'), isNull);
  });
}
