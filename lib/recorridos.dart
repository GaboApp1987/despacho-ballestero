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


/// Cierre de caja (caja_screen.dart).
class GuiaCaja {
  static const clave = 'caja';
  static final fondo = GlobalKey(debugLabel: 'guia_caja_fondo');
  static final movimientos = GlobalKey(debugLabel: 'guia_caja_movimientos');
  static final resumen = GlobalKey(debugLabel: 'guia_caja_resumen');
  static final cerrar = GlobalKey(debugLabel: 'guia_caja_cerrar');
  static final historial = GlobalKey(debugLabel: 'guia_caja_historial');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: [
        const PasoRecorrido(
          titulo: "El cierre de caja",
          texto: "Abrís la caja con el fondo, vendés normal (marcando en cada factura cómo pagó) y al final contás el dinero: Equilibra te dice si sobra o falta.",
        ),
        PasoRecorrido(
          objetivo: fondo,
          titulo: "Abrir la caja",
          texto: "Al empezar el turno, poné cuánto dinero hay en la gaveta para dar cambio y tocá Abrir caja.",
        ),
        PasoRecorrido(
          objetivo: movimientos,
          titulo: "Entradas y salidas",
          texto: "Si sacás plata de la caja para pagar algo (hielo, un proveedor) o metés más cambio, anotalo aquí con el motivo.",
        ),
        PasoRecorrido(
          objetivo: resumen,
          titulo: "Lo que debería haber",
          texto: "Ventas de contado, abonos y propinas por medio de pago. Los cajeros no lo ven hasta cerrar, así el conteo es honesto.",
        ),
        PasoRecorrido(
          objetivo: cerrar,
          titulo: "Cerrar la caja",
          texto: "Contás billetes y monedas con el contador, y lo de tarjeta y SINPE. Sale el resultado con faltantes o sobrantes y lo podés imprimir.",
        ),
        PasoRecorrido(
          objetivo: historial,
          titulo: "Historial",
          texto: "Todos los cierres con su diferencia, para revisar cualquier día.",
        ),
      ]);
}

/// Inventario (inventario_screen.dart).
class GuiaInventario {
  static const clave = 'inventario';
  static final nuevo = GlobalKey(debugLabel: 'guia_inv_nuevo');
  static final buscar = GlobalKey(debugLabel: 'guia_inv_buscar');
  static final importar = GlobalKey(debugLabel: 'guia_inv_importar');
  static final precios = GlobalKey(debugLabel: 'guia_inv_precios');
  static final pestanas = GlobalKey(debugLabel: 'guia_inv_pestanas');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: [
        const PasoRecorrido(
          titulo: "Tu inventario",
          texto: "Aquí están tus productos y servicios, lo que ponés en las facturas. Las compras suman al stock y las ventas lo restan solas.",
        ),
        PasoRecorrido(
          objetivo: nuevo,
          titulo: "Nuevo producto",
          texto: "Nombre, precio y el código CABYS, que Hacienda exige (lo buscás por palabra). Con el costo, Equilibra te calcula la ganancia.",
        ),
        PasoRecorrido(
          objetivo: buscar,
          titulo: "Buscar y editar",
          texto: "Encontrá cualquier producto. Con ⋮ lo editás o ajustás solo el stock después de un conteo.",
        ),
        PasoRecorrido(
          objetivo: importar,
          titulo: "¿Tenés una lista en Excel?",
          texto: "Subila y se crean todos de una vez; la IA le busca el CABYS a cada uno.",
        ),
        PasoRecorrido(
          objetivo: precios,
          titulo: "Actualizar precios",
          texto: "Subí los precios de varios productos a la vez, por porcentaje.",
        ),
        PasoRecorrido(
          objetivo: pestanas,
          titulo: "Categorías",
          texto: "Agrupá los productos (Bebidas, Repuestos...) para encontrarlos rápido y verlos en los reportes.",
        ),
      ]);
}

/// Clientes (detalle_negocio.dart, sección Clientes).
class GuiaClientes {
  static const clave = 'clientes';
  static final nuevo = GlobalKey(debugLabel: 'guia_cli_nuevo');
  static final buscar = GlobalKey(debugLabel: 'guia_cli_buscar');
  static final historial = GlobalKey(debugLabel: 'guia_cli_historial');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: [
        const PasoRecorrido(
          titulo: "Tus clientes",
          texto: "Con el cliente guardado, facturarle es elegirlo de la lista: sus datos van solos al comprobante.",
        ),
        PasoRecorrido(
          objetivo: nuevo,
          titulo: "Nuevo cliente",
          texto: "Escribí la cédula y se trae el nombre desde Hacienda. Agregá el correo: ahí le llegan las facturas (y una copia a quien vos digás).",
        ),
        PasoRecorrido(
          objetivo: buscar,
          titulo: "Buscar",
          texto: "Por nombre, cédula o correo.",
        ),
        PasoRecorrido(
          objetivo: historial,
          titulo: "Historial de precios",
          texto: "Qué le vendiste y a qué precio. Al facturarle, la app te avisa si le estás cambiando el precio.",
        ),
      ]);
}

/// Cuentas por cobrar (cuentas_por_cobrar_screen.dart).
class GuiaCobrar {
  static const clave = 'cuentas_cobrar';
  static final total = GlobalKey(debugLabel: 'guia_cxc_total');
  static final cliente = GlobalKey(debugLabel: 'guia_cxc_cliente');
  static final pagos = GlobalKey(debugLabel: 'guia_cxc_pagos');
  static final recordatorios = GlobalKey(debugLabel: 'guia_cxc_recordatorios');
  static final exportar = GlobalKey(debugLabel: 'guia_cxc_exportar');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: [
        const PasoRecorrido(
          titulo: "Cuentas por cobrar",
          texto: "Quién te debe y cuánto: cada factura a crédito suma al saldo del cliente hasta que te pague.",
        ),
        PasoRecorrido(
          objetivo: total,
          titulo: "Total por cobrar",
          texto: "Lo que te deben entre todos los clientes.",
        ),
        PasoRecorrido(
          objetivo: cliente,
          titulo: "El saldo de cada cliente",
          texto: "Tocá un cliente para ver sus facturas pendientes y registrar un abono (efectivo, SINPE, transferencia...). El abono baja el saldo y le podés mandar el recibo.",
        ),
        PasoRecorrido(
          objetivo: pagos,
          titulo: "Pagos reportados",
          texto: "Cuando un cliente paga desde el enlace de su factura, aparece aquí para que lo confirmés.",
        ),
        PasoRecorrido(
          objetivo: recordatorios,
          titulo: "Recordatorios de cobro",
          texto: "Arma un mensaje de WhatsApp para cada cliente con lo que debe, listo para mandar.",
        ),
        PasoRecorrido(
          objetivo: exportar,
          titulo: "Exportar",
          texto: "El estado de cuentas en PDF o en Excel.",
        ),
      ]);
}

/// Notas de crédito y débito (notas_credito_debito_screen.dart).
class GuiaNotas {
  static const clave = 'notas';
  static final nueva = GlobalKey(debugLabel: 'guia_notas_nueva');
  static final pestanas = GlobalKey(debugLabel: 'guia_notas_pestanas');
  static final estados = GlobalKey(debugLabel: 'guia_notas_estados');

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: [
        const PasoRecorrido(
          titulo: "Notas de crédito y débito",
          texto: "Una factura emitida no se borra ni se edita: se corrige con una nota, que se manda a Hacienda igual que una factura.",
        ),
        PasoRecorrido(
          objetivo: nueva,
          titulo: "Nueva nota de crédito",
          texto: "Para anular o rebajar una factura (devolución, precio equivocado): elegís la factura y si es total o solo algunas líneas. Lo devuelto vuelve al inventario.",
        ),
        PasoRecorrido(
          objetivo: pestanas,
          titulo: "Las tres pestañas",
          texto: "Las notas de crédito que emitiste, las de débito (para cobrar de más, como intereses) y las notas de débito que te mandan tus proveedores.",
        ),
        PasoRecorrido(
          objetivo: estados,
          titulo: "Estado en Hacienda",
          texto: "Revisá si Hacienda ya aceptó tus notas de crédito.",
        ),
      ]);
}
