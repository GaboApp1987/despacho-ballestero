import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'negocio.dart';
import 'tarjeta_lealtad.dart';

/// Tarjeta de lealtad del negocio: cómo funciona (puntos, sellos o las
/// dos), el QR para que los clientes se inscriban solos y guarden la
/// tarjeta en el Wallet, avisos a esos clientes y la lista de tarjetas.
class TarjetaLealtadScreen extends StatefulWidget {
  final Negocio negocio;
  const TarjetaLealtadScreen({super.key, required this.negocio});

  @override
  State<TarjetaLealtadScreen> createState() => _TarjetaLealtadScreenState();
}

const _colores = ['#1E3A8A', '#0F766E', '#15803D', '#7C2D12', '#B91C1C', '#9D174D', '#6D28D9', '#111827'];

Color _hex(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

String _colones(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '₡$b';
}

class _TarjetaLealtadScreenState extends State<TarjetaLealtadScreen> {
  bool _cargando = true;
  List<TarjetaLealtad> _tarjetas = [];
  ProgramaLealtad? _programa;
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _busquedaCtrl.addListener(() {
      setState(() => _busqueda = _busquedaCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final respuestas = await Future.wait([
        ApiService.get('/tarjetas-lealtad/?negocio=${widget.negocio.id}'),
        ApiService.get('/lealtad/programa/?negocio=${widget.negocio.id}'),
      ]);
      if (respuestas[0].statusCode == 200) {
        final data = json.decode(utf8.decode(respuestas[0].bodyBytes)) as List;
        _tarjetas = data.map((j) => TarjetaLealtad.fromJson(j)).toList();
      }
      if (respuestas[1].statusCode == 200) {
        _programa = ProgramaLealtad.fromJson(json.decode(utf8.decode(respuestas[1].bodyBytes)));
      }
    } catch (_) {
      // Si falla, simplemente se muestra la lista vacía.
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), backgroundColor: error ? Colors.red : null));
  }

  List<TarjetaLealtad> get _tarjetasFiltradas {
    if (_busqueda.isEmpty) return _tarjetas;
    final digitos = _busqueda.replaceAll(RegExp(r'\D'), '');
    return _tarjetas.where((t) =>
        t.clienteNombre.toLowerCase().contains(_busqueda) ||
        t.clienteCedula.toLowerCase().contains(_busqueda) ||
        t.codigo.toLowerCase() == _busqueda ||
        (digitos.length >= 4 && t.clienteTelefono.contains(digitos))).toList();
  }

  String _resumenPrograma(ProgramaLealtad p) {
    final partes = <String>[];
    if (p.usaPuntos) partes.add("1 punto por cada ${_colones(p.colonesPorPunto)}");
    if (p.usaSellos) {
      partes.add("1 sello por compra${p.montoMinimoSello > 0 ? ' desde ${_colones(p.montoMinimoSello)}' : ''}"
          "${p.premioSellos.isNotEmpty ? ' · ${p.sellosMeta} sellos = ${p.premioSellos}' : ' · meta de ${p.sellosMeta} sellos'}");
    }
    return partes.join('\n');
  }

  // ------------------------------------------------------------ Programa

  Future<void> _configurar() async {
    final p = _programa;
    if (p == null) return;
    var modo = p.modo;
    var color = p.color;
    final colonesCtrl = TextEditingController(text: '${p.colonesPorPunto}');
    final metaCtrl = TextEditingController(text: '${p.sellosMeta}');
    final premioCtrl = TextEditingController(text: p.premioSellos);
    final minimoCtrl = TextEditingController(text: p.montoMinimoSello > 0 ? '${p.montoMinimoSello}' : '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("Cómo funciona tu tarjeta"),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'puntos', label: Text("Puntos"), icon: Icon(Icons.stars_outlined)),
                      ButtonSegment(value: 'sellos', label: Text("Sellos"), icon: Icon(Icons.local_cafe_outlined)),
                      ButtonSegment(value: 'ambos', label: Text("Los dos")),
                    ],
                    selected: {modo},
                    onSelectionChanged: (s) => setD(() => modo = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (modo != 'sellos') ...[
                    TextField(
                      controller: colonesCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: "Colones de compra por cada punto", prefixText: "₡ ", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (modo != 'puntos') ...[
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: metaCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: "Sellos para el premio", border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: minimoCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: "Compra mínima", prefixText: "₡ ", hintText: "Cualquiera", border: OutlineInputBorder()),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: premioCtrl,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: "Premio", hintText: "Ej: 1 café gratis", border: OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text("Color de la tarjeta", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in _colores)
                        InkWell(
                          onTap: () => setD(() => color = c),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _hex(c),
                              shape: BoxShape.circle,
                              border: Border.all(color: color == c ? AppColors.textStrong : Colors.transparent, width: 3),
                            ),
                            child: color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
          ],
        ),
      ),
    );
    if (guardar != true) return;
    try {
      final r = await ApiService.patch('/lealtad/programa/?negocio=${widget.negocio.id}', {
        'modo': modo,
        'colones_por_punto': int.tryParse(colonesCtrl.text) ?? p.colonesPorPunto,
        'sellos_meta': int.tryParse(metaCtrl.text) ?? p.sellosMeta,
        'premio_sellos': premioCtrl.text.trim(),
        'monto_minimo_sello': int.tryParse(minimoCtrl.text) ?? 0,
        'color': color,
      });
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      setState(() => _programa = ProgramaLealtad.fromJson(json.decode(utf8.decode(r.bodyBytes))));
      _aviso("Listo, la tarjeta quedó actualizada.");
    } catch (e) {
      if (mounted) _aviso("No se pudo guardar: $e", error: true);
    }
  }

  Future<void> _imprimirCartel(ProgramaLealtad p) async {
    final doc = pw.Document();
    final color = PdfColor.fromHex(p.color);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(height: 10),
          pw.Text(widget.negocio.nombreComercial, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: color), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 6),
          pw.Text("Tarjeta de cliente frecuente", style: const pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 24),
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: p.urlPublica, width: 230, height: 230, color: PdfColors.black),
          pw.SizedBox(height: 24),
          pw.Text("Escaneá con la cámara de tu celular", style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(_resumenPrograma(p).replaceAll('\n', ' · ').replaceAll('₡', 'CRC '),
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
          pw.Spacer(),
          pw.Text("Guardala en Google Wallet o en la pantalla de inicio de tu iPhone",
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600), textAlign: pw.TextAlign.center),
        ],
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'QR_tarjeta_${widget.negocio.nombreComercial}.pdf');
  }

  void _verQr() {
    final p = _programa;
    if (p == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("QR para tus clientes"),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Pegalo en la caja o en las mesas. Al escanearlo, el cliente se inscribe con su nombre y teléfono y recibe su tarjeta "
                "para guardarla en Google Wallet (Android) o en la pantalla de inicio (iPhone).",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Image.network(p.qrPng, width: 220, height: 220, filterQuality: FilterQuality.none,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 220, child: Center(child: Icon(Icons.qr_code_2, size: 80)))),
              ),
              const SizedBox(height: 12),
              SelectableText(p.urlPublica, style: TextStyle(color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text("Copiar enlace"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: p.urlPublica));
              Navigator.pop(ctx);
              _aviso("Enlace copiado.");
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text("Imprimir cartel"),
            onPressed: () {
              Navigator.pop(ctx);
              _imprimirCartel(p);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _enviarAviso() async {
    final p = _programa;
    if (p == null) return;
    if (!p.googleWallet) {
      _aviso("Los avisos al Wallet todavía no están activados.");
      return;
    }
    if (p.enGoogleWallet == 0) {
      _aviso("Todavía ningún cliente tiene tu tarjeta en Google Wallet. Compartí el QR para que la guarden.");
      return;
    }
    final tituloCtrl = TextEditingController();
    final textoCtrl = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Aviso a tus clientes"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Les llega a los ${p.enGoogleWallet} ${p.enGoogleWallet == 1 ? 'cliente que tiene' : 'clientes que tienen'} tu tarjeta en Google Wallet "
                "(en Android como notificación). Te ${p.avisosDisponiblesHoy == 1 ? 'queda 1 aviso' : 'quedan ${p.avisosDisponiblesHoy} avisos'} por hoy.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(controller: tituloCtrl, maxLength: 60, autofocus: true,
                  decoration: const InputDecoration(labelText: "Título", hintText: "Ej: 2x1 en cafés hoy", border: OutlineInputBorder())),
              const SizedBox(height: 6),
              TextField(controller: textoCtrl, maxLength: 300, maxLines: 3,
                  decoration: const InputDecoration(labelText: "Mensaje", border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton.icon(
            icon: const Icon(Icons.send, size: 18),
            label: const Text("Enviar"),
            onPressed: p.avisosDisponiblesHoy > 0 ? () => Navigator.pop(ctx, true) : null,
          ),
        ],
      ),
    );
    if (enviar != true) return;
    try {
      final r = await ApiService.post('/lealtad/aviso/', {
        'negocio': widget.negocio.id,
        'titulo': tituloCtrl.text.trim(),
        'texto': textoCtrl.text.trim(),
      });
      if (r.statusCode != 201) throw Exception(ApiService.mensajeError(r));
      _aviso("Aviso enviado.");
      _cargarDatos();
    } catch (e) {
      if (mounted) _aviso("No se pudo enviar: $e", error: true);
    }
  }

  Widget _tarjetaPrograma(ProgramaLealtad p) {
    final ancho = MediaQuery.sizeOf(context).width;
    final botones = [
      OutlinedButton.icon(onPressed: _configurar, icon: const Icon(Icons.tune, size: 18), label: const Text("Configurar")),
      FilledButton.icon(onPressed: _verQr, icon: const Icon(Icons.qr_code_2, size: 18), label: const Text("QR para la caja")),
      OutlinedButton.icon(onPressed: _enviarAviso, icon: const Icon(Icons.campaign_outlined, size: 18), label: const Text("Enviar aviso")),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: _hex(p.color)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(p.usaSellos && !p.usaPuntos ? Icons.local_cafe_outlined : Icons.stars_outlined, color: _hex(p.color), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        p.modo == 'ambos' ? "Puntos y sellos" : (p.modo == 'sellos' ? "Sellos" : "Puntos"),
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong, fontSize: 15),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(_resumenPrograma(p), style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
                    const SizedBox(height: 6),
                    Text(
                      "${p.tarjetas} ${p.tarjetas == 1 ? 'cliente' : 'clientes'} con tarjeta"
                      "${p.googleWallet ? ' · ${p.enGoogleWallet} en Google Wallet' : ''}",
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: ancho < 420 ? botones.reversed.toList() : botones),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Tarjetas

  Future<void> _verMovimientos(TarjetaLealtad tarjeta) async {
    List<MovimientoLealtad> movimientos = [];
    try {
      final response = await ApiService.get('/tarjetas-lealtad/${tarjeta.id}/movimientos/');
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as List;
        movimientos = data.map((j) => MovimientoLealtad.fromJson(j)).toList();
      }
    } catch (_) {}

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Historial - ${tarjeta.clienteNombre}"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 320),
          child: movimientos.isEmpty
              ? const Center(child: Text("Sin movimientos todavía.", style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: movimientos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = movimientos[i];
                    final partes = [
                      if (m.puntos != 0) "${m.puntos > 0 ? '+' : ''}${m.puntos} pts",
                      if (m.sellos != 0) "${m.sellos > 0 ? '+' : ''}${m.sellos} ${m.sellos.abs() == 1 ? 'sello' : 'sellos'}",
                    ];
                    final positivo = m.puntos >= 0 && m.sellos >= 0;
                    return ListTile(
                      dense: true,
                      title: Text(m.etiquetaTipo),
                      subtitle: Text(m.descripcion.isEmpty ? m.fecha.split('T')[0] : "${m.descripcion} · ${m.fecha.split('T')[0]}"),
                      trailing: Text(
                        partes.join('\n'),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.bold, color: positivo ? Colors.green : Colors.red),
                      ),
                    );
                  },
                ),
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
      ),
    );
  }

  Future<void> _enviarAjuste(TarjetaLealtad tarjeta, Map<String, dynamic> datos) async {
    try {
      final response = await ApiService.post('/tarjetas-lealtad/${tarjeta.id}/ajustar/', datos);
      if (response.statusCode != 200) throw Exception(ApiService.mensajeError(response));
      _cargarDatos();
    } catch (e) {
      if (mounted) _aviso("No se pudo ajustar: $e", error: true);
    }
  }

  Future<void> _ajustarPuntos(TarjetaLealtad tarjeta, {required bool canjear}) async {
    final cantidadCtrl = TextEditingController();
    final descripcionCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(canjear ? "Canjear puntos" : "Agregar puntos"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${tarjeta.clienteNombre} tiene ${tarjeta.puntos} puntos.", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: cantidadCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              decoration: const InputDecoration(labelText: "Cantidad de puntos", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descripcionCtrl,
              decoration: InputDecoration(labelText: canjear ? "Canjeado por..." : "Motivo (opcional)", border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: canjear ? Colors.red : Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(canjear ? "Canjear" : "Agregar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final cantidad = int.tryParse(cantidadCtrl.text);
    if (cantidad == null || cantidad <= 0) {
      if (mounted) _aviso("Ingrese una cantidad válida de puntos.");
      return;
    }
    await _enviarAjuste(tarjeta, {'puntos': canjear ? -cantidad : cantidad, 'descripcion': descripcionCtrl.text.trim()});
  }

  Future<void> _canjearPremio(TarjetaLealtad tarjeta) async {
    final p = _programa!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Canjear premio"),
        content: Text("¿Entregar ${p.premioSellos.isNotEmpty ? p.premioSellos : 'el premio'} a ${tarjeta.clienteNombre}? "
            "Se le descuentan ${p.sellosMeta} sellos."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Canjear")),
        ],
      ),
    );
    if (ok == true) await _enviarAjuste(tarjeta, {'canjear_premio': true});
  }

  void _compartirTarjeta(TarjetaLealtad t) {
    if (t.url.isEmpty) return;
    final texto = "Tu tarjeta de cliente frecuente de ${widget.negocio.nombreComercial}: ${t.url}";
    Share.share(texto).catchError((_) {
      Clipboard.setData(ClipboardData(text: t.url));
      if (mounted) _aviso("Enlace copiado.");
      return ShareResult.unavailable;
    });
  }

  Widget _insignia(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12.5)),
      );

  Widget _fila(TarjetaLealtad t) {
    final p = _programa;
    final usaPuntos = p?.usaPuntos ?? true;
    final usaSellos = p?.usaSellos ?? false;
    final premioListo = usaSellos && t.sellos >= (p?.sellosMeta ?? 10);
    final subtitulo = [
      if (t.clienteCedula.isNotEmpty) t.clienteCedula,
      if (t.clienteTelefono.isNotEmpty) t.clienteTelefono,
      if (t.enGoogleWallet) "En Google Wallet",
    ].join(' · ');
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        leading: CircleAvatar(
          backgroundColor: Colors.amber.withValues(alpha: 0.15),
          child: Icon(premioListo ? Icons.redeem : Icons.card_giftcard, color: Colors.amber.shade700),
        ),
        title: Text(t.clienteNombre, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong)),
        subtitle: subtitulo.isEmpty ? null : Text(subtitulo, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (usaPuntos) _insignia("${t.puntos} pts", const Color(0xFFB7791F)),
            if (usaPuntos && usaSellos) const SizedBox(width: 6),
            if (usaSellos) _insignia("${t.sellos}/${p?.sellosMeta ?? 10}", premioListo ? const Color(0xFF15803D) : const Color(0xFF7C3AED)),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
              onSelected: (opcion) {
                switch (opcion) {
                  case 'agregar': _ajustarPuntos(t, canjear: false);
                  case 'canjear': _ajustarPuntos(t, canjear: true);
                  case 'sello': _enviarAjuste(t, {'sellos': 1, 'descripcion': 'Sello a mano'});
                  case 'premio': _canjearPremio(t);
                  case 'compartir': _compartirTarjeta(t);
                  case 'historial': _verMovimientos(t);
                }
              },
              itemBuilder: (context) => [
                if (usaPuntos) ...[
                  const PopupMenuItem(value: 'agregar', child: ListTile(leading: Icon(Icons.add, color: Colors.green), title: Text("Agregar puntos"), contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'canjear', child: ListTile(leading: Icon(Icons.remove, color: Colors.red), title: Text("Canjear puntos"), contentPadding: EdgeInsets.zero)),
                ],
                if (usaSellos) ...[
                  const PopupMenuItem(value: 'sello', child: ListTile(leading: Icon(Icons.approval_outlined, color: Color(0xFF7C3AED)), title: Text("Agregar sello"), contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(value: 'premio', enabled: premioListo, child: const ListTile(leading: Icon(Icons.redeem, color: Color(0xFF15803D)), title: Text("Canjear premio"), contentPadding: EdgeInsets.zero)),
                ],
                PopupMenuItem(value: 'compartir', child: ListTile(leading: Icon(Icons.share_outlined, color: AppColors.primary), title: const Text("Enviar su tarjeta"), contentPadding: EdgeInsets.zero)),
                PopupMenuItem(value: 'historial', child: ListTile(leading: Icon(Icons.history, color: AppColors.primary), title: const Text("Ver historial"), contentPadding: EdgeInsets.zero)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _tarjetasFiltradas;
    return Container(
      color: AppColors.surfaceSubtle,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Icon(Icons.loyalty_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                Text("Tarjeta de Lealtad", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos, tooltip: "Actualizar"),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      if (_programa != null) _tarjetaPrograma(_programa!),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: TextField(
                          controller: _busquedaCtrl,
                          decoration: InputDecoration(
                            hintText: "Buscar por nombre, cédula, teléfono o código...",
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      if (filtradas.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              _tarjetas.isEmpty
                                  ? "Todavía no hay clientes con tarjeta.\nCompartí el QR para que se inscriban."
                                  : "No se encontraron clientes con ese criterio.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        )
                      else
                        for (final t in filtradas)
                          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: _fila(t)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
