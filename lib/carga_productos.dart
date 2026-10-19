import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'cabys_picker.dart';
import 'export_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'producto.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Carga masiva de productos: exportar el inventario a Excel, editarlo y
/// volver a subirlo; la plantilla vacía; o cualquier otro archivo (PDF,
/// foto, Excel de otro sistema) que lee la IA. Siempre termina en
/// [PantallaRevisionCarga]: nada se guarda sin revisar (ver
/// carga_masiva en ProductoViewSet y gestion/productos_masivo.py).

/// Columnas de la plantilla, en orden. La clave es la que espera el backend.
const List<(String, String)> columnasPlantilla = [
  ('id', 'ID'),
  ('nombre', 'Nombre'),
  ('cabys', 'CABYS'),
  ('unidad', 'Unidad'),
  ('tipo', 'Tipo'),
  ('categoria', 'Categoría'),
  ('moneda', 'Moneda'),
  ('precio', 'Precio'),
  ('costo', 'Costo'),
  ('stock', 'Existencias'),
  ('iva', 'IVA %'),
];

/// Otros nombres con que suele venir cada columna en un Excel ajeno.
const Map<String, List<String>> _sinonimos = {
  'id': ['id'],
  'nombre': ['nombre', 'producto', 'descripcion', 'articulo', 'detalle', 'nombre del producto'],
  'cabys': ['cabys', 'codigo cabys', 'cod cabys', 'codigo de cabys'],
  'unidad': ['unidad', 'unidad de medida', 'um', 'medida', 'unid'],
  'tipo': ['tipo'],
  'categoria': ['categoria', 'familia', 'departamento', 'grupo'],
  'moneda': ['moneda'],
  'precio': ['precio', 'precio venta', 'precio de venta', 'pvp', 'precio unitario', 'precio al publico', 'venta'],
  'costo': ['costo', 'precio costo', 'costo unitario', 'precio compra', 'precio de compra', 'compra'],
  'stock': ['existencias', 'stock', 'cantidad', 'inventario', 'existencia'],
  'iva': ['iva', 'iva %', 'impuesto', 'tarifa', 'tarifa iva', '% iva'],
};

String _normalizar(String t) => t
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úù]'), 'u')
    .replaceAll(RegExp(r'[^a-z0-9% ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Columna -> índice, a partir de una fila de encabezados. Primero por
/// nombre exacto; si no, por palabra ("precio de venta con IVA" ->
/// precio), revisando costo antes que precio para no confundirlos.
Map<String, int> _mapearEncabezados(List<String> celdas) {
  final mapa = <String, int>{};
  final normal = celdas.map(_normalizar).toList();
  for (var i = 0; i < normal.length; i++) {
    for (final e in _sinonimos.entries) {
      if (!mapa.containsKey(e.key) && e.value.contains(normal[i])) {
        mapa[e.key] = i;
        break;
      }
    }
  }
  const porPalabra = [
    ('cabys', 'cabys'),
    ('costo', 'costo'),
    ('costo', 'compra'),
    ('precio', 'precio'),
    ('stock', 'existencia'),
    ('iva', 'iva'),
    ('nombre', 'descripcion'),
    ('nombre', 'producto'),
    ('categoria', 'categoria'),
  ];
  for (var i = 0; i < normal.length; i++) {
    if (mapa.containsValue(i)) continue;
    for (final (clave, palabra) in porPalabra) {
      if (!mapa.containsKey(clave) && normal[i].contains(palabra)) {
        mapa[clave] = i;
        break;
      }
    }
  }
  return mapa;
}

bool _reconocida(Map<String, int> mapa) =>
    mapa.containsKey('nombre') && ['precio', 'stock', 'id', 'costo', 'cabys'].any(mapa.containsKey) ||
    mapa.containsKey('id') && ['precio', 'stock', 'costo'].any(mapa.containsKey);

dynamic _valorCelda(Data? celda, String clave) {
  final v = celda?.value;
  if (v == null) return null;
  if (v is IntCellValue) return clave == 'cabys' || clave == 'nombre' ? v.value.toString() : v.value;
  if (v is DoubleCellValue) {
    if (clave == 'cabys' || clave == 'id') return v.value.toStringAsFixed(0);
    return v.value;
  }
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

List<Map<String, dynamic>> _filasDesde(List<List<dynamic>> tabla, int filaEncabezado, Map<String, int> mapa) {
  final filas = <Map<String, dynamic>>[];
  for (var r = filaEncabezado + 1; r < tabla.length; r++) {
    final fila = <String, dynamic>{};
    for (final e in mapa.entries) {
      if (e.value < tabla[r].length && tabla[r][e.value] != null) fila[e.key] = tabla[r][e.value];
    }
    if (fila.values.any((v) => v != null && v.toString().trim().isNotEmpty)) filas.add(fila);
  }
  return filas;
}

/// Lee la plantilla (o cualquier Excel/CSV con encabezados reconocibles)
/// sin IA. Devuelve null si no reconoce las columnas: entonces lo lee la IA.
List<Map<String, dynamic>>? leerArchivoProductos(Uint8List bytes, String nombreArchivo) {
  final ext = nombreArchivo.toLowerCase().split('.').last;
  try {
    if (ext == 'xlsx') {
      final excel = Excel.decodeBytes(bytes);
      for (final hoja in excel.tables.values) {
        for (var r = 0; r < hoja.rows.length && r < 8; r++) {
          final mapa = _mapearEncabezados(hoja.rows[r].map((c) => c?.value?.toString() ?? '').toList());
          if (!_reconocida(mapa)) continue;
          final tabla = [
            for (final fila in hoja.rows)
              [for (var c = 0; c < fila.length; c++) _valorCelda(fila[c], mapa.entries.where((e) => e.value == c).map((e) => e.key).firstOrNull ?? '')]
          ];
          return _filasDesde(tabla, r, mapa);
        }
      }
      return null;
    }
    if (ext == 'csv' || ext == 'txt') {
      String texto;
      try {
        texto = utf8.decode(bytes);
      } catch (_) {
        texto = latin1.decode(bytes);
      }
      final tabla = leerCsv(texto.replaceFirst('﻿', ''));
      for (var r = 0; r < tabla.length && r < 8; r++) {
        final mapa = _mapearEncabezados(tabla[r].map((c) => c.toString()).toList());
        if (_reconocida(mapa)) return _filasDesde(tabla, r, mapa);
      }
    }
  } catch (_) {
    // Un archivo que no se deja leer lo intenta la IA.
  }
  return null;
}

/// CSV con separador , ; o tabulador (el que más aparezca en la primera
/// línea) y comillas dobles.
List<List<String>> leerCsv(String texto) {
  final primera = texto.split('\n').first;
  final sep = [';', ',', '\t'].reduce((a, b) => primera.split(a).length >= primera.split(b).length ? a : b);
  final filas = <List<String>>[];
  var fila = <String>[];
  final celda = StringBuffer();
  var comillas = false;
  for (var i = 0; i < texto.length; i++) {
    final c = texto[i];
    if (comillas) {
      if (c == '"' && i + 1 < texto.length && texto[i + 1] == '"') {
        celda.write('"');
        i++;
      } else if (c == '"') {
        comillas = false;
      } else {
        celda.write(c);
      }
    } else if (c == '"') {
      comillas = true;
    } else if (c == sep) {
      fila.add(celda.toString().trim());
      celda.clear();
    } else if (c == '\n') {
      fila.add(celda.toString().trim());
      celda.clear();
      filas.add(fila);
      fila = <String>[];
    } else if (c != '\r') {
      celda.write(c);
    }
  }
  if (celda.isNotEmpty || fila.isNotEmpty) {
    fila.add(celda.toString().trim());
    filas.add(fila);
  }
  return filas;
}

/// El inventario en el formato de la plantilla (vacío = plantilla sola),
/// con una hoja de instrucciones.
Excel armarExcelProductos(List<Producto> productos) {
  final excel = Excel.createExcel();
  final hoja = excel['Productos'];
  final encabezado = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF3730A3'),
  );
  hoja.appendRow([for (final c in columnasPlantilla) TextCellValue(c.$2)]);
  for (var c = 0; c < columnasPlantilla.length; c++) {
    hoja.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = encabezado;
  }
  for (final p in productos) {
    hoja.appendRow([
      IntCellValue(p.id),
      TextCellValue(p.nombre),
      TextCellValue(p.codigoCabys),
      TextCellValue(p.unidadMedida),
      TextCellValue(tiposProducto[p.tipo] ?? p.tipo),
      TextCellValue(p.nombreCategoria ?? ''),
      TextCellValue(p.monedaPrecio),
      DoubleCellValue(p.precioUnitario),
      DoubleCellValue(p.costo),
      IntCellValue(p.stock),
      p.impuesto == null ? null : DoubleCellValue(p.impuesto!.porcentaje),
    ]);
  }
  const anchos = [8.0, 38.0, 17.0, 9.0, 12.0, 18.0, 9.0, 13.0, 13.0, 12.0, 8.0];
  for (var i = 0; i < anchos.length; i++) {
    hoja.setColumnWidth(i, anchos[i]);
  }

  final ayuda = excel['Instrucciones'];
  for (final linea in [
    'Cómo usar esta hoja',
    '',
    'Una fila por producto. Al subirla, Equilibra te muestra lo que va a crear y lo que va a cambiar antes de guardar.',
    'ID: no lo cambiés. Con ID se actualiza ese producto; sin ID se busca por nombre y, si no existe, se crea.',
    'Celda vacía = no se cambia ese dato. Podés borrar las columnas que no vas a tocar (dejá ID o Nombre).',
    'CABYS: obligatorio para los productos nuevos (13 dígitos). Si no lo sabés, dejalo vacío y la IA lo busca en la revisión.',
    'Unidad: Unid, Kg, G, L, mL, M, h, Sp (servicios profesionales)... Si la dejás vacía queda Unid.',
    'Tipo: Mercancía o Servicio. Vacío = según el CABYS.',
    'Moneda: CRC o USD (del precio y el costo).',
    'IVA %: 13, 4, 2, 1, 0 o Exento. Vacío en un producto nuevo = la tarifa que elijás al subirla (13% por defecto).',
    'Existencias: la cantidad que hay ahora (sirve para cargar un conteo físico).',
    'Categoría: si no existe, se crea.',
  ]) {
    ayuda.appendRow([TextCellValue(linea)]);
  }
  ayuda.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = CellStyle(bold: true, fontSize: 14);
  ayuda.setColumnWidth(0, 110);

  excel.setDefaultSheet('Productos');
  if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
  return excel;
}

String _hoy() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Menú de Inventario: subir archivo, plantilla y exportar.
Future<void> abrirCargaProductos({
  required BuildContext context,
  required Negocio negocio,
  required List<Producto> productos,
  required VoidCallback onGuardado,
}) async {
  final opcion = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Importar y exportar productos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          ListTile(
            leading: Icon(Icons.upload_file_outlined, color: AppColors.primary),
            title: const Text('Subir archivo'),
            subtitle: const Text('La plantilla o tu inventario exportado se lee al instante. Cualquier otro Excel, PDF o foto de una lista de precios lo lee la IA.'),
            onTap: () => Navigator.pop(ctx, 'subir'),
          ),
          ListTile(
            leading: Icon(Icons.download_outlined, color: AppColors.primary),
            title: const Text('Exportar mi inventario a Excel'),
            subtitle: const Text('Cambiá precios, costos o existencias en el Excel y volvé a subirlo.'),
            enabled: productos.isNotEmpty,
            onTap: () => Navigator.pop(ctx, 'exportar'),
          ),
          ListTile(
            leading: Icon(Icons.table_chart_outlined, color: AppColors.primary),
            title: const Text('Descargar plantilla vacía'),
            subtitle: const Text('Para cargar tus productos desde cero.'),
            onTap: () => Navigator.pop(ctx, 'plantilla'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (opcion == null || !context.mounted) return;
  if (opcion == 'exportar' || opcion == 'plantilla') {
    final excel = armarExcelProductos(opcion == 'exportar' ? productos : const []);
    await ExportService.guardarExcel(excel, opcion == 'exportar' ? 'inventario_${_hoy()}.xlsx' : 'plantilla_productos.xlsx');
    return;
  }

  final archivo = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf', 'jpg', 'jpeg', 'png'],
    withData: true, // en Web no hay ruta real, hacen falta los bytes.
  );
  final elegido = archivo?.files.single;
  if (elegido?.bytes == null || !context.mounted) return;

  var filas = leerArchivoProductos(elegido!.bytes!, elegido.name);
  if (filas == null) {
    filas = await _filasConIa(context, negocio, archivo: (elegido.bytes!, elegido.name));
    if (filas == null || !context.mounted) return;
  }
  if (filas.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No encontré productos en ese archivo.')));
    return;
  }
  final guardado = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => PantallaRevisionCarga(negocio: negocio, filas: filas!)),
  );
  if (guardado == true) onGuardado();
}

/// Lee un archivo con IA, o busca el CABYS que les falta a [filas]. Muestra
/// el avance y devuelve las filas (null si falló o se canceló).
Future<List<Map<String, dynamic>>?> _filasConIa(
  BuildContext context,
  Negocio negocio, {
  (Uint8List, String)? archivo,
  List<Map<String, dynamic>>? filas,
}) async {
  String jobId;
  try {
    final response = archivo != null
        ? await ApiService.postMultipartBytes(
            '/productos/importar-externo/', {'negocio': negocio.id.toString()}, 'archivo', archivo.$1, archivo.$2)
        : await ApiService.post('/productos/importar-externo/', {'negocio': negocio.id, 'filas': filas});
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 202) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail']?.toString() ?? 'No se pudo leer el archivo.')));
      }
      return null;
    }
    jobId = data['job_id'];
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    return null;
  }
  if (!context.mounted) return null;
  final estado = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoProgresoIa(jobId: jobId, leyendo: archivo != null),
  );
  if (estado == null) return null;
  if (estado['estado'] == 'error') {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo: ${estado['error']}')));
    }
    return null;
  }
  return [for (final f in (estado['filas'] as List? ?? [])) Map<String, dynamic>.from(f as Map)];
}

class _DialogoProgresoIa extends StatefulWidget {
  final String jobId;
  final bool leyendo;
  const _DialogoProgresoIa({required this.jobId, required this.leyendo});

  @override
  State<_DialogoProgresoIa> createState() => _DialogoProgresoIaState();
}

class _DialogoProgresoIaState extends State<_DialogoProgresoIa> {
  Timer? _timer;
  Map<String, dynamic> _estado = const {};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _consultar());
  }

  Future<void> _consultar() async {
    try {
      final r = await ApiService.get('/productos/importar-externo-estado/?job_id=${widget.jobId}');
      if (!mounted) return;
      if (r.statusCode == 404) {
        _timer?.cancel();
        Navigator.of(context).pop({'estado': 'error', 'error': 'el proceso expiró, intentá de nuevo.'});
        return;
      }
      if (r.statusCode != 200) return;
      final datos = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      setState(() => _estado = datos);
      if (datos['estado'] == 'listo' || datos['estado'] == 'error') {
        _timer?.cancel();
        Navigator.of(context).pop(datos);
      }
    } catch (_) {
      // Un fallo puntual de red no corta el seguimiento.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado['estado'] ?? (widget.leyendo ? 'leyendo' : 'resolviendo_cabys');
    final total = (_estado['total'] ?? 0) as int;
    final hechos = (_estado['procesados'] ?? 0) as int;
    final mensaje = estado == 'leyendo'
        ? 'Leyendo el archivo con IA...'
        : total > 0
            ? 'Buscando códigos CABYS: $hechos de $total'
            : 'Buscando códigos CABYS...';
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mensaje),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: estado != 'leyendo' && total > 0 ? hechos / total : null),
          const SizedBox(height: 10),
          Text('Puede tardar un par de minutos con listas largas.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

const Map<String, String> _nombreCampo = {
  'nombre': 'Nombre',
  'cabys': 'CABYS',
  'unidad': 'Unidad',
  'tipo': 'Tipo',
  'categoria': 'Categoría',
  'moneda': 'Moneda',
  'precio': 'Precio',
  'costo': 'Costo',
  'stock': 'Existencias',
  'iva': 'IVA',
};

const List<(double, String)> _tarifas = [(13, '13%'), (4, '4%'), (2, '2%'), (1, '1%'), (0, 'Exento')];

/// Lo que va a pasar con cada fila del archivo, para corregir antes de
/// guardar. Cada cambio vuelve a preguntarle al backend (que es el que
/// valida), así lo que se ve es exactamente lo que se va a guardar.
class PantallaRevisionCarga extends StatefulWidget {
  final Negocio negocio;
  final List<Map<String, dynamic>> filas;
  const PantallaRevisionCarga({super.key, required this.negocio, required this.filas});

  @override
  State<PantallaRevisionCarga> createState() => _PantallaRevisionCargaState();
}

class _PantallaRevisionCargaState extends State<PantallaRevisionCarga> {
  late List<Map<String, dynamic>> _filas;
  Map<String, dynamic>? _analisis;
  String? _error;
  bool _ocupado = false;
  double _ivaDefecto = 13;
  String? _filtro;

  @override
  void initState() {
    super.initState();
    _filas = [for (final f in widget.filas) Map<String, dynamic>.from(f)];
    _analizar();
  }

  Future<Map<String, dynamic>?> _llamar(bool confirmar) async {
    final r = await ApiService.post('/productos/carga-masiva/', {
      'negocio': widget.negocio.id,
      'filas': _filas,
      'iva_defecto': _ivaDefecto,
      'confirmar': confirmar,
    });
    final data = json.decode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) throw Exception(data['detail'] ?? 'Error del servidor: ${r.statusCode}');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> _analizar() async {
    setState(() => _ocupado = true);
    try {
      final a = await _llamar(false);
      if (mounted) {
        setState(() {
          _analisis = a;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  List<Map<String, dynamic>> get _resultado => [for (final f in (_analisis?['filas'] as List? ?? [])) Map<String, dynamic>.from(f as Map)];

  int _cuenta(String k) => ((_analisis?['resumen'] as Map?)?[k] ?? 0) as int;

  List<Map<String, dynamic>> get _sinCabys => _resultado
      .where((f) => (f['errores'] as List).any((e) => e.toString().startsWith('Falta el código CABYS')))
      .toList();

  Future<void> _buscarCabys() async {
    final indices = _sinCabys.map((f) => f['indice'] as int).toList();
    final nuevas = await _filasConIa(context, widget.negocio, filas: [for (final i in indices) _filas[i]]);
    if (nuevas == null || !mounted) return;
    var encontrados = 0;
    for (var k = 0; k < indices.length && k < nuevas.length; k++) {
      final cabys = (nuevas[k]['cabys'] ?? '').toString();
      if (cabys.isNotEmpty) {
        _filas[indices[k]]['cabys'] = cabys;
        encontrados++;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(encontrados == indices.length
          ? 'Listo: se encontró el CABYS de los $encontrados.'
          : 'Se encontró el CABYS de $encontrados de ${indices.length}. A los demás buscáselo tocándolos.'),
    ));
    await _analizar();
  }

  Future<void> _guardar() async {
    final nuevos = _cuenta('crear'), cambios = _cuenta('actualizar'), errores = _cuenta('errores');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Guardar la carga?'),
        content: Text([
          if (nuevos > 0) 'Se van a crear $nuevos productos.',
          if (cambios > 0) 'Se van a actualizar $cambios productos.',
          if (errores > 0) '$errores filas con error no se guardan.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir revisando')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      final r = await _llamar(true);
      if (!mounted) return;
      final partes = [
        if ((r!['creados'] ?? 0) > 0) '${r['creados']} creados',
        if ((r['actualizados'] ?? 0) > 0) '${r['actualizados']} actualizados',
      ];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Productos guardados: ${partes.join(' y ')}.'),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _ocupado = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
      }
    }
  }

  Future<void> _editar(Map<String, dynamic> resultado) async {
    final i = resultado['indice'] as int;
    final editada = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => _DialogoFila(fila: _filas[i], resultado: resultado),
    );
    if (editada == null) return;
    setState(() => _filas[i] = editada);
    await _analizar();
  }

  String _monto(dynamic v, String moneda) {
    final n = (v is num) ? v : double.tryParse(v.toString()) ?? 0;
    return moneda == 'USD' ? formatearDolares(n) : formatearColones(n);
  }

  String _valor(String campo, dynamic v, String moneda) {
    if (v == null || v == '') return '—';
    if (campo == 'precio' || campo == 'costo') return _monto(v, moneda);
    if (campo == 'iva') return (v as num) == 0 ? 'Exento' : '${formatearNumero(v, decimales: 0)}%';
    if (campo == 'tipo') return tiposProducto[v] ?? v.toString();
    if (campo == 'stock') return formatearNumero(v as num, decimales: 0);
    return v.toString();
  }

  Widget _chip(String clave, String texto, Color color) {
    final n = _cuenta(clave);
    final activo = _filtro == clave;
    return FilterChip(
      selected: activo,
      showCheckmark: false,
      label: Text('$texto  $n', style: TextStyle(color: activo ? Colors.white : color, fontWeight: FontWeight.w600)),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      onSelected: n == 0 ? null : (_) => setState(() => _filtro = activo ? null : clave),
    );
  }

  Widget _tarjeta(Map<String, dynamic> f) {
    final accion = f['accion'] as String;
    final datos = Map<String, dynamic>.from(f['datos'] as Map);
    final moneda = (datos['moneda'] ?? 'CRC').toString();
    final (etiqueta, color) = switch (accion) {
      'crear' => ('Nuevo', Colors.green.shade700),
      'actualizar' => ('Actualizar', AppColors.primary),
      'sin_cambios' => ('Sin cambios', AppColors.textMuted),
      _ => ('Error', Colors.red.shade700),
    };
    final lineas = <Widget>[];
    if (accion == 'crear' || (accion == 'error' && f['producto_id'] == null)) {
      lineas.add(Text(
        [
          if (datos['precio'] != null) _monto(datos['precio'], moneda),
          if (datos['iva'] != null) 'IVA ${_valor('iva', datos['iva'], moneda)}',
          if (datos['stock'] != null) '${_valor('stock', datos['stock'], moneda)} ${datos['unidad'] ?? 'Unid'}',
          if (datos['cabys'] != null) 'CABYS ${datos['cabys']}',
          if (datos['categoria'] != null) datos['categoria'],
        ].join(' · '),
        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      ));
    }
    for (final c in (f['cambios'] as List)) {
      final campo = c['campo'] as String;
      lineas.add(Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5), children: [
        TextSpan(text: '${_nombreCampo[campo] ?? campo}: ', style: TextStyle(color: AppColors.textMuted)),
        TextSpan(text: _valor(campo, c['antes'], moneda), style: TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.textMuted)),
        const TextSpan(text: '  →  '),
        TextSpan(text: _valor(campo, c['despues'], moneda), style: const TextStyle(fontWeight: FontWeight.w600)),
      ])));
    }
    for (final e in (f['errores'] as List)) {
      lineas.add(Text('• $e', style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)));
    }
    for (final a in (f['avisos'] as List)) {
      lineas.add(Text('• $a', style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800)));
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: accion == 'error' ? Colors.red.shade200 : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _ocupado ? null : () => _editar(f),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (f['nombre'] ?? '').toString().isEmpty ? 'Fila ${(f['indice'] as int) + 1}' : f['nombre'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    ...lineas,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(etiqueta, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _resultado.where((f) => _filtro == null || f['accion'] == (_filtro == 'errores' ? 'error' : _filtro)).toList();
    final aGuardar = _cuenta('crear') + _cuenta('actualizar');
    final sinCabys = _sinCabys.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar carga de productos'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        bottom: _ocupado ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        actions: const [BotonCalculadora()],
      ),
      body: _analisis == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _analizar, child: const Text('Reintentar')),
                      ]),
                    ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                  children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _chip('crear', 'Nuevos', Colors.green.shade700),
                      _chip('actualizar', 'A actualizar', AppColors.primary),
                      _chip('sin_cambios', 'Sin cambios', AppColors.textMuted),
                      _chip('errores', 'Con errores', Colors.red.shade700),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      children: [
                        const Text('IVA de los productos nuevos sin tarifa:', style: TextStyle(fontSize: 13.5)),
                        DropdownButton<double>(
                          value: _ivaDefecto,
                          isDense: true,
                          items: [for (final (v, t) in _tarifas) DropdownMenuItem(value: v, child: Text(t))],
                          onChanged: _ocupado
                              ? null
                              : (v) {
                                  setState(() => _ivaDefecto = v ?? 13);
                                  _analizar();
                                },
                        ),
                      ],
                    ),
                    if (sinCabys > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Row(children: [
                            Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text('A $sinCabys ${sinCabys == 1 ? 'producto le falta' : 'productos les falta'} el código CABYS. La IA puede buscarlo en el catálogo de Hacienda.', style: const TextStyle(fontSize: 13.5))),
                          ]),
                          const SizedBox(height: 8),
                          FilledButton.tonal(onPressed: _ocupado ? null : _buscarCabys, child: const Text('Buscarlos con IA')),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text('Tocá un producto para corregirlo.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    ...visibles.map(_tarjeta),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _analisis == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _ocupado || aGuardar == 0 ? null : _guardar,
                  icon: const Icon(Icons.check),
                  label: Text(aGuardar == 0 ? 'No hay nada para guardar' : 'Guardar $aGuardar ${aGuardar == 1 ? 'producto' : 'productos'}'),
                ),
              ),
            ),
    );
  }
}

/// Corregir una fila: lo que viene en el archivo, con buscador de CABYS.
/// "Quitar de la carga" la deja vacía (el backend salta las filas vacías).
class _DialogoFila extends StatefulWidget {
  final Map<String, dynamic> fila;
  final Map<String, dynamic> resultado;
  const _DialogoFila({required this.fila, required this.resultado});

  @override
  State<_DialogoFila> createState() => _DialogoFilaState();
}

class _DialogoFilaState extends State<_DialogoFila> {
  late final Map<String, TextEditingController> _c;
  String? _iva;

  @override
  void initState() {
    super.initState();
    final datos = Map<String, dynamic>.from(widget.resultado['datos'] as Map);
    String txt(String k) {
      final v = widget.fila[k] ?? datos[k];
      if (v == null) return '';
      if (v is double && v == v.roundToDouble()) return v.toStringAsFixed(0);
      return v.toString();
    }

    _c = {for (final k in ['nombre', 'cabys', 'precio', 'costo', 'stock', 'unidad', 'categoria']) k: TextEditingController(text: txt(k))};
    final iva = widget.fila['iva'];
    _iva = iva == null || iva.toString().trim().isEmpty ? null : iva.toString();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _campo(String k, String etiqueta, {TextInputType? teclado, Widget? sufijo}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[k],
          keyboardType: teclado,
          decoration: InputDecoration(labelText: etiqueta, isDense: true, border: const OutlineInputBorder(), suffixIcon: sufijo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const numeros = TextInputType.numberWithOptions(decimal: true);
    final ivaNum = double.tryParse((_iva ?? '').replaceAll('%', ''));
    final opcionesIva = [
      const DropdownMenuItem<String?>(value: null, child: Text('Sin cambiar / la de por defecto')),
      for (final (v, t) in _tarifas) DropdownMenuItem<String?>(value: v.toStringAsFixed(0), child: Text(t)),
    ];
    final valorIva = _iva == null
        ? null
        : _tarifas.any((t) => t.$1 == ivaNum)
            ? ivaNum!.toStringAsFixed(0)
            : (_iva!.toLowerCase().startsWith('exent') ? '0' : null);
    return AlertDialog(
      title: const Text('Corregir producto'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _campo('nombre', 'Nombre'),
            _campo('cabys', 'Código CABYS',
                teclado: TextInputType.number,
                sufijo: IconButton(
                  tooltip: 'Buscar CABYS',
                  icon: const Icon(Icons.search),
                  onPressed: () async {
                    final r = await mostrarBuscadorCabys(context);
                    if (r != null) setState(() => _c['cabys']!.text = r.codigo);
                  },
                )),
            Row(children: [
              Expanded(child: _campo('precio', 'Precio', teclado: numeros)),
              const SizedBox(width: 10),
              Expanded(child: _campo('costo', 'Costo', teclado: numeros)),
            ]),
            Row(children: [
              Expanded(child: _campo('stock', 'Existencias', teclado: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(child: _campo('unidad', 'Unidad')),
            ]),
            _campo('categoria', 'Categoría'),
            DropdownButtonFormField<String?>(
              initialValue: valorIva,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'IVA', isDense: true, border: OutlineInputBorder()),
              items: opcionesIva,
              onChanged: (v) => setState(() => _iva = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, <String, dynamic>{}),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Quitar de la carga'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final fila = Map<String, dynamic>.from(widget.fila);
            for (final e in _c.entries) {
              final t = e.value.text.trim();
              if (t.isEmpty) {
                fila.remove(e.key);
              } else {
                fila[e.key] = t;
              }
            }
            if (_iva == null) {
              fila.remove('iva');
            } else {
              fila['iva'] = _iva;
            }
            Navigator.pop(context, fila);
          },
          child: const Text('Listo'),
        ),
      ],
    );
  }
}
