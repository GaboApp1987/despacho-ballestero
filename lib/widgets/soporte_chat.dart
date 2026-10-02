import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../theme/app_theme.dart';
import '../api_service.dart';
import '../formato.dart';
import '../export_service.dart';
import '../factura.dart';
import 'adjuntos_ia.dart';
import 'asistente_flotante.dart';

/// Abre el chat de soporte con IA en una hoja modal -- se puede llamar desde
/// cualquier pantalla (login, o ya adentro de la app). `contexto` cambia el
/// tono del asistente ('visitante' antes de iniciar sesión, 'usuario' ya
/// logueado, ver _SOPORTE_SYSTEM_PROMPT_* en el backend). `negocioId` es
/// opcional y solo se manda si hay uno logueado, para que un mensaje que
/// deje el usuario quede asociado a su negocio.
///
/// Desde la barra "¿Qué querés hacer hoy?" de los dashboards (ver
/// widgets/asistente_ia_bar.dart) se abre en modo asistente: con la
/// pregunta ya enviada (`mensajeInicial`), las secciones de ese perfil
/// (`secciones`, clave -> descripción) para que la IA pueda proponer abrir
/// una, y `onNavegar` para llevar a la persona ahí al tocar el botón.
/// `adjuntosIniciales`: nota de voz o archivos que ya vienen de la barra.
///
/// Se le puede hablar con notas de voz (la IA las escucha y contesta, sin
/// mostrar la transcripción, y la respuesta se lee en voz alta) y mandarle
/// fotos, PDF o Excel -- ver adjuntos_ia.dart y gestion/ia_adjuntos.py.
Future<void> mostrarSoporteChat(
  BuildContext context, {
  required String contexto,
  int? negocioId,
  String? mensajeInicial,
  List<AdjuntoIA> adjuntosIniciales = const [],
  Map<String, String>? secciones,
  void Function(String clave)? onNavegar,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SoporteChatSheet(
      contexto: contexto,
      negocioId: negocioId,
      mensajeInicial: mensajeInicial,
      adjuntosIniciales: adjuntosIniciales,
      secciones: secciones,
      onNavegar: onNavegar,
    ),
  );
}

/// El asistente como pantalla propia (estilo Claude/Gemini): lo primero que
/// se ve al iniciar sesión (ver AsistenteIABar) y desde ahí "Ir al panel".
/// Misma conversación, herramientas y adjuntos que el chat en hoja, con
/// diseño de pantalla completa.
Future<void> abrirAsistentePantalla(
  BuildContext context, {
  int? negocioId,
  required Map<String, String> secciones,
  required void Function(String clave) onNavegar,
  List<(IconData, String)> sugerencias = const [],
  String? saludo,
  String? mensajeInicial,
  List<AdjuntoIA> adjuntosIniciales = const [],
  bool empezarGrabando = false,
}) {
  AsistenteFlotante.abierto.value = true;
  return Navigator.of(context).push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => _SoporteChatSheet(
      contexto: 'usuario',
      negocioId: negocioId,
      mensajeInicial: mensajeInicial,
      adjuntosIniciales: adjuntosIniciales,
      secciones: secciones,
      onNavegar: onNavegar,
      pantallaCompleta: true,
      saludo: saludo,
      sugerencias: sugerencias,
      empezarGrabando: empezarGrabando,
    ),
    transitionsBuilder: (_, animacion, __, child) {
      final curva = CurvedAnimation(parent: animacion, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curva,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(curva), child: child),
      );
    },
  )).whenComplete(() => AsistenteFlotante.abierto.value = false);
}

class _ChatMensaje {
  final String role; // 'user' | 'assistant'
  final String content;
  final _PropuestaFactura? propuesta;
  final _PropuestaProducto? propuestaProducto;
  // Sección que la IA propuso abrir (clave de `secciones`), ver "navegar"
  // en SoporteChatView.
  final String? navegar;
  // Acción genérica que la IA dejó lista para confirmar (crear cliente,
  // registrar gasto o abono...), ver asistente_acciones.py en el backend.
  final Map<String, dynamic>? propuestaAccion;
  String estadoAccion = 'pendiente';
  // Reporte/documento descargable que preparó la IA (ver preparar_reporte
  // en asistente_acciones.py); se arma acá con ExportService.
  final Map<String, dynamic>? propuestaDocumento;
  String? descargando; // 'pdf' | 'excel' mientras se genera
  // 'pendiente' | 'creando' | 'creada' -- aplica a `propuesta` (factura).
  String estadoPropuesta = 'pendiente';
  // 'pendiente' | 'creando' | 'creada' -- aplica a `propuestaProducto`.
  String estadoPropuestaProducto = 'pendiente';
  // Nota de voz / archivos que mandó la persona (solo se muestran acá).
  final List<AdjuntoIA> adjuntos;
  // Lo que el backend devuelve sobre esos adjuntos (ej. lo que dijo la nota
  // de voz): nunca se muestra, pero viaja en el historial para que la IA
  // lo recuerde en los turnos siguientes.
  String? notaOculta;
  _ChatMensaje(this.role, this.content,
      {this.propuesta, this.propuestaProducto, this.navegar, this.propuestaAccion, this.propuestaDocumento, this.adjuntos = const []});

  Map<String, String> toJson() => {
        'role': role,
        'content': [content, notaOculta ?? ''].where((t) => t.trim().isNotEmpty).join('\n'),
      };
}

/// Borrador de producto que arma el chat (herramienta preparar_producto del
/// backend) con un código CABYS real ya buscado -- igual que
/// _PropuestaFactura, nunca se crea sola, el usuario la confirma con un
/// botón (ver _confirmarProducto).
class _PropuestaProducto {
  final String nombre;
  final String codigoCabys;
  final String codigoCabysDescripcion;
  final String unidadMedida;
  final double precioUnitario;
  final double costo;
  final double margenGanancia;
  final int stock;
  final int? categoriaId;
  final String? categoriaNombre;
  final int impuestoId;
  final String impuestoNombre;
  // Negocio del cliente cuando lo arma el asistente del contador.
  final int? negocioId;
  final String? negocioNombre;
  _PropuestaProducto({
    this.negocioId,
    this.negocioNombre,
    required this.nombre,
    required this.codigoCabys,
    required this.codigoCabysDescripcion,
    required this.unidadMedida,
    required this.precioUnitario,
    required this.costo,
    required this.margenGanancia,
    required this.stock,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.impuestoId,
    required this.impuestoNombre,
  });

  factory _PropuestaProducto.fromJson(Map<String, dynamic> json) {
    return _PropuestaProducto(
      nombre: json['nombre'] ?? '',
      codigoCabys: json['codigo_cabys'] ?? '',
      codigoCabysDescripcion: json['codigo_cabys_descripcion'] ?? '',
      unidadMedida: json['unidad_medida'] ?? 'Unid',
      precioUnitario: (json['precio_unitario'] as num).toDouble(),
      costo: (json['costo'] as num? ?? 0).toDouble(),
      margenGanancia: (json['margen_ganancia'] as num? ?? 30).toDouble(),
      stock: (json['stock'] as num? ?? 0).toInt(),
      categoriaId: json['categoria_id'],
      categoriaNombre: json['categoria_nombre'],
      impuestoId: json['impuesto_id'],
      impuestoNombre: json['impuesto_nombre'] ?? '',
      negocioId: json['negocio_id'],
      negocioNombre: json['negocio_nombre'],
    );
  }
}

/// Borrador de factura que arma el chat (herramienta preparar_factura del
/// backend) a partir de productos/cliente reales del catálogo -- nunca se
/// crea sola, el usuario la confirma con un botón (ver _confirmarFactura).
class _PropuestaFactura {
  // null = Tiquete Electrónico a consumidor final (sin cliente).
  final int? clienteId;
  final String clienteNombre;
  final String clienteCedula;
  final List<Map<String, dynamic>> items;
  final String tipoDocumento; // '01' factura | '04' tiquete
  final String condicionVenta; // '01' contado | '02' crédito
  final int plazoCredito;
  final String medioPago; // '01' efectivo | '02' tarjeta | '03' cheque | '04' transferencia
  // Negocio del cliente cuando la arma el asistente del contador.
  final int? negocioId;
  final String? negocioNombre;
  // Los precios de `items` van SIEMPRE en colones (igual que el formulario
  // de factura); en una factura en dólares se muestran divididos por esto.
  final String moneda; // 'CRC' | 'USD'
  final double tipoCambio;
  _PropuestaFactura({
    this.negocioId,
    this.negocioNombre,
    this.moneda = 'CRC',
    this.tipoCambio = 1.0,
    required this.clienteId,
    required this.clienteNombre,
    required this.clienteCedula,
    required this.items,
    this.tipoDocumento = '01',
    this.condicionVenta = '01',
    this.plazoCredito = 0,
    this.medioPago = '01',
  });

  factory _PropuestaFactura.fromJson(Map<String, dynamic> json) {
    return _PropuestaFactura(
      clienteId: json['cliente_id'],
      clienteNombre: json['cliente_nombre'] ?? '',
      clienteCedula: json['cliente_cedula'] ?? '',
      items: (json['items'] as List).cast<Map<String, dynamic>>(),
      tipoDocumento: json['tipo_documento'] ?? '01',
      condicionVenta: json['condicion_venta'] ?? '01',
      plazoCredito: (json['plazo_credito'] as num? ?? 0).toInt(),
      medioPago: json['medio_pago'] ?? '01',
      negocioId: json['negocio_id'],
      negocioNombre: json['negocio_nombre'],
      moneda: json['moneda'] == 'USD' ? 'USD' : 'CRC',
      tipoCambio: (json['tipo_cambio'] as num?)?.toDouble() ?? 1.0,
    );
  }

  bool get enDolares => moneda == 'USD' && tipoCambio > 1;
  /// Un monto (en colones) en la moneda de la factura.
  String formatear(num colones) => enDolares ? formatearDolares(colones / tipoCambio) : formatearColones(colones);

  bool get esTiquete => tipoDocumento == '04';
  bool get esCredito => condicionVenta == '02';
  String get medioPagoNombre => const {'01': 'efectivo', '02': 'tarjeta', '03': 'cheque', '04': 'transferencia'}[medioPago] ?? 'efectivo';

  double get subtotal => items.fold(0.0, (s, it) => s + (it['precio_unitario'] as num) * (it['cantidad'] as num));
  double get montoIva => items.fold(
      0.0, (s, it) => s + (it['precio_unitario'] as num) * (it['cantidad'] as num) * ((it['impuesto_porcentaje'] as num? ?? 0) / 100));
  double get total => subtotal + montoIva;
}

class _SoporteChatSheet extends StatefulWidget {
  final String contexto;
  final int? negocioId;
  final String? mensajeInicial;
  final List<AdjuntoIA> adjuntosIniciales;
  final Map<String, String>? secciones;
  final void Function(String clave)? onNavegar;
  // Solo en pantalla completa (ver abrirAsistentePantalla).
  final bool pantallaCompleta;
  final String? saludo;
  final List<(IconData, String)> sugerencias;
  final bool empezarGrabando;
  const _SoporteChatSheet({
    required this.contexto,
    this.negocioId,
    this.mensajeInicial,
    this.adjuntosIniciales = const [],
    this.secciones,
    this.onNavegar,
    this.pantallaCompleta = false,
    this.saludo,
    this.sugerencias = const [],
    this.empezarGrabando = false,
  });

  bool get modoAsistente => secciones != null;

  @override
  State<_SoporteChatSheet> createState() => _SoporteChatSheetState();
}

class _SoporteChatSheetState extends State<_SoporteChatSheet> with SingleTickerProviderStateMixin {
  late final List<_ChatMensaje> _mensajes = [
    _ChatMensaje(
      'assistant',
      widget.modoAsistente
          ? '¡Hola! Soy el asistente de Equilibra. Preguntame lo que necesites o pedime que haga algo por vos.'
          : '¡Hola! Soy el asistente de soporte de Equilibra. ¿En qué te ayudo?',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Viene de la barra del dashboard: la pregunta ya se escribió afuera,
    // se manda apenas se abre el panel.
    final inicial = widget.mensajeInicial?.trim() ?? '';
    if (inicial.isNotEmpty || widget.adjuntosIniciales.isNotEmpty) {
      _inputCtrl.text = inicial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _enviarMensaje(adjuntos: widget.adjuntosIniciales));
    }
    _inputCtrl.addListener(() => setState(() {}));
    if (widget.empezarGrabando) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _empezarAGrabar());
    }
  }
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _enviando = false;
  // Respuesta que va llegando en vivo (ver ApiService.postEnVivo) y lo que
  // el asistente está consultando ("Buscando tus facturas…").
  String _parcial = '';
  String? _estadoVivo;

  // Notas de voz (ver adjuntos_ia.dart) y archivos pendientes de mandar.
  // `_pulseCtrl` anima el aro del micrófono mientras la IA habla.
  GrabadorVoz? _grabador;
  bool _grabando = false;
  final List<AdjuntoIA> _pendientes = [];
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  // Salida por voz: si le hablaste con una nota de voz, la respuesta se
  // lee en voz alta. Tocar el micrófono mientras habla la interrumpe.
  final FlutterTts _tts = FlutterTts();
  bool _ttsListo = false;
  bool _hablando = false;

  Future<void> _prepararTts() async {
    if (_ttsListo) return;
    await _tts.setLanguage('es-CR');
    await _tts.setSpeechRate(0.5);
    try {
      // Si "es-CR" no está instalado en el motor de voz del sistema, cae a
      // cualquier variante de español disponible antes que quedarse mudo.
      final voces = await _tts.getLanguages;
      final idiomas = (voces as List).cast<String>();
      if (!idiomas.any((l) => l.toLowerCase() == 'es-cr')) {
        final esAlternativo = idiomas.firstWhere((l) => l.toLowerCase().startsWith('es'), orElse: () => '');
        if (esAlternativo.isNotEmpty) await _tts.setLanguage(esAlternativo);
      }
    } catch (_) {
      // Sin lista de idiomas disponible -- seguimos con 'es-CR' igual.
    }
    _tts.setStartHandler(() {
      if (mounted) setState(() => _hablando = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _hablando = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _hablando = false);
    });
    _tts.setErrorHandler((msg) {
      if (mounted) setState(() => _hablando = false);
    });
    _ttsListo = true;
  }

  Future<void> _hablar(String texto) async {
    if (texto.trim().isEmpty) return;
    await _prepararTts();
    await _tts.stop();
    await _tts.speak(texto);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _pulseCtrl.dispose();
    _grabador?.cancelar();
    _grabador?.dispose();
    if (_ttsListo) _tts.stop();
    super.dispose();
  }

  Future<void> _empezarAGrabar() async {
    if (_hablando) {
      await _tts.stop();
      return;
    }
    final grabador = _grabador ??= GrabadorVoz();
    try {
      if (!await grabador.iniciar()) throw Exception('sin permiso');
      if (mounted) setState(() => _grabando = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No pude usar el micrófono. Revisá que el navegador o Windows le den permiso a Equilibra.'),
        duration: Duration(seconds: 6),
      ));
    }
  }

  Future<void> _mandarNotaDeVoz() async {
    if (!_grabando) return;
    setState(() => _grabando = false);
    final nota = await _grabador!.detener();
    if (nota != null && mounted) _enviarMensaje(adjuntos: [..._pendientes, nota]);
  }

  Future<void> _descartarNotaDeVoz() async {
    setState(() => _grabando = false);
    await _grabador?.cancelar();
  }

  Future<void> _adjuntar() async {
    final archivos = await elegirArchivosParaIA(context);
    if (archivos.isEmpty || !mounted) return;
    setState(() {
      _pendientes.addAll(archivos);
      if (_pendientes.length > 5) _pendientes.removeRange(0, _pendientes.length - 5);
    });
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _enviarMensaje({List<AdjuntoIA>? adjuntos}) async {
    final texto = _inputCtrl.text.trim();
    final adj = adjuntos ?? List.of(_pendientes);
    if ((texto.isEmpty && adj.isEmpty) || _enviando) return;
    final porVoz = adj.any((a) => a.esAudio);
    final mensajeUsuario = _ChatMensaje('user', texto, adjuntos: adj);
    setState(() {
      _mensajes.add(mensajeUsuario);
      _inputCtrl.clear();
      _pendientes.clear();
      _enviando = true;
    });
    _scrollAlFinal();

    try {
      // La respuesta va apareciendo mientras la IA la escribe (como en
      // Claude/Gemini) en vez de esperar a que esté completa.
      Map<String, dynamic>? datosFin;
      await for (final evento in ApiService.postEnVivo('/soporte/chat/', {
        'mensajes': _mensajes.map((m) => m.toJson()).toList(),
        'contexto': widget.contexto,
        if (widget.negocioId != null) 'negocio': widget.negocioId,
        if (widget.secciones != null) 'secciones': widget.secciones,
        if (adj.isNotEmpty) 'adjuntos': adj.map((a) => a.toJson()).toList(),
        'stream': true,
      })) {
        if (!mounted) return;
        switch (evento['tipo']) {
          case 'texto':
            setState(() {
              _parcial += '${evento['dato'] ?? ''}';
              _estadoVivo = null;
            });
            _scrollAlFinal();
          case 'estado':
            // Lo que alcanzó a decir antes de consultar ("Déjame ver…") se
            // reemplaza por lo que está haciendo.
            setState(() {
              _parcial = '';
              _estadoVivo = '${evento['dato'] ?? ''}';
            });
          case 'fin':
            datosFin = Map<String, dynamic>.from(evento['dato'] as Map);
          case 'error':
            throw Exception(evento['dato'] ?? 'Error desconocido');
        }
      }
      final data = datosFin ?? (throw Exception('La respuesta se cortó. Probá de nuevo.'));
      final propuestaJson = data['propuesta_factura'];
      final propuestaProductoJson = data['propuesta_producto'];
      final respuesta = data['respuesta'] ?? '';
      mensajeUsuario.notaOculta = data['nota_adjuntos'] as String?;
      _parcial = '';
      _estadoVivo = null;
      setState(() => _mensajes.add(_ChatMensaje(
            'assistant',
            respuesta,
            propuesta: propuestaJson != null ? _PropuestaFactura.fromJson(propuestaJson) : null,
            propuestaProducto: propuestaProductoJson != null ? _PropuestaProducto.fromJson(propuestaProductoJson) : null,
            navegar: data['navegar'] as String?,
            propuestaAccion: data['propuesta_accion'] is Map ? Map<String, dynamic>.from(data['propuesta_accion']) : null,
            propuestaDocumento: data['propuesta_documento'] is Map ? Map<String, dynamic>.from(data['propuesta_documento']) : null,
          )));
      // Si le hablaste con una nota de voz, te contesta en voz alta.
      if (porVoz) _hablar(respuesta);
      // La IA marca cuando detecta que no puede resolver algo sola (ver
      // sugerir_contacto en el backend) -- se abre el formulario solo en
      // vez de esperar a que la persona note el botón de abajo.
      if (data['sugerir_contacto'] == true && mounted) _abrirDejarMensaje();
    } catch (e) {
      const mensajeError = 'No pude responder ahora mismo. Podés dejar tu mensaje con el botón de abajo y te contactamos.';
      setState(() => _mensajes.add(_ChatMensaje('assistant', '$mensajeError ($e)')));
      if (porVoz) _hablar(mensajeError);
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
          _parcial = '';
          _estadoVivo = null;
        });
      }
      _scrollAlFinal();
    }
  }

  /// Lo que va llegando, sin las marcas internas ([[ABRIR:...]] y demás)
  /// que el servidor quita de la respuesta final.
  String get _parcialVisible {
    final i = _parcial.indexOf('[[');
    return (i == -1 ? _parcial : _parcial.substring(0, i)).trimRight();
  }

  /// Crea de verdad la factura que el chat propuso, solo cuando el usuario
  /// toca "Confirmar" en la tarjeta de la propuesta -- de contado siempre
  /// (ver _SOPORTE_SYSTEM_PROMPT_USUARIO en el backend), reusando el mismo
  /// endpoint que el formulario normal de factura.
  Future<void> _confirmarFactura(_ChatMensaje mensaje) async {
    final propuesta = mensaje.propuesta!;
    setState(() => mensaje.estadoPropuesta = 'creando');
    try {
      final body = {
        'negocio': propuesta.negocioId ?? widget.negocioId,
        'cliente': propuesta.clienteId,
        'consecutivo': '',
        'tipo_documento': propuesta.tipoDocumento,
        'receptor_nombre': propuesta.clienteNombre,
        'receptor_cedula': propuesta.clienteCedula,
        'total_iva': redondear2(propuesta.montoIva),
        'total_factura': redondear2(propuesta.total),
        'moneda': propuesta.enDolares ? 'USD' : 'CRC',
        'tipo_cambio': propuesta.enDolares ? propuesta.tipoCambio : 1.0,
        'condicion_venta': propuesta.condicionVenta,
        'plazo_credito': propuesta.plazoCredito,
        'medio_pago': propuesta.medioPago,
        'detalles': propuesta.items.map((it) {
          final subtotalItem = (it['precio_unitario'] as num) * (it['cantidad'] as num);
          final ivaItem = subtotalItem * ((it['impuesto_porcentaje'] as num? ?? 0) / 100);
          return {
            'producto': it['producto_id'],
            'cantidad': it['cantidad'],
            'precio_unitario': redondear2(it['precio_unitario'] as num),
            'monto_iva': redondear2(ivaItem),
            'subtotal': redondear2(subtotalItem),
          };
        }).toList(),
      };
      final response = await ApiService.post('/facturas/', body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        setState(() => mensaje.estadoPropuesta = 'creada');
        _mensajes.add(_ChatMensaje('assistant', propuesta.esTiquete ? '¡Listo! Tiquete emitido y enviado a Hacienda.' : '¡Listo! Factura creada y enviada a Hacienda.'));
        setState(() {});
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      setState(() => mensaje.estadoPropuesta = 'pendiente');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la factura: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      _scrollAlFinal();
    }
  }

  /// Crea de verdad el producto que el chat propuso, solo cuando el usuario
  /// toca "Confirmar" en la tarjeta de la propuesta -- reusa el mismo
  /// endpoint que el formulario normal de producto (ver crear_producto.dart).
  Future<void> _confirmarProducto(_ChatMensaje mensaje) async {
    final propuesta = mensaje.propuestaProducto!;
    setState(() => mensaje.estadoPropuestaProducto = 'creando');
    try {
      final response = await ApiService.post('/productos/', {
        'negocio': propuesta.negocioId ?? widget.negocioId,
        'nombre': propuesta.nombre,
        'codigo_cabys': propuesta.codigoCabys,
        'unidad_medida': propuesta.unidadMedida,
        'precio_unitario': propuesta.precioUnitario,
        'costo': propuesta.costo,
        'margen_ganancia': propuesta.margenGanancia,
        'stock': propuesta.stock,
        'categoria': propuesta.categoriaId,
        'impuesto': propuesta.impuestoId,
      });
      if (response.statusCode == 201 || response.statusCode == 200) {
        setState(() => mensaje.estadoPropuestaProducto = 'creada');
        _mensajes.add(_ChatMensaje('assistant', '¡Listo! Producto "${propuesta.nombre}" agregado al catálogo.'));
        setState(() {});
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      setState(() => mensaje.estadoPropuestaProducto = 'pendiente');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear el producto: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      _scrollAlFinal();
    }
  }

  Future<void> _abrirDejarMensaje() async {
    final nombreCtrl = TextEditingController();
    final correoCtrl = TextEditingController();
    final mensajeCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dejar mensaje para el equipo'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo *'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Ingresá un correo válido' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: mensajeCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Mensaje *', alignLabelWithHint: true),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Contanos qué necesitás' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (enviar != true) return;

    final transcripcion = _mensajes.map((m) => "${m.role == 'user' ? 'Yo' : 'IA'}: ${m.toJson()['content']}").join('\n');
    try {
      final response = await ApiService.post('/soporte/contacto/', {
        'nombre': nombreCtrl.text.trim(),
        'correo': correoCtrl.text.trim(),
        'mensaje': mensajeCtrl.text.trim(),
        'origen': widget.contexto == 'usuario' ? 'app' : 'login',
        'transcripcion': transcripcion,
        if (widget.negocioId != null) 'negocio': widget.negocioId,
      });
      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Listo! En breve te contactamos.'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception('Error ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo enviar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildTarjetaPropuesta(_ChatMensaje mensaje) {
    final propuesta = mensaje.propuesta!;
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(propuesta.esTiquete ? 'Borrador de tiquete' : 'Borrador de factura', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          if (propuesta.negocioNombre != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Emite: ${propuesta.negocioNombre}', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          Text(propuesta.esTiquete ? 'Consumidor final (sin cliente)' : 'Cliente: ${propuesta.clienteNombre}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          ...propuesta.items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${it['cantidad']} x ${it['nombre_producto']} (${propuesta.formatear(it['precio_unitario'] as num)})',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                propuesta.esCredito ? 'Total (crédito ${propuesta.plazoCredito} días)' : 'Total (contado, ${propuesta.medioPagoNombre})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(propuesta.formatear(propuesta.total), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
            ],
          ),
          if (propuesta.enDolares)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Factura en dólares · tipo de cambio ${formatearNumero(propuesta.tipoCambio)} (≈ ${formatearColones(propuesta.total)})',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 10),
          if (mensaje.estadoPropuesta == 'creada')
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text('Emitida', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: mensaje.estadoPropuesta == 'creando' ? null : () => _confirmarFactura(mensaje),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                child: mensaje.estadoPropuesta == 'creando'
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(propuesta.esTiquete ? 'Confirmar y emitir tiquete' : 'Confirmar y crear factura',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTarjetaPropuestaProducto(_ChatMensaje mensaje) {
    final propuesta = mensaje.propuestaProducto!;
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text('Borrador de producto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          if (propuesta.negocioNombre != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Para: ${propuesta.negocioNombre}', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          Text(propuesta.nombre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'CABYS ${propuesta.codigoCabys} · ${propuesta.codigoCabysDescripcion}',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            '${propuesta.categoriaNombre ?? 'Sin categoría'} · ${propuesta.impuestoNombre} · ${propuesta.unidadMedida} · Stock inicial ${propuesta.stock}',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Precio de venta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(formatearColones(propuesta.precioUnitario), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          if (mensaje.estadoPropuestaProducto == 'creada')
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text('Producto creado', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: mensaje.estadoPropuestaProducto == 'creando' ? null : () => _confirmarProducto(mensaje),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                child: mensaje.estadoPropuestaProducto == 'creando'
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Confirmar y crear producto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  // Solo estas rutas puede tocar una propuesta del chat (las mismas de los
  // formularios normales, con sus permisos y validaciones) -- ver
  // asistente_acciones.py en el backend.
  static final _rutasPost = RegExp(
      r'^/(clientes|gastos-operativos|abonos|abonos-proveedor|cotizaciones|notas-credito|ingresos-operativos|proveedores)/$'
      r'|^/facturas/\d+/(reenviar-hacienda|consultar-hacienda)/$'
      r'|^/compras/registrar-desde-asistente/$');
  static final _rutasPatch = RegExp(r'^/productos/\d+/$');
  static const _estadosHacienda = {
    '1': 'Sin enviar', '2': 'Enviando', '3': 'Aceptada', '4': 'Rechazada', '5': 'Error técnico', '6': 'No aplica (interno)',
  };

  Future<void> _confirmarAccion(_ChatMensaje mensaje) async {
    final accion = mensaje.propuestaAccion!;
    final endpoint = accion['endpoint'] as String? ?? '';
    final esPatch = (accion['metodo'] as String?)?.toUpperCase() == 'PATCH';
    if (!(esPatch ? _rutasPatch : _rutasPost).hasMatch(endpoint)) return;
    setState(() => mensaje.estadoAccion = 'creando');
    try {
      final datos = Map<String, dynamic>.from(accion['datos'] as Map? ?? {});
      final response = esPatch ? await ApiService.patch(endpoint, datos) : await ApiService.post(endpoint, datos);
      if (response.statusCode == 201 || response.statusCode == 200) {
        var exito = (accion['exito'] as String?) ?? '¡Listo!';
        // Reenviar/consultar en Hacienda: decir cómo quedó.
        if (accion['mostrar_estado_hacienda'] == true) {
          try {
            final cuerpo = json.decode(utf8.decode(response.bodyBytes));
            final estado = cuerpo is Map ? (cuerpo['estado_hacienda'] ?? cuerpo['estado'])?.toString() : null;
            if (estado != null) exito = 'Listo. Estado en Hacienda: ${_estadosHacienda[estado] ?? estado}.';
          } catch (_) {}
        }
        setState(() {
          mensaje.estadoAccion = 'creada';
          _mensajes.add(_ChatMensaje('assistant', exito));
        });
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      setState(() => mensaje.estadoAccion = 'pendiente');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo completar: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      _scrollAlFinal();
    }
  }

  static const _iconosAccion = {
    'cliente': Icons.person_add_alt_1_outlined,
    'gasto': Icons.receipt_long_outlined,
    'abono': Icons.payments_outlined,
    'hacienda': Icons.account_balance_outlined,
    'cotizacion': Icons.request_quote_outlined,
    'anular': Icons.block_outlined,
    'ingreso': Icons.trending_up,
    'proveedor': Icons.local_shipping_outlined,
    'producto': Icons.inventory_2_outlined,
    'compra': Icons.shopping_cart_outlined,
  };

  Widget _buildTarjetaAccion(_ChatMensaje mensaje) {
    final accion = mensaje.propuestaAccion!;
    final filas = (accion['filas'] as List? ?? []).map((f) => (f as List).map((v) => '$v').toList()).toList();
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85 > 460 ? 460 : MediaQuery.of(context).size.width * 0.85),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconosAccion[accion['icono']] ?? Icons.task_alt, size: 17, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('${accion['titulo'] ?? 'Confirmar'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 10),
          for (final f in filas)
            if (f.length >= 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 110, child: Text(f[0], style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
                    Expanded(child: Text(f[1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          if (mensaje.estadoAccion == 'creada')
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text('Hecho', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: mensaje.estadoAccion == 'creando' ? null : () => _confirmarAccion(mensaje),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                child: mensaje.estadoAccion == 'creando'
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('${accion['boton'] ?? 'Confirmar'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Documentos descargables (reportes y PDF de facturas)

  Future<Map<String, dynamic>> _getJson(String endpoint) async {
    final r = await ApiService.get(endpoint);
    final data = json.decode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) {
      throw Exception(data is Map ? (data['detail'] ?? data['error'] ?? 'Error ${r.statusCode}') : 'Error ${r.statusCode}');
    }
    return data is Map<String, dynamic> ? data : {'lista': data};
  }

  String _fechaCorta(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : '${d.day}/${d.month}/${d.year}';
  }

  /// Pide los datos del reporte y lo arma con las MISMAS funciones de la
  /// pantalla de Reportes (mismo PDF/Excel con dashboard y formato).
  Future<void> _descargarDocumento(_ChatMensaje mensaje, String formato) async {
    final doc = mensaje.propuestaDocumento!;
    final pdf = formato == 'pdf';
    final ids = ((doc['negocio_ids'] as List?) ?? [doc['negocio_id'] ?? widget.negocioId]).whereType<int>().toList();
    setState(() => mensaje.descargando = formato);
    try {
      switch (doc['tipo']) {
        case 'ventas_compras':
          final desde = doc['fecha_inicio'] as String;
          final hasta = doc['fecha_fin'] as String;
          final periodo = '${_fechaCorta(desde)} - ${_fechaCorta(hasta)}';
          final reportes = <Map<String, dynamic>>[];
          for (final id in ids) {
            reportes.add(await _getJson('/reportes/consolidado/?negocio=$id&fecha_inicio=$desde&fecha_fin=$hasta&tipo=ambos'));
          }
          if (reportes.length == 1) {
            pdf
                ? await ExportService.exportReporteConsolidadoToPdf(reportes.first, periodo)
                : await ExportService.exportReporteConsolidadoToExcel(reportes.first);
          } else {
            pdf
                ? await ExportService.exportReportesConsolidadosToPdf(reportes, periodo)
                : await ExportService.exportReportesConsolidadosToExcel(reportes, periodo: periodo);
          }
        case 'renta':
          final anio = (doc['anio'] as num).toInt();
          final rentas = <Map<String, dynamic>>[];
          for (final id in ids) {
            rentas.add(await _getJson('/facturas/declaracion-renta/?negocio=$id&periodo_fiscal=$anio'));
          }
          pdf ? await ExportService.exportRentaContadorToPdf(rentas, anio) : await ExportService.exportRentaContadorToExcel(rentas, anio);
        case 'cuentas_por_cobrar':
          final r = await ApiService.get('/clientes/saldos/?negocio=${ids.first}');
          if (r.statusCode != 200) throw Exception('No se pudieron leer las cuentas por cobrar.');
          final saldos = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
          pdf
              ? await ExportService.exportSaldosToPdf(saldos, (doc['negocio_nombre'] ?? '').toString())
              : await ExportService.exportSaldosToExcel(saldos);
        case 'factura':
          final factura = Factura.fromJson(await _getJson('/facturas/${doc['factura_id']}/'));
          await ExportService.exportFacturaDetalleToPdf(factura);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el documento: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => mensaje.descargando = null);
    }
  }

  Widget _buildTarjetaDocumento(_ChatMensaje mensaje) {
    final doc = mensaje.propuestaDocumento!;
    final formatos = ((doc['formatos'] as List?) ?? ['pdf']).map((f) => '$f').toList();
    final icono = switch (doc['tipo']) {
      'renta' => Icons.account_balance_outlined,
      'cuentas_por_cobrar' => Icons.monetization_on_outlined,
      'factura' => Icons.receipt_long_outlined,
      _ => Icons.insert_chart_outlined,
    };
    Widget boton(String formato) {
      final esPdf = formato == 'pdf';
      final ocupado = mensaje.descargando != null;
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: ocupado ? null : () => _descargarDocumento(mensaje, formato),
          icon: mensaje.descargando == formato
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(esPdf ? Icons.picture_as_pdf : Icons.table_chart, size: 18, color: esPdf ? Colors.redAccent : Colors.green),
          label: Text(esPdf ? 'PDF' : 'Excel', style: const TextStyle(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    final ancho = MediaQuery.of(context).size.width * 0.85;
    return Container(
      constraints: BoxConstraints(maxWidth: ancho > 420 ? 420 : ancho),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icono, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${doc['titulo'] ?? 'Documento'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    if ((doc['descripcion'] ?? '').toString().isNotEmpty)
                      Text('${doc['descripcion']}', style: TextStyle(fontSize: 12, color: AppColors.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < formatos.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                boton(formatos[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Botón para ir a la sección que la IA propuso (marca [[ABRIR:...]]).
  Widget _buildTarjetaNavegar(_ChatMensaje mensaje) {
    final clave = mensaje.navegar!;
    final descripcion = widget.secciones?[clave] ?? clave;
    final titulo = descripcion.split(':').first.split('(').first.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.icon(
        onPressed: widget.onNavegar == null
            ? null
            : () {
                Navigator.pop(context);
                widget.onNavegar!(clave);
              },
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: Text('Abrir $titulo', style: const TextStyle(fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// Micrófono: graba una nota de voz para la IA. Mientras la IA lee su
  /// respuesta en voz alta, el aro pulsa y tocarlo la calla.
  Widget _buildBotonMicrofono() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hablando ? AppColors.primary.withOpacity(0.12 + 0.18 * _pulseCtrl.value) : Colors.transparent,
          ),
          child: child,
        );
      },
      child: IconButton.filled(
        onPressed: _enviando ? null : _empezarAGrabar,
        icon: Icon(_hablando ? Icons.volume_up_rounded : Icons.mic_rounded),
        style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
        tooltip: _hablando ? 'Hablando... tocá para callarla' : 'Mandar nota de voz',
      ),
    );
  }

  /// Nota de voz, fotos y archivos que mandó la persona, dentro de su burbuja.
  List<Widget> _buildAdjuntosMensaje(_ChatMensaje m, {Color? colorTexto}) {
    final color = colorTexto ?? (m.role == 'user' ? Colors.black : AppColors.textStrong);
    return [
      for (final a in m.adjuntos)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: a.esAudio
              ? NotaVozBurbuja(bytes: a.bytes, mime: a.mime, duracion: a.duracion, color: color)
              : a.esImagen
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(a.bytes, width: 200, fit: BoxFit.cover),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(a.mime == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined, size: 18, color: color),
                        const SizedBox(width: 6),
                        Flexible(child: Text(a.nombre, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 13))),
                      ],
                    ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => widget.pantallaCompleta ? _buildPantalla(context) : _buildHoja(context);

  // Colores fijos de marca de la pantalla completa (iguales en el tema
  // claro del contador y en el oscuro del negocio).
  static const _cian = Color(0xFF22D3EE);
  static const _cianSuave = Color(0xFF67E8F9);

  bool get _sinConversacion => !_mensajes.any((m) => m.role == 'user') && !_enviando;

  Widget _buildListaMensajes({required bool estiloPantalla}) {
    final anchoBurbuja = MediaQuery.of(context).size.width * 0.75;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: estiloPantalla ? const EdgeInsets.fromLTRB(16, 8, 16, 16) : const EdgeInsets.all(16),
      itemCount: _mensajes.length + (_enviando && (estiloPantalla || _parcialVisible.isNotEmpty || _estadoVivo != null) ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _mensajes.length) {
          if (_parcialVisible.isEmpty) {
            return estiloPantalla
                ? _Pensando(texto: _estadoVivo)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_estadoVivo ?? '', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontStyle: FontStyle.italic)),
                  );
          }
          if (estiloPantalla) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AvatarIA(tamano: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('$_parcialVisible ▍', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, height: 1.55)),
                    ),
                  ),
                ],
              ),
            );
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: anchoBurbuja),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(14)),
              child: Text('$_parcialVisible ▍', style: TextStyle(color: AppColors.textStrong, fontSize: 14, height: 1.4)),
            ),
          );
        }
        final m = _mensajes[index];
        final esUsuario = m.role == 'user';
        final colorTexto = estiloPantalla
            ? Colors.white.withOpacity(esUsuario ? 0.95 : 0.9)
            : (esUsuario ? Colors.black : AppColors.textStrong);
        final contenido = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._buildAdjuntosMensaje(m, colorTexto: colorTexto),
            if (m.content.isNotEmpty)
              (estiloPantalla && !esUsuario)
                  ? SelectableText(m.content, style: TextStyle(color: colorTexto, fontSize: 15, height: 1.55))
                  : Text(m.content, style: TextStyle(color: colorTexto, fontSize: estiloPantalla ? 15 : 14, height: 1.4)),
          ],
        );
        final Widget burbuja;
        if (estiloPantalla && !esUsuario) {
          // Como en Claude/Gemini: la IA escribe "suelta", sin burbuja.
          burbuja = Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AvatarIA(tamano: 30),
                const SizedBox(width: 12),
                Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: contenido)),
              ],
            ),
          );
        } else {
          burbuja = Align(
            alignment: esUsuario ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: estiloPantalla ? (anchoBurbuja > 560 ? 560 : anchoBurbuja) : anchoBurbuja),
              margin: EdgeInsets.only(bottom: estiloPantalla ? 18 : 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: estiloPantalla ? Colors.white.withOpacity(0.10) : (esUsuario ? AppColors.primary : AppColors.surfaceSubtle),
                borderRadius: BorderRadius.circular(estiloPantalla ? 18 : 14),
              ),
              child: contenido,
            ),
          );
        }
        return Column(
          crossAxisAlignment: esUsuario ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            burbuja,
            if (m.propuesta != null) Padding(padding: EdgeInsets.only(left: estiloPantalla ? 42 : 0), child: _buildTarjetaPropuesta(m)),
            if (m.propuestaProducto != null)
              Padding(padding: EdgeInsets.only(left: estiloPantalla ? 42 : 0), child: _buildTarjetaPropuestaProducto(m)),
            if (m.propuestaAccion != null) Padding(padding: EdgeInsets.only(left: estiloPantalla ? 42 : 0), child: _buildTarjetaAccion(m)),
            if (m.propuestaDocumento != null) Padding(padding: EdgeInsets.only(left: estiloPantalla ? 42 : 0), child: _buildTarjetaDocumento(m)),
            if (m.navegar != null) Padding(padding: EdgeInsets.only(left: estiloPantalla ? 42 : 0), child: _buildTarjetaNavegar(m)),
          ],
        );
      },
    );
  }

  Widget _buildPendientes(EdgeInsets padding) {
    if (_pendientes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in List.of(_pendientes)) ChipAdjunto(adjunto: a, onQuitar: () => setState(() => _pendientes.remove(a))),
          ],
        ),
      ),
    );
  }

  bool get _hayAlgoParaMandar => _inputCtrl.text.trim().isNotEmpty || _pendientes.isNotEmpty;

  /// Caja de entrada de la pantalla completa: texto arriba (varias líneas),
  /// abajo el clip a la izquierda y micrófono/enviar a la derecha.
  Widget _buildEntradaPantalla() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        boxShadow: [BoxShadow(color: _cian.withOpacity(0.08), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
      child: _grabando
          ? GrabandoNotaVoz(grabador: _grabador!, onCancelar: _descartarNotaDeVoz, onEnviar: _mandarNotaDeVoz)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPendientes(const EdgeInsets.fromLTRB(10, 6, 10, 2)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 10, 0),
                  child: TextField(
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviarMensaje(),
                    cursorColor: _cian,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                    decoration: InputDecoration(
                      hintText: _hablando ? 'Hablando...' : 'Pedile algo a Equilibra o mandale una nota de voz...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.42), fontSize: 16),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _enviando ? null : _adjuntar,
                      icon: Icon(Icons.attach_file_rounded, color: Colors.white.withOpacity(0.7)),
                      tooltip: 'Adjuntar foto, PDF o Excel',
                    ),
                    const Spacer(),
                    _BotonRedondoIA(
                      icono: _hayAlgoParaMandar ? Icons.arrow_upward_rounded : (_hablando ? Icons.volume_off_rounded : Icons.mic_rounded),
                      tooltip: _hayAlgoParaMandar ? 'Enviar' : (_hablando ? 'Callar' : 'Hablarle (nota de voz)'),
                      pulso: !_hayAlgoParaMandar && !_hablando,
                      onTap: _enviando ? null : (_hayAlgoParaMandar ? () => _enviarMensaje() : _empezarAGrabar),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  void _usarSugerencia(String texto) {
    _inputCtrl.text = texto;
    _enviarMensaje();
  }

  Widget _buildBienvenida(bool compacto) {
    final saludo = widget.saludo ?? 'Hola';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _AvatarIA(tamano: 64)),
        const SizedBox(height: 22),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [_cianSuave, Color(0xFFA5B4FC), Color(0xFFC4B5FD)]).createShader(r),
          child: Text(
            '$saludo 👋',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: compacto ? 26 : 36, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '¿Qué hacemos hoy?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: compacto ? 24 : 34, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 10),
        Text(
          'Soy Equilibra, tu asistente virtual. Pedime lo que necesités y lo resolvemos acá mismo. Escribime o mandame una nota de voz.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: compacto ? 14 : 15.5, height: 1.45),
        ),
        SizedBox(height: compacto ? 22 : 30),
        _buildEntradaPantalla(),
        if (widget.sugerencias.isNotEmpty) ...[
          const SizedBox(height: 18),
          if (compacto)
            for (final (icono, texto) in widget.sugerencias)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SugerenciaIA(icono: icono, texto: texto, anchoCompleto: true, onTap: () => _usarSugerencia(texto)),
              )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (icono, texto) in widget.sugerencias)
                  _SugerenciaIA(icono: icono, texto: texto, onTap: () => _usarSugerencia(texto)),
              ],
            ),
        ],
      ],
    );
  }

  Widget _buildPantalla(BuildContext context) {
    final compacto = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1120), Color(0xFF141838), Color(0xFF0B2230)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // --- barra superior
              Padding(
                padding: EdgeInsets.fromLTRB(compacto ? 14 : 24, 12, compacto ? 8 : 18, 6),
                child: Row(
                  children: [
                    const _AvatarIA(tamano: 34),
                    const SizedBox(width: 10),
                    const Text('Equilibra', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                    const SizedBox(width: 8),
                    if (!compacto)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: _cian.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _cian.withOpacity(0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            const Text('TU ASISTENTE VIRTUAL', style: TextStyle(color: _cianSuave, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (!_sinConversacion)
                      IconButton(
                        onPressed: _enviando ? null : _nuevaConversacion,
                        icon: Icon(Icons.edit_square, color: Colors.white.withOpacity(0.75), size: 21),
                        tooltip: 'Nueva conversación',
                      ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.space_dashboard_outlined, size: 18),
                      label: Text(compacto ? 'Panel' : 'Ir al panel'),
                      style: TextButton.styleFrom(
                        foregroundColor: _cianSuave,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(0.14))),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _sinConversacion
                      ? Center(
                          key: const ValueKey('bienvenida'),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(compacto ? 16 : 24, 12, compacto ? 16 : 24, 24),
                            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _buildBienvenida(compacto)),
                          ),
                        )
                      : Center(
                          key: const ValueKey('conversacion'),
                          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: _buildListaMensajes(estiloPantalla: true)),
                        ),
                ),
              ),
              if (!_sinConversacion)
                Padding(
                  padding: EdgeInsets.fromLTRB(compacto ? 12 : 24, 0, compacto ? 12 : 24, 6),
                  child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: _buildEntradaPantalla())),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 2),
                child: Text(
                  'Equilibra puede equivocarse. Revisá los datos importantes antes de confirmar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _nuevaConversacion() {
    if (_hablando) _tts.stop();
    setState(() {
      _mensajes.removeRange(1, _mensajes.length);
      _pendientes.clear();
      _inputCtrl.clear();
    });
  }

  Widget _buildHoja(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.82;
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Container(
        height: alto,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Icon(widget.modoAsistente ? Icons.auto_awesome : Icons.support_agent, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.modoAsistente ? 'Asistente Equilibra' : 'Soporte Equilibra',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildListaMensajes(estiloPantalla: false)),
            if (_enviando)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _abrirDejarMensaje,
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Dejar mensaje para el equipo', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
            _buildPendientes(const EdgeInsets.fromLTRB(16, 0, 16, 8)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 16),
              child: _grabando
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(28)),
                      child: GrabandoNotaVoz(
                        grabador: _grabador!,
                        onCancelar: _descartarNotaDeVoz,
                        onEnviar: _mandarNotaDeVoz,
                        colorTexto: AppColors.textStrong,
                      ),
                    )
                  : Row(
                      children: [
                        IconButton(
                          onPressed: _enviando ? null : _adjuntar,
                          icon: Icon(Icons.attach_file_rounded, color: AppColors.textMuted),
                          tooltip: 'Adjuntar foto, PDF o Excel',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _enviarMensaje(),
                            decoration: InputDecoration(
                              hintText: _hablando ? 'Hablando...' : 'Escribí o mandá una nota de voz...',
                              filled: true,
                              fillColor: _hablando ? AppColors.primary.withOpacity(0.06) : AppColors.surfaceSubtle,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Como en WhatsApp: con algo escrito o adjunto se
                        // envía; si no, el micrófono.
                        if (_hayAlgoParaMandar)
                          IconButton.filled(
                            onPressed: _enviando ? null : () => _enviarMensaje(),
                            icon: const Icon(Icons.send),
                            style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                          )
                        else
                          _buildBotonMicrofono(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo del asistente: destellos sobre un círculo con degradado de marca.
class _AvatarIA extends StatelessWidget {
  final double tamano;
  const _AvatarIA({this.tamano = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22D3EE), Color(0xFF6366F1), Color(0xFFA855F7)],
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.35), blurRadius: tamano * 0.45)],
      ),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: tamano * 0.52),
    );
  }
}

/// "Pensando..." mientras la IA responde (pantalla completa).
class _Pensando extends StatefulWidget {
  /// Qué está haciendo (ej. "Buscando tus facturas…"); null = "Pensando...".
  final String? texto;
  const _Pensando({this.texto});

  @override
  State<_Pensando> createState() => _PensandoState();
}

class _PensandoState extends State<_Pensando> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          RotationTransition(turns: _ctrl, child: const _AvatarIA(tamano: 30)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              widget.texto ?? 'Pensando...',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14.5, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonRedondoIA extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final bool pulso;
  final VoidCallback? onTap;
  const _BotonRedondoIA({required this.icono, required this.tooltip, required this.onTap, this.pulso = false});

  @override
  Widget build(BuildContext context) {
    // La sombra va en un contenedor aparte: dentro del Material (Ink) se
    // recortaba en cuadrado.
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: pulso ? [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.45), blurRadius: 16)] : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF6366F1)]),
              ),
              child: Icon(icono, color: Colors.white, size: 23),
            ),
          ),
        ),
      ),
    );
  }
}

class _SugerenciaIA extends StatefulWidget {
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final bool anchoCompleto;
  const _SugerenciaIA({required this.icono, required this.texto, required this.onTap, this.anchoCompleto = false});

  @override
  State<_SugerenciaIA> createState() => _SugerenciaIAState();
}

class _SugerenciaIAState extends State<_SugerenciaIA> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: widget.anchoCompleto ? 12 : 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_hover ? 0.13 : 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover ? const Color(0xFF22D3EE) : Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            mainAxisSize: widget.anchoCompleto ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(widget.icono, size: 17, color: const Color(0xFF67E8F9)),
              const SizedBox(width: 8),
              if (widget.anchoCompleto)
                Expanded(child: Text(widget.texto, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w600)))
              else
                Text(widget.texto, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
