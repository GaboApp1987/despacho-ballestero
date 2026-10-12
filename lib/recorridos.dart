import 'package:flutter/material.dart';

import 'restaurante_tema.dart';
import 'widgets/recorrido_guiado.dart';

/// Los recorridos guiados de la app (ver widgets/recorrido_guiado.dart).
/// Cada uno tiene las marcas (GlobalKey) que se ponen en los widgets que
/// ilumina y sus pasos. Para agregar uno: una clase más acá, las marcas en
/// la pantalla, el botón "?" (BotonGuia) y ofrecerRecorrido al abrirla.

/// Emitir una factura o tiquete (formulario_factura.dart).
class GuiaFactura {
  static const clave = 'factura';
  static final buscar = GlobalKey(debugLabel: 'guia_factura_buscar');
  static final catalogo = GlobalKey(debugLabel: 'guia_factura_catalogo');
  static final tipo = GlobalKey(debugLabel: 'guia_factura_tipo');
  static final cliente = GlobalKey(debugLabel: 'guia_factura_cliente');
  static final condicion = GlobalKey(debugLabel: 'guia_factura_condicion');
  static final medioPago = GlobalKey(debugLabel: 'guia_factura_medio');
  static final emitir = GlobalKey(debugLabel: 'guia_factura_emitir');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: [
        const PasoRecorrido(
          titulo: "Así se hace una factura",
          texto: "Elegís lo que vendés, a quién y cómo paga, y la emitís. Equilibra la firma y la manda a Hacienda sola.",
        ),
        PasoRecorrido(
          objetivo: buscar,
          titulo: "Buscá lo que vendés",
          texto: "Escribí el nombre del producto o servicio. Si todavía no existe, crealo en Inventario.",
        ),
        PasoRecorrido(
          objetivo: catalogo,
          titulo: "Tocá para agregar",
          texto: "Cada toque suma uno a la factura. Para cambiar la cantidad, el precio o poner un descuento, tocá la línea en la factura.",
        ),
        PasoRecorrido(
          objetivo: tipo,
          titulo: "¿Factura o tiquete?",
          texto: "Factura cuando el cliente la pide a su nombre (para sus gastos). Tiquete para consumidor final: no hace falta cliente.",
        ),
        PasoRecorrido(
          objetivo: cliente,
          titulo: "El cliente",
          texto: "Para una factura, elegí el cliente. Si es nuevo, agregalo en Clientes: con la cédula se llenan sus datos solos.",
        ),
        PasoRecorrido(
          objetivo: condicion,
          titulo: "Contado o crédito",
          texto: "A crédito indicás el plazo y la factura queda en Cuentas por cobrar hasta que te paguen.",
        ),
        PasoRecorrido(
          objetivo: medioPago,
          titulo: "¿Cómo paga?",
          texto: "Efectivo, tarjeta, SINPE Móvil... Sale en el comprobante y cuadra solo en el cierre de caja.",
        ),
        PasoRecorrido(
          objetivo: emitir,
          titulo: "Emitir",
          texto: "Se firma y se envía a Hacienda. En unos segundos te dice si fue aceptada, y al cliente le llega por correo.",
        ),
      ]);
}

/// La lista de compras (compras_screen.dart).
class GuiaCompras {
  static const clave = 'compras';
  static final nueva = GlobalKey(debugLabel: 'guia_compras_nueva');
  static final porRevisar = GlobalKey(debugLabel: 'guia_compras_revisar');
  static final importarVarios = GlobalKey(debugLabel: 'guia_compras_importar');

  static void mostrar(BuildContext context, {required String cedulaNegocio}) => mostrarRecorrido(context, clave: clave, pasos: [
        PasoRecorrido(
          titulo: "Tus compras",
          texto: "Registrar las compras con factura te baja el IVA a pagar y te sube el inventario.\n\n"
              "Tip: pedile a tus proveedores que manden la factura a $cedulaNegocio@facturas.equilibracr.com y te aparece aquí sola.",
        ),
        PasoRecorrido(
          objetivo: nueva,
          titulo: "Nueva compra",
          texto: "Adjuntás la factura del proveedor (el XML, el PDF o una foto) y se llena sola. Te lo muestro adentro.",
        ),
        PasoRecorrido(
          objetivo: porRevisar,
          titulo: "Por revisar",
          texto: "Facturas que llegaron solas por correo. Revisalas y confirmalas con un toque; si una no sirve, descartala.",
        ),
        PasoRecorrido(
          objetivo: importarVarios,
          titulo: "¿Son muchas?",
          texto: "Subí varios XML de una vez y se registra una compra por cada uno.",
        ),
      ]);
}

/// Registrar una compra (formulario_compra.dart).
class GuiaCompra {
  static const clave = 'compra';
  static final adjuntar = GlobalKey(debugLabel: 'guia_compra_adjuntar');
  static final proveedor = GlobalKey(debugLabel: 'guia_compra_proveedor');
  static final condicion = GlobalKey(debugLabel: 'guia_compra_condicion');
  static final aceptar = GlobalKey(debugLabel: 'guia_compra_aceptar');
  static final confirmar = GlobalKey(debugLabel: 'guia_compra_confirmar');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: [
        PasoRecorrido(
          objetivo: adjuntar,
          titulo: "Adjuntá la factura",
          texto: "Subí el XML de Hacienda (lo más exacto), el PDF o una foto. Se llenan solos el proveedor, el número y las líneas.",
        ),
        PasoRecorrido(
          objetivo: proveedor,
          titulo: "El proveedor",
          texto: "Si no existe, se crea solo con los datos de la factura. También lo podés elegir o crear con el +.",
        ),
        PasoRecorrido(
          objetivo: condicion,
          titulo: "Contado o crédito",
          texto: "A crédito, la compra queda en Cuentas por pagar hasta que le pagués al proveedor.",
        ),
        PasoRecorrido(
          objetivo: aceptar,
          titulo: "Aceptar ante Hacienda",
          texto: "Con el XML se manda la aceptación a Hacienda: así el IVA de esta compra cuenta como crédito fiscal.",
        ),
        PasoRecorrido(
          objetivo: confirmar,
          titulo: "Confirmar",
          texto: "Guarda la compra y suma al inventario los productos que trae.",
        ),
      ]);
}

/// El salón del restaurante (restaurante_screen.dart).
class GuiaRestaurante {
  static const clave = 'restaurante';
  static final mesas = GlobalKey(debugLabel: 'guia_resto_mesas');
  static final paraLlevar = GlobalKey(debugLabel: 'guia_resto_llevar');
  static final pestanas = GlobalKey(debugLabel: 'guia_resto_pestanas');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: colorResto, pasos: [
        const PasoRecorrido(
          titulo: "Bienvenido al modo restaurante",
          texto: "Aquí manejás las mesas, la cocina y los cobros. Te muestro lo básico.",
        ),
        PasoRecorrido(
          objetivo: mesas,
          titulo: "Tus mesas",
          texto: "Tocá una mesa libre para abrirle la cuenta. Las ocupadas muestran el total y el tiempo; las que llaman o piden la cuenta salen arriba, en \"Atender ahora\".",
        ),
        PasoRecorrido(
          objetivo: paraLlevar,
          titulo: "Para llevar",
          texto: "Para pedidos sin mesa: le ponés el nombre del cliente y aparece en la franja de arriba.",
        ),
        PasoRecorrido(
          objetivo: pestanas,
          titulo: "Lo demás",
          texto: "En Cocina se ven las comandas, en Variaciones armás tamaños y adicionales, en Insumos las recetas y en Mesas configurás las mesas, el menú QR y el 10% de servicio.",
        ),
      ]);
}

/// La cuenta de una mesa (restaurante_orden_screen.dart).
class GuiaOrden {
  static const clave = 'restaurante_orden';
  static final menu = GlobalKey(debugLabel: 'guia_orden_menu');
  static final agregarPlatos = GlobalKey(debugLabel: 'guia_orden_agregar');
  static final enviar = GlobalKey(debugLabel: 'guia_orden_enviar');
  static final cobrar = GlobalKey(debugLabel: 'guia_orden_cobrar');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: colorResto, pasos: [
        const PasoRecorrido(
          titulo: "Así se atiende una mesa",
          texto: "Agregás los platos, los mandás a la cocina por rondas y al final cobrás.",
        ),
        PasoRecorrido(
          objetivo: menu,
          titulo: "Elegí los platos",
          texto: "Buscá o filtrá por categoría y tocá un plato para agregarlo. Si tiene tamaños o adicionales, te pregunta. Mantené presionado para ponerle una nota (sin cebolla).",
        ),
        PasoRecorrido(
          objetivo: agregarPlatos,
          titulo: "Agregar platos",
          texto: "Abre el menú: buscá y tocá los platos. Si tienen tamaños o adicionales, te pregunta.",
        ),
        PasoRecorrido(
          objetivo: enviar,
          titulo: "Enviar a cocina",
          texto: "Lo nuevo queda \"por enviar\" hasta que tocás aquí. Cada envío es una ronda: la cocina la ve en su pantalla o se imprime la comanda.",
        ),
        PasoRecorrido(
          objetivo: cobrar,
          titulo: "Cobrar",
          texto: "Cobrás todo, por platos o en partes iguales. Sale el tiquete (con el 10% de servicio si está activo) y la mesa queda libre.",
        ),
      ]);
}
