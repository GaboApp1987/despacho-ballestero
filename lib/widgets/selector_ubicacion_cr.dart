import 'package:flutter/material.dart';

import '../ubicacion_cr.dart';

/// Provincia / Cantón / Distrito del catálogo oficial de Hacienda, en
/// cascada -- mismo patrón que la ubicación del negocio en Ajustes, para
/// usarlo donde haga falta (ej. el proveedor del régimen simplificado al que
/// se le emite una Factura Electrónica de Compra).
class SelectorUbicacionCR extends StatefulWidget {
  final String? provincia;
  final String? canton;
  final String? distrito;
  final void Function(String? provincia, String? canton, String? distrito) onChanged;

  const SelectorUbicacionCR({
    super.key,
    this.provincia,
    this.canton,
    this.distrito,
    required this.onChanged,
  });

  @override
  State<SelectorUbicacionCR> createState() => _SelectorUbicacionCRState();
}

class _SelectorUbicacionCRState extends State<SelectorUbicacionCR> {
  List<ProvinciaCR> _ubicaciones = [];
  String? _provincia;
  String? _canton;
  String? _distrito;

  @override
  void initState() {
    super.initState();
    _provincia = (widget.provincia ?? '').isEmpty ? null : widget.provincia;
    _canton = (widget.canton ?? '').isEmpty ? null : widget.canton;
    _distrito = (widget.distrito ?? '').isEmpty ? null : widget.distrito;
    UbicacionCR.cargar().then((u) {
      if (mounted) setState(() => _ubicaciones = u);
    });
  }

  List<CantonCR> get _cantones {
    final prov = _ubicaciones.where((p) => p.codigo == _provincia);
    return prov.isEmpty ? [] : prov.first.cantones;
  }

  List<DistritoCR> get _distritos {
    final cant = _cantones.where((c) => c.codigo == _canton);
    return cant.isEmpty ? [] : cant.first.distritos;
  }

  void _avisar() => widget.onChanged(_provincia, _canton, _distrito);

  @override
  Widget build(BuildContext context) {
    if (_ubicaciones.isEmpty) {
      return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    }
    // Si el código guardado no existe en el catálogo, el Dropdown no puede
    // mostrarlo como seleccionado: se deja vacío.
    final cantonValido = _cantones.any((c) => c.codigo == _canton) ? _canton : null;
    final distritoValido = _distritos.any((d) => d.codigo == _distrito) ? _distrito : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _ubicaciones.any((p) => p.codigo == _provincia) ? _provincia : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: "Provincia", border: OutlineInputBorder()),
          items: _ubicaciones.map((p) => DropdownMenuItem(value: p.codigo, child: Text(p.nombre))).toList(),
          onChanged: (v) => setState(() {
            _provincia = v;
            _canton = null;
            _distrito = null;
            _avisar();
          }),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey('canton-$_provincia'),
          initialValue: cantonValido,
          isExpanded: true,
          decoration: const InputDecoration(labelText: "Cantón", border: OutlineInputBorder()),
          items: _cantones.map((c) => DropdownMenuItem(value: c.codigo, child: Text(c.nombre))).toList(),
          onChanged: _provincia == null
              ? null
              : (v) => setState(() {
                    _canton = v;
                    _distrito = null;
                    _avisar();
                  }),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey('distrito-$_provincia-$_canton'),
          initialValue: distritoValido,
          isExpanded: true,
          decoration: const InputDecoration(labelText: "Distrito", border: OutlineInputBorder()),
          items: _distritos.map((d) => DropdownMenuItem(value: d.codigo, child: Text(d.nombre))).toList(),
          onChanged: _canton == null
              ? null
              : (v) => setState(() {
                    _distrito = v;
                    _avisar();
                  }),
        ),
      ],
    );
  }
}
