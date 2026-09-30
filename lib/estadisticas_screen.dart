import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'theme/app_theme.dart';

/// Estadísticas del embudo de adquisición (solo superusuario): cuánta gente
/// visita el landing, cuántos tocan "Probar gratis", abren y envían el
/// registro, crean la cuenta y confirman el correo -- backend:
/// AnaliticaResumenView. Sin cookies ni datos personales (ver
/// EventoAnalitica).
///
/// Todo es una sola serie por gráfico, así que usa un único color
/// (AppColors.primary) y sin leyenda; los números van escritos en texto
/// normal al lado de cada barra, nunca solo en el color.
class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  int _dias = 30;
  Map<String, dynamic>? _datos;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await ApiService.get('/analitica/resumen/?dias=$_dias');
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => _datos = json.decode(utf8.decode(r.bodyBytes)));
      } else {
        setState(() => _error = "No se pudieron cargar las estadísticas (HTTP ${r.statusCode}).");
      }
    } catch (e) {
      if (mounted) setState(() => _error = "No se pudieron cargar las estadísticas: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ---------------------------------------------------------------- piezas

  Widget _tarjeta({required String titulo, String? subtitulo, required Widget hijo}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textStrong)),
          if (subtitulo != null) ...[
            const SizedBox(height: 2),
            Text(subtitulo, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 14),
          hijo,
        ],
      ),
    );
  }

  Widget _numeroDestacado(String etiqueta, String valor, String? pie) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Text(valor, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            if (pie != null) Text(pie, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
    );
  }

  /// Barra horizontal fina: etiqueta arriba, barra con punta redondeada de
  /// 4 px y el número al lado (en color de texto, no de la barra).
  Widget _barra(String etiqueta, int valor, int maximo, {String? extra, String? ayuda}) {
    final proporcion = maximo == 0 ? 0.0 : valor / maximo;
    final fila = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(etiqueta, style: TextStyle(fontSize: 13, color: AppColors.textStrong), overflow: TextOverflow.ellipsis)),
              Text("$valor", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              if (extra != null) ...[
                const SizedBox(width: 8),
                SizedBox(width: 64, child: Text(extra, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ],
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                Container(height: 10, width: c.maxWidth, decoration: BoxDecoration(color: AppColors.border.withOpacity(0.5), borderRadius: BorderRadius.circular(4))),
                Container(
                  height: 10,
                  width: valor == 0 ? 0 : (c.maxWidth * proporcion).clamp(4.0, c.maxWidth),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ayuda == null ? fila : Tooltip(message: ayuda, child: fila);
  }

  Widget _embudo(List pasos) {
    final maximo = pasos.isEmpty ? 0 : (pasos.first['personas'] as num).toInt();
    return Column(
      children: [
        for (var i = 0; i < pasos.length; i++)
          () {
            final n = (pasos[i]['personas'] as num).toInt();
            String? extra;
            String? ayuda;
            if (i > 0) {
              final anterior = (pasos[i - 1]['personas'] as num).toInt();
              if (anterior > 0) {
                final pct = (n * 100 / anterior).round();
                extra = "$pct% siguen";
                ayuda = "$pct% de los que \"${pasos[i - 1]['etiqueta']}\" llegaron a este paso";
              } else {
                extra = "—";
              }
            }
            return _barra(pasos[i]['etiqueta'], n, maximo, extra: extra, ayuda: ayuda);
          }(),
      ],
    );
  }

  Widget _visitasPorDia(List dias) {
    if (dias.isEmpty) return _vacio();
    final maximo = dias.map((d) => (d['personas'] as num).toInt()).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in dias)
                Expanded(
                  child: Tooltip(
                    message: "${_fechaCorta(d['dia'])}: ${d['personas']} visitante(s)",
                    child: Container(
                      // Área de toque más grande que la barra (toda la columna).
                      color: Colors.transparent,
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        heightFactor: maximo == 0 ? 0 : ((d['personas'] as num) / maximo).clamp(0.03, 1.0).toDouble(),
                        child: Container(
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(_fechaCorta(dias.first['dia']), style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const Spacer(),
            Text("máx. $maximo por día", style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const Spacer(),
            Text(_fechaCorta(dias.last['dia']), style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }

  Widget _ranking(List filas, {String Function(String)? nombre}) {
    if (filas.isEmpty) return _vacio();
    final maximo = (filas.first['personas'] as num).toInt();
    return Column(
      children: [
        for (final f in filas)
          _barra(nombre != null ? nombre(f['nombre'].toString()) : f['nombre'].toString(), (f['personas'] as num).toInt(), maximo),
      ],
    );
  }

  Widget _vacio() => Text("Todavía no hay datos en este periodo.", style: TextStyle(color: AppColors.textMuted, fontSize: 13));

  String _fechaCorta(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? "${int.parse(p[2])}/${int.parse(p[1])}" : iso;
  }

  static const _nombresZona = {
    'portada': 'Portada (arriba)',
    'menu': 'Menú de arriba',
    'banner': 'Franja de promoción',
    'novedades': 'Sección Novedades',
    'contadores': 'Sección Contadores',
    'despachos': 'Sección Despachos',
    'cierre': 'Cierre de la página',
    'pie': 'Pie de página',
  };

  String _nombreBoton(String detalle) {
    final partes = detalle.split(' / ');
    final zona = _nombresZona[partes.first] ?? partes.first;
    return partes.length > 1 && partes[1].isNotEmpty ? "$zona · ${partes[1]}" : zona;
  }

  String _nombreDispositivo(String d) => {'movil': 'Celular', 'escritorio': 'Computadora', 'app': 'App instalada'}[d] ?? d;

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final embudo = (_datos?['embudo'] as List?) ?? [];
    int paso(String tipo) => (embudo.firstWhere((p) => p['tipo'] == tipo, orElse: () => {'personas': 0})['personas'] as num).toInt();
    final visitas = paso('visita');
    final cuentas = paso('cuenta_creada');
    final verificadas = paso('correo_verificado');
    final conversion = visitas == 0 ? null : (cuentas * 100 / visitas);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Estadísticas del landing"),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: "Actualizar", onPressed: _cargar)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Filtro de periodo, arriba de todo.
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text("7 días")),
                  ButtonSegment(value: 30, label: Text("30 días")),
                  ButtonSegment(value: 90, label: Text("90 días")),
                ],
                selected: {_dias},
                onSelectionChanged: (s) {
                  setState(() => _dias = s.first);
                  _cargar();
                },
              ),
              const SizedBox(height: 16),
              if (_cargando)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red))
              else ...[
                LayoutBuilder(builder: (context, c) {
                  final tarjetas = [
                    _numeroDestacado("Visitantes", "$visitas", "personas distintas"),
                    _numeroDestacado("Cuentas creadas", "$cuentas", "$verificadas confirmaron el correo"),
                    _numeroDestacado("Conversión", conversion == null ? "—" : "${conversion.toStringAsFixed(conversion < 10 ? 1 : 0)}%", "de visitante a cuenta"),
                  ];
                  // En celular una debajo de la otra; en pantalla ancha, en fila.
                  if (c.maxWidth < 560) {
                    return Column(children: [for (final t in tarjetas) Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(width: double.infinity, child: t))]);
                  }
                  return Row(children: [
                    for (var i = 0; i < tarjetas.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: tarjetas[i]),
                    ],
                  ]);
                }),
                const SizedBox(height: 16),
                _tarjeta(
                  titulo: "Embudo de registro",
                  subtitulo: "Personas distintas en cada paso · el % es cuántos siguen desde el paso anterior",
                  hijo: _embudo(embudo),
                ),
                _tarjeta(titulo: "Visitantes por día", hijo: _visitasPorDia((_datos?['visitas_por_dia'] as List?) ?? [])),
                _tarjeta(
                  titulo: "¿De dónde llegan?",
                  subtitulo: "\"Directo\" incluye links abiertos desde WhatsApp y apps que no dicen de dónde vienen",
                  hijo: _ranking((_datos?['origenes'] as List?) ?? []),
                ),
                _tarjeta(
                  titulo: "¿Qué botón de \"Probar gratis\" usan?",
                  hijo: _ranking((_datos?['botones'] as List?) ?? [], nombre: _nombreBoton),
                ),
                _tarjeta(
                  titulo: "Dispositivo",
                  hijo: _ranking((_datos?['dispositivos'] as List?) ?? [], nombre: _nombreDispositivo),
                ),
                _tarjeta(
                  titulo: "Cuentas creadas por tipo",
                  hijo: _ranking((_datos?['cuentas_por_tipo'] as List?) ?? []),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
