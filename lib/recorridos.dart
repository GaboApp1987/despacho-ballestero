import 'package:flutter/material.dart';

import 'restaurante_tema.dart';
import 'theme/app_theme.dart';
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

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}

/// La lista de compras (compras_screen.dart).
class GuiaCompras {
  static const clave = 'compras';
  static final nueva = GlobalKey(debugLabel: 'guia_compras_nueva');
  static final porRevisar = GlobalKey(debugLabel: 'guia_compras_revisar');
  static final importarVarios = GlobalKey(debugLabel: 'guia_compras_importar');

  static List<PasoRecorrido> pasos({String cedulaNegocio = 'la-cedula'}) => [
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
      ];

  static void mostrar(BuildContext context, {required String cedulaNegocio}) =>
      mostrarRecorrido(context, clave: clave, pasos: pasos(cedulaNegocio: cedulaNegocio));
}

/// Registrar una compra (formulario_compra.dart).
class GuiaCompra {
  static const clave = 'compra';
  static final adjuntar = GlobalKey(debugLabel: 'guia_compra_adjuntar');
  static final proveedor = GlobalKey(debugLabel: 'guia_compra_proveedor');
  static final condicion = GlobalKey(debugLabel: 'guia_compra_condicion');
  static final aceptar = GlobalKey(debugLabel: 'guia_compra_aceptar');
  static final confirmar = GlobalKey(debugLabel: 'guia_compra_confirmar');

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}

/// El salón del restaurante (restaurante_screen.dart).
class GuiaRestaurante {
  static const clave = 'restaurante';
  static final mesas = GlobalKey(debugLabel: 'guia_resto_mesas');
  static final paraLlevar = GlobalKey(debugLabel: 'guia_resto_llevar');
  static final pestanas = GlobalKey(debugLabel: 'guia_resto_pestanas');

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: colorResto, pasos: pasos);
}

/// La cuenta de una mesa (restaurante_orden_screen.dart).
class GuiaOrden {
  static const clave = 'restaurante_orden';
  static final menu = GlobalKey(debugLabel: 'guia_orden_menu');
  static final agregarPlatos = GlobalKey(debugLabel: 'guia_orden_agregar');
  static final enviar = GlobalKey(debugLabel: 'guia_orden_enviar');
  static final cobrar = GlobalKey(debugLabel: 'guia_orden_cobrar');

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: colorResto, pasos: pasos);
}


/// Cierre de caja (caja_screen.dart).
class GuiaCaja {
  static const clave = 'caja';
  static final fondo = GlobalKey(debugLabel: 'guia_caja_fondo');
  static final movimientos = GlobalKey(debugLabel: 'guia_caja_movimientos');
  static final resumen = GlobalKey(debugLabel: 'guia_caja_resumen');
  static final cerrar = GlobalKey(debugLabel: 'guia_caja_cerrar');
  static final historial = GlobalKey(debugLabel: 'guia_caja_historial');

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}

/// Inventario (inventario_screen.dart).
class GuiaInventario {
  static const clave = 'inventario';
  static final nuevo = GlobalKey(debugLabel: 'guia_inv_nuevo');
  static final buscar = GlobalKey(debugLabel: 'guia_inv_buscar');
  static final importar = GlobalKey(debugLabel: 'guia_inv_importar');
  static final precios = GlobalKey(debugLabel: 'guia_inv_precios');
  static final pestanas = GlobalKey(debugLabel: 'guia_inv_pestanas');

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}

/// Clientes (detalle_negocio.dart, sección Clientes).
class GuiaClientes {
  static const clave = 'clientes';
  static final nuevo = GlobalKey(debugLabel: 'guia_cli_nuevo');
  static final buscar = GlobalKey(debugLabel: 'guia_cli_buscar');
  static final historial = GlobalKey(debugLabel: 'guia_cli_historial');
  static final importar = GlobalKey(debugLabel: 'guia_cli_importar');

  static List<PasoRecorrido> get pasos => [
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
          objetivo: importar,
          titulo: "¿Venís de otro sistema?",
          texto: "Subí tu lista de clientes en Excel, CSV o PDF y se crean todos de una vez. Los que ya estaban no se repiten.",
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}

/// Cuentas por cobrar (cuentas_por_cobrar_screen.dart).
class GuiaCobrar {
  static const clave = 'cuentas_cobrar';
  static final total = GlobalKey(debugLabel: 'guia_cxc_total');
  static final cliente = GlobalKey(debugLabel: 'guia_cxc_cliente');
  static final pagos = GlobalKey(debugLabel: 'guia_cxc_pagos');
  static final recordatorios = GlobalKey(debugLabel: 'guia_cxc_recordatorios');
  static final exportar = GlobalKey(debugLabel: 'guia_cxc_exportar');

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}

/// Notas de crédito y débito (notas_credito_debito_screen.dart).
class GuiaNotas {
  static const clave = 'notas';
  static final nueva = GlobalKey(debugLabel: 'guia_notas_nueva');
  static final pestanas = GlobalKey(debugLabel: 'guia_notas_pestanas');
  static final estados = GlobalKey(debugLabel: 'guia_notas_estados');

  static List<PasoRecorrido> get pasos => [
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
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}


// ---------------------------------------------------------------- Contador

/// Panel del contador (negocios_screen.dart).
class GuiaPanelContador {
  static const clave = 'panel_contador';
  static final asistente = GlobalKey(debugLabel: 'guia_panel_asistente');
  static final cliente = GlobalKey(debugLabel: 'guia_panel_cliente');
  static final menu = GlobalKey(debugLabel: 'guia_panel_menu');
  static final nuevo = GlobalKey(debugLabel: 'guia_panel_nuevo');

  static List<PasoRecorrido> get pasos => [
        const PasoRecorrido(
          titulo: "Tu panel de contador",
          texto: "Desde aquí manejás a todos tus clientes: entrás a cada negocio, llevás su contabilidad y sacás sus reportes.",
        ),
        PasoRecorrido(
          objetivo: asistente,
          titulo: "Preguntale a la IA",
          texto: "Escribí lo que necesitás, como \"el IVA de septiembre de Soda Mora\", y te lleva a donde es o te lo arma.",
        ),
        PasoRecorrido(
          objetivo: cliente,
          titulo: "Tus clientes",
          texto: "Tocá un cliente para entrar a su negocio: facturas, compras, bancos y declaraciones. Arriba siempre ves con qué perfil estás trabajando.",
        ),
        PasoRecorrido(
          objetivo: menu,
          titulo: "El menú",
          texto: "Contabilidad (catálogo, asientos y bancos), reportes, certificaciones y chats con tus clientes. Con el buscador encontrás cualquier cliente.",
        ),
        PasoRecorrido(
          objetivo: nuevo,
          titulo: "Nuevo negocio",
          texto: "Registrá un cliente nuevo con su cédula y sus datos de Hacienda.",
        ),
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: TemaContador.acento, pasos: pasos);
}

/// Bancos de un cliente (bancos_screen.dart).
class GuiaBancos {
  static const clave = 'bancos';
  static final nueva = GlobalKey(debugLabel: 'guia_bancos_nueva');
  static final cuenta = GlobalKey(debugLabel: 'guia_bancos_cuenta');
  static final traslado = GlobalKey(debugLabel: 'guia_bancos_traslado');

  static List<PasoRecorrido> get pasos => [
        const PasoRecorrido(
          titulo: "Bancos",
          texto: "Las cuentas bancarias del negocio (y la caja, si maneja efectivo). Cada movimiento genera su asiento contable solo.",
        ),
        PasoRecorrido(
          objetivo: nueva,
          titulo: "Nueva cuenta",
          texto: "Banco, moneda y saldo inicial. Se le crea su propia cuenta contable para que el mayor de cada banco salga aparte.",
        ),
        PasoRecorrido(
          objetivo: cuenta,
          titulo: "Movimientos y conciliación",
          texto: "Tocá una cuenta para registrar depósitos, cheques o comisiones. Adentro, arriba a la derecha, está Conciliación para cuadrarla con el estado de cuenta.",
        ),
        PasoRecorrido(
          objetivo: traslado,
          titulo: "Traslados",
          texto: "Para pasar plata entre cuentas propias, también entre colones y dólares.",
        ),
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, pasos: pasos);
}

/// Conciliación bancaria de un mes (conciliacion_screen.dart).
class GuiaConciliacion {
  static const clave = 'conciliacion';
  static final cargar = GlobalKey(debugLabel: 'guia_conc_cargar');
  static final emparejar = GlobalKey(debugLabel: 'guia_conc_emparejar');
  static final resumen = GlobalKey(debugLabel: 'guia_conc_resumen');
  static final banco = GlobalKey(debugLabel: 'guia_conc_banco');
  static final cerrar = GlobalKey(debugLabel: 'guia_conc_cerrar');

  static List<PasoRecorrido> get pasos => [
        const PasoRecorrido(
          titulo: "Conciliar el mes",
          texto: "Se compara el estado de cuenta del banco con lo registrado en libros. Cuando cuadran, cerrás el mes y queda bloqueado.",
        ),
        PasoRecorrido(
          objetivo: cargar,
          titulo: "Cargá el estado de cuenta",
          texto: "El Excel o CSV que bajás del banco. Lo que coincide con libros (mismo monto, hasta 5 días de diferencia) se empareja solo.",
        ),
        PasoRecorrido(
          objetivo: emparejar,
          titulo: "Emparejar automático",
          texto: "Vuelve a buscar coincidencias, por ejemplo después de registrar algo que faltaba.",
        ),
        PasoRecorrido(
          objetivo: resumen,
          titulo: "¿Cuadra?",
          texto: "El banco ajustado (con depósitos en tránsito y pagos pendientes) contra los libros ajustados. La diferencia tiene que quedar en cero.",
        ),
        PasoRecorrido(
          objetivo: banco,
          titulo: "Lo que falta",
          texto: "En cada línea sin emparejar, con ⋮: emparejala a mano o registrala en libros (comisiones, intereses) con su asiento.",
        ),
        PasoRecorrido(
          objetivo: cerrar,
          titulo: "Cerrar el mes",
          texto: "Se activa cuando cuadra. Los movimientos de ese mes quedan bloqueados para todos; si hace falta corregir, se reabre.",
        ),
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: TemaContador.acento, pasos: pasos);
}

/// Catálogo de cuentas de un cliente (cuentas_contables_screen.dart).
class GuiaCatalogo {
  static const clave = 'catalogo';
  static final estandar = GlobalKey(debugLabel: 'guia_cat_estandar');
  static final copiar = GlobalKey(debugLabel: 'guia_cat_copiar');
  static final buscar = GlobalKey(debugLabel: 'guia_cat_buscar');
  static final nueva = GlobalKey(debugLabel: 'guia_cat_nueva');
  static final acciones = GlobalKey(debugLabel: 'guia_cat_acciones');

  static List<PasoRecorrido> get pasos => [
        const PasoRecorrido(
          titulo: "Catálogo de cuentas",
          texto: "Cada cliente tiene el suyo. Las ventas, compras y bancos generan sus asientos contra estas cuentas.",
        ),
        PasoRecorrido(
          objetivo: estandar,
          titulo: "Arrancá rápido",
          texto: "Cargá el catálogo estándar de Costa Rica con un toque y después ajustalo.",
        ),
        PasoRecorrido(
          objetivo: copiar,
          titulo: "O copialo",
          texto: "Desde tu plantilla, desde otro cliente o desde un Excel.",
        ),
        PasoRecorrido(
          objetivo: buscar,
          titulo: "Buscar",
          texto: "Por código, nombre o tipo. Tocá una cuenta para editarla.",
        ),
        PasoRecorrido(
          objetivo: nueva,
          titulo: "Nueva cuenta",
          texto: "Agregá subcuentas de detalle (las que reciben movimientos) debajo de su cuenta madre.",
        ),
        PasoRecorrido(
          objetivo: acciones,
          titulo: "Más acciones",
          texto: "Guardá este catálogo como tu plantilla para los próximos clientes, copialo de otro o exportalo a Excel.",
        ),
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: TemaContador.acento, pasos: pasos);
}

/// Asientos contables (asientos_contables_screen.dart).
class GuiaAsientos {
  static const clave = 'asientos';
  static final cliente = GlobalKey(debugLabel: 'guia_asi_cliente');
  static final generar = GlobalKey(debugLabel: 'guia_asi_generar');
  static final nuevo = GlobalKey(debugLabel: 'guia_asi_nuevo');
  static final estados = GlobalKey(debugLabel: 'guia_asi_estados');

  static List<PasoRecorrido> get pasos => [
        const PasoRecorrido(
          titulo: "Asientos contables",
          texto: "La contabilidad de cada cliente. La mayoría de los asientos salen solos de sus ventas, compras y bancos.",
        ),
        PasoRecorrido(
          objetivo: cliente,
          titulo: "Elegí el cliente",
          texto: "Todo lo de abajo es del negocio que elegís aquí.",
        ),
        PasoRecorrido(
          objetivo: generar,
          titulo: "Generar automáticos",
          texto: "Crea los asientos de las facturas, compras y gastos que todavía no los tienen.",
        ),
        PasoRecorrido(
          objetivo: nuevo,
          titulo: "Asiento manual",
          texto: "Para ajustes, depreciaciones o cierres: líneas al debe y al haber, que tienen que cuadrar.",
        ),
        PasoRecorrido(
          objetivo: estados,
          titulo: "Estados financieros",
          texto: "El balance general y el estado de resultados del cliente, listos para exportar.",
        ),
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: TemaContador.acento, pasos: pasos);
}

/// Centro de reportes (reportes_contador_screen.dart).
class GuiaReportes {
  static const clave = 'reportes';
  static final tipo = GlobalKey(debugLabel: 'guia_rep_tipo');
  static final clientes = GlobalKey(debugLabel: 'guia_rep_clientes');
  static final periodo = GlobalKey(debugLabel: 'guia_rep_periodo');
  static final generar = GlobalKey(debugLabel: 'guia_rep_generar');

  static List<PasoRecorrido> get pasos => [
        const PasoRecorrido(
          titulo: "Centro de reportes",
          texto: "Ventas, compras, IVA y renta de uno o varios clientes a la vez, para la declaración o para mandarlos en PDF o Excel.",
        ),
        PasoRecorrido(
          objetivo: tipo,
          titulo: "1. El reporte",
          texto: "Elegí qué querés ver: ventas, compras, el resumen para la declaración de IVA (D-104) o la renta.",
        ),
        PasoRecorrido(
          objetivo: clientes,
          titulo: "2. Los clientes",
          texto: "Uno, varios o todos: con varios ves el resultado de cada uno.",
        ),
        PasoRecorrido(
          objetivo: periodo,
          titulo: "3. El período",
          texto: "Este mes, el pasado, el trimestre, el año o las fechas que querás.",
        ),
        PasoRecorrido(
          objetivo: generar,
          titulo: "Generar",
          texto: "Lo ves aquí mismo y desde el resultado lo exportás a PDF o Excel.",
        ),
      ];

  static void mostrar(BuildContext context) => mostrarRecorrido(context, clave: clave, color: TemaContador.acento, pasos: pasos);
}
