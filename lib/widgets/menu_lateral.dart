import 'package:flutter/material.dart';

import '../avatar_logo.dart';

/// Colores del menú lateral (navy profundo, diseño "Menú lateral del
/// contador", 2026-10-08) -- fijos, no cambian con el tema claro/oscuro.
class MenuLateralColores {
  static const Color fondo = Color(0xFF0E1726);
  static const Color tarjeta = Color(0xFF16223A);
  static const Color campo = Color(0xFF121D31);
  static const Color avatar = Color(0xFF24324D);
  static const Color texto = Color(0xFFC3CBDA);
  static const Color etiqueta = Color(0xFF8A98B3);
  static const Color textoActivo = Colors.white;
  // Más claro que el azul de la app: sobre el navy ese no contrasta.
  static const Color acento = Color(0xFF5B8CFF);
  static const Color aviso = Color(0xFFE11D48);
  static const Color salir = Color(0xFFF4A3B4);
}

class EntradaMenu {
  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;
  final bool activo;
  /// Globo rojo con la cantidad (certificaciones pendientes, chats sin leer...).
  final int? aviso;
  /// Etiqueta chica al lado del nombre (ej. "IA").
  final String? insignia;
  /// Ícono en color de acento también cuando no está activa.
  final bool destacada;
  const EntradaMenu({
    required this.icono,
    required this.etiqueta,
    required this.onTap,
    this.activo = false,
    this.aviso,
    this.insignia,
    this.destacada = false,
  });
}

class SeccionMenu {
  final String titulo;
  final List<EntradaMenu> entradas;
  const SeccionMenu(this.titulo, this.entradas);
}

class OpcionCuenta {
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final bool peligrosa;
  const OpcionCuenta(this.icono, this.texto, this.onTap, {this.peligrosa = false});
}

/// Menú lateral de los paneles (contador, dueño de la plataforma): logo,
/// buscador opcional, secciones con entradas y una fila de cuenta abajo
/// con su menú (Mi perfil, Soporte, Cerrar sesión...). Colapsado queda en
/// solo íconos. Cada pantalla decide dónde va (al lado del contenido o
/// por encima en pantallas angostas) y guarda si está colapsado.
class MenuLateral extends StatelessWidget {
  static const double anchoColapsado = 76;
  static const double anchoExpandido = 264;

  final String subtitulo;
  final bool colapsada;
  final VoidCallback onAlternar;
  /// Corre antes de cada acción (ej. cerrar el menú superpuesto).
  final VoidCallback? antesDeTocar;
  final List<SeccionMenu> secciones;
  final String? pistaBuscador;
  final TextEditingController? controladorBuscador;
  final ValueChanged<String>? onBuscar;
  final ValueChanged<String>? onBuscarEnviado;
  final String nombreCuenta;
  final String detalleCuenta;
  final String? logoCuenta;
  final IconData iconoCuenta;
  final List<OpcionCuenta> opcionesCuenta;

  const MenuLateral({
    super.key,
    required this.subtitulo,
    required this.colapsada,
    required this.onAlternar,
    required this.secciones,
    required this.nombreCuenta,
    required this.detalleCuenta,
    required this.opcionesCuenta,
    this.antesDeTocar,
    this.pistaBuscador,
    this.controladorBuscador,
    this.onBuscar,
    this.onBuscarEnviado,
    this.logoCuenta,
    this.iconoCuenta = Icons.badge_outlined,
  });

  void _tocar(VoidCallback accion) {
    antesDeTocar?.call();
    accion();
  }

  Widget _globo(int cantidad, {bool chico = false}) => Container(
        constraints: BoxConstraints(minWidth: chico ? 16 : 20),
        height: chico ? 16 : 20,
        padding: EdgeInsets.symmetric(horizontal: chico ? 4 : 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MenuLateralColores.aviso,
          borderRadius: BorderRadius.circular(999),
          border: chico ? Border.all(color: MenuLateralColores.fondo, width: 2) : null,
        ),
        child: Text(
          cantidad > 99 ? '99+' : '$cantidad',
          style: TextStyle(color: Colors.white, fontSize: chico ? 9 : 11, fontWeight: FontWeight.w700, height: 1),
        ),
      );

  Widget _entrada(EntradaMenu e) {
    final hayAviso = e.aviso != null && e.aviso! > 0;
    final colorTexto = e.activo ? MenuLateralColores.textoActivo : MenuLateralColores.texto;
    final icono = Icon(e.icono, size: 19, color: e.activo || (e.destacada && colapsada) ? MenuLateralColores.acento : colorTexto);
    final contenido = colapsada
        ? Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                icono,
                if (hayAviso) Positioned(top: -8, right: -11, child: _globo(e.aviso!, chico: true)),
              ],
            ),
          )
        : Row(
            children: [
              icono,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e.etiqueta,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorTexto, fontSize: 13.5, fontWeight: e.activo ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
              if (hayAviso) _globo(e.aviso!),
              if (e.insignia != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MenuLateralColores.acento),
                  ),
                  child: Text(e.insignia!, style: const TextStyle(color: MenuLateralColores.acento, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          );
    final boton = Material(
      color: e.activo ? MenuLateralColores.acento.withOpacity(0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withOpacity(0.05),
        onTap: () => _tocar(e.onTap),
        child: SizedBox(
          height: colapsada ? 44 : 40,
          child: Padding(padding: EdgeInsets.symmetric(horizontal: colapsada ? 0 : 10), child: contenido),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: colapsada ? 16 : 14, vertical: 1),
      child: colapsada ? Tooltip(message: hayAviso ? '${e.etiqueta} (${e.aviso})' : e.etiqueta, child: boton) : boton,
    );
  }

  Widget _tituloSeccion(String titulo, {required bool primera}) {
    if (colapsada) {
      return primera
          ? const SizedBox(height: 8)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Container(width: 28, height: 1, color: Colors.white.withOpacity(0.08))),
            );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(24, primera ? 10 : 18, 24, 6),
      child: Text(
        titulo,
        style: const TextStyle(color: MenuLateralColores.etiqueta, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9),
      ),
    );
  }

  Widget _encabezado() {
    final logo = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: MenuLateralColores.acento, borderRadius: BorderRadius.circular(9)),
      child: const Text('e', style: TextStyle(color: MenuLateralColores.fondo, fontWeight: FontWeight.w800, fontSize: 19, height: 1)),
    );
    final alternar = Tooltip(
      message: colapsada ? "Expandir menú" : "Colapsar menú",
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: onAlternar,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              colapsada ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded,
              size: 17,
              color: MenuLateralColores.etiqueta,
            ),
          ),
        ),
      ),
    );
    if (colapsada) return Column(children: [logo, const SizedBox(height: 8), alternar]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Equilibra", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5, letterSpacing: -0.2)),
                const SizedBox(height: 1),
                Text(subtitulo,
                    style: const TextStyle(color: MenuLateralColores.etiqueta, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.4)),
              ],
            ),
          ),
          alternar,
        ],
      ),
    );
  }

  Widget? _buscador() {
    if (controladorBuscador == null) return null;
    if (colapsada) {
      return _entrada(EntradaMenu(icono: Icons.search_rounded, etiqueta: pistaBuscador ?? "Buscar", onTap: onAlternar));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: controladorBuscador,
          onChanged: onBuscar,
          onSubmitted: onBuscarEnviado,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          cursorColor: MenuLateralColores.acento,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: MenuLateralColores.campo,
            hintText: pistaBuscador ?? "Buscar…",
            hintStyle: const TextStyle(color: MenuLateralColores.etiqueta, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded, size: 17, color: MenuLateralColores.etiqueta),
            prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.07)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: MenuLateralColores.acento),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cuenta() {
    final avatar = avatarConLogo(
      logoUrl: logoCuenta,
      icono: iconoCuenta,
      radius: 16,
      color: Colors.white,
      fondo: MenuLateralColores.avatar,
      nombre: nombreCuenta,
    );
    return PopupMenuButton<int>(
      tooltip: "Cuenta",
      color: MenuLateralColores.tarjeta,
      elevation: 8,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      onSelected: (i) => _tocar(opcionesCuenta[i].onTap),
      itemBuilder: (_) => [
        for (var i = 0; i < opcionesCuenta.length; i++) ...[
          if (opcionesCuenta[i].peligrosa && i > 0) const PopupMenuDivider(height: 8),
          PopupMenuItem<int>(
            value: i,
            height: 42,
            child: Row(
              children: [
                Icon(opcionesCuenta[i].icono, size: 18, color: opcionesCuenta[i].peligrosa ? MenuLateralColores.salir : Colors.white),
                const SizedBox(width: 12),
                Text(
                  opcionesCuenta[i].texto,
                  style: TextStyle(
                    color: opcionesCuenta[i].peligrosa ? MenuLateralColores.salir : Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      child: colapsada
          ? SizedBox(height: 52, child: Center(child: avatar))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(nombreCuenta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(detalleCuenta,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MenuLateralColores.etiqueta, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.unfold_more_rounded, size: 18, color: MenuLateralColores.etiqueta),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = colapsada ? anchoColapsado : anchoExpandido;
    final buscador = _buscador();
    final contenido = SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 14),
          _encabezado(),
          const SizedBox(height: 14),
          if (buscador != null) buscador,
          // Con scroll propio: en ventanas bajas las entradas no caben.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              children: [
                for (var i = 0; i < secciones.length; i++) ...[
                  _tituloSeccion(secciones[i].titulo, primera: i == 0),
                  for (final e in secciones[i].entradas) _entrada(e),
                ],
              ],
            ),
          ),
          Container(height: 1, margin: EdgeInsets.symmetric(horizontal: colapsada ? 24 : 14), color: Colors.white.withOpacity(0.07)),
          _cuenta(),
          const SizedBox(height: 4),
        ],
      ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: ancho,
      color: MenuLateralColores.fondo,
      // El contenido se arma al ancho final y se recorta mientras el menú se
      // abre o se cierra, en vez de apretarse (y desbordar) a medio camino.
      child: ClipRect(
        child: OverflowBox(alignment: Alignment.topLeft, minWidth: ancho, maxWidth: ancho, child: contenido),
      ),
    );
  }
}
