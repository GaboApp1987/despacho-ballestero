class CuentaContable {
  final int? id;
  final int negocio;
  final String? negocioNombre;
  String codigo;
  String nombre;
  String tipo;
  String naturaleza;
  int? cuentaPadre;
  final String? cuentaPadreNombre;
  bool esDetalle;
  bool activa;

  CuentaContable({
    this.id,
    required this.negocio,
    this.negocioNombre,
    this.codigo = '',
    this.nombre = '',
    this.tipo = 'activo',
    this.naturaleza = 'deudora',
    this.cuentaPadre,
    this.cuentaPadreNombre,
    this.esDetalle = true,
    this.activa = true,
  });

  static const Map<String, String> tiposEtiquetas = {
    'activo': 'Activo',
    'pasivo': 'Pasivo',
    'patrimonio': 'Patrimonio',
    'ingreso': 'Ingreso',
    'costo': 'Costo',
    'gasto': 'Gasto',
  };

  static const Map<String, String> naturalezaEtiquetas = {
    'deudora': 'Deudora',
    'acreedora': 'Acreedora',
  };

  factory CuentaContable.fromJson(Map<String, dynamic> json) => CuentaContable(
        id: json['id'],
        negocio: json['negocio'],
        negocioNombre: json['negocio_nombre'],
        codigo: json['codigo'] ?? '',
        nombre: json['nombre'] ?? '',
        tipo: json['tipo'] ?? 'activo',
        naturaleza: json['naturaleza'] ?? 'deudora',
        cuentaPadre: json['cuenta_padre'],
        cuentaPadreNombre: json['cuenta_padre_nombre'],
        esDetalle: json['es_detalle'] ?? true,
        activa: json['activa'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'negocio': negocio,
        'codigo': codigo,
        'nombre': nombre,
        'tipo': tipo,
        'naturaleza': naturaleza,
        if (cuentaPadre != null) 'cuenta_padre': cuentaPadre,
        'es_detalle': esDetalle,
        'activa': activa,
      };
}
