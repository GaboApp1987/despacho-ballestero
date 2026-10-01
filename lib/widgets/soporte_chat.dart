import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../theme/app_theme.dart';
import '../api_service.dart';
import '../formato.dart';
import 'adjuntos_ia.dart';

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

class _ChatMensaje {
  final String role; // 'user' | 'assistant'
  final String content;
  final _PropuestaFactura? propuesta;
  final _PropuestaProducto? propuestaProducto;
  // Sección que la IA propuso abrir (clave de `secciones`), ver "navegar"
  // en SoporteChatView.
  final String? navegar;
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
  _ChatMensaje(this.role, this.content, {this.propuesta, this.propuestaProducto, this.navegar, this.adjuntos = const []});

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
  _PropuestaProducto({
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
    );
  }
}

/// Borrador de factura que arma el chat (herramienta preparar_factura del
/// backend) a partir de productos/cliente reales del catálogo -- nunca se
/// crea sola, el usuario la confirma con un botón (ver _confirmarFactura).
class _PropuestaFactura {
  final int clienteId;
  final String clienteNombre;
  final String clienteCedula;
  final List<Map<String, dynamic>> items;
  _PropuestaFactura({
    required this.clienteId,
    required this.clienteNombre,
    required this.clienteCedula,
    required this.items,
  });

  factory _PropuestaFactura.fromJson(Map<String, dynamic> json) {
    return _PropuestaFactura(
      clienteId: json['cliente_id'],
      clienteNombre: json['cliente_nombre'] ?? '',
      clienteCedula: json['cliente_cedula'] ?? '',
      items: (json['items'] as List).cast<Map<String, dynamic>>(),
    );
  }

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
  const _SoporteChatSheet({
    required this.contexto,
    this.negocioId,
    this.mensajeInicial,
    this.adjuntosIniciales = const [],
    this.secciones,
    this.onNavegar,
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
  }
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _enviando = false;

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
      final response = await ApiService.post('/soporte/chat/', {
        'mensajes': _mensajes.map((m) => m.toJson()).toList(),
        'contexto': widget.contexto,
        if (widget.negocioId != null) 'negocio': widget.negocioId,
        if (widget.secciones != null) 'secciones': widget.secciones,
        if (adj.isNotEmpty) 'adjuntos': adj.map((a) => a.toJson()).toList(),
      });
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? 'Error desconocido');
      }
      final propuestaJson = data['propuesta_factura'];
      final propuestaProductoJson = data['propuesta_producto'];
      final respuesta = data['respuesta'] ?? '';
      mensajeUsuario.notaOculta = data['nota_adjuntos'] as String?;
      setState(() => _mensajes.add(_ChatMensaje(
            'assistant',
            respuesta,
            propuesta: propuestaJson != null ? _PropuestaFactura.fromJson(propuestaJson) : null,
            propuestaProducto: propuestaProductoJson != null ? _PropuestaProducto.fromJson(propuestaProductoJson) : null,
            navegar: data['navegar'] as String?,
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
      if (mounted) setState(() => _enviando = false);
      _scrollAlFinal();
    }
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
        'negocio': widget.negocioId,
        'cliente': propuesta.clienteId,
        'consecutivo': '',
        'receptor_nombre': propuesta.clienteNombre,
        'receptor_cedula': propuesta.clienteCedula,
        'total_iva': redondear2(propuesta.montoIva),
        'total_factura': redondear2(propuesta.total),
        'condicion_venta': '01',
        'plazo_credito': 0,
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
        _mensajes.add(_ChatMensaje('assistant', '¡Listo! Factura creada y enviada a Hacienda.'));
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
        'negocio': widget.negocioId,
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
              const Text('Borrador de factura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Cliente: ${propuesta.clienteNombre}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          ...propuesta.items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${it['cantidad']} x ${it['nombre_producto']} (${formatearColones((it['precio_unitario'] as num).toDouble())})',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total (contado)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(formatearColones(propuesta.total), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          if (mensaje.estadoPropuesta == 'creada')
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text('Factura creada', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
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
                    : const Text('Confirmar y crear factura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
  List<Widget> _buildAdjuntosMensaje(_ChatMensaje m) {
    final color = m.role == 'user' ? Colors.black : AppColors.textStrong;
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
  Widget build(BuildContext context) {
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
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _mensajes.length,
                itemBuilder: (context, index) {
                  final m = _mensajes[index];
                  final esUsuario = m.role == 'user';
                  return Column(
                    crossAxisAlignment: esUsuario ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: esUsuario ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: esUsuario ? AppColors.primary : AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ..._buildAdjuntosMensaje(m),
                              if (m.content.isNotEmpty)
                                Text(
                                  m.content,
                                  style: TextStyle(color: esUsuario ? Colors.black : AppColors.textStrong, fontSize: 14, height: 1.35),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (m.propuesta != null) _buildTarjetaPropuesta(m),
                      if (m.propuestaProducto != null) _buildTarjetaPropuestaProducto(m),
                      if (m.navegar != null) _buildTarjetaNavegar(m),
                    ],
                  );
                },
              ),
            ),
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
            if (_pendientes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in List.of(_pendientes))
                        ChipAdjunto(adjunto: a, onQuitar: () => setState(() => _pendientes.remove(a))),
                    ],
                  ),
                ),
              ),
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
                        if (_inputCtrl.text.trim().isNotEmpty || _pendientes.isNotEmpty)
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
