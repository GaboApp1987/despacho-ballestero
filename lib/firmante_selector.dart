import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'firmante_contador.dart';

/// Selector de "Firmante" para Certificación de Ingresos/Atestiguamiento/
/// Flujo de Caja -- solo se muestra si el contador desactivó "Firmar con
/// mi nombre registrado" en su perfil y tiene al menos un firmante
/// cargado (ver Socio.firmarConNombreRegistrado). El firmante elegido acá
/// es el nombre/carné que sale impreso en el PDF/Word final.
Widget selectorFirmante({
  required bool firmarConNombreRegistrado,
  required List<FirmanteContador> firmantes,
  required int? firmanteSeleccionado,
  required ValueChanged<int?> onChanged,
}) {
  if (firmarConNombreRegistrado || firmantes.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: DropdownButtonFormField<int>(
      initialValue: firmanteSeleccionado,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: "Firmante *",
        labelStyle: const TextStyle(color: TemaContador.textoTenue),
        filled: true,
        fillColor: TemaContador.superficie,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.borde)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TemaContador.acento, width: 1.5)),
      ),
      style: const TextStyle(color: TemaContador.textoFuerte),
      dropdownColor: TemaContador.fondo,
      items: firmantes
          .map((f) => DropdownMenuItem(
                value: f.id,
                child: Text(
                  f.carneCpa.isNotEmpty ? "${f.nombre} (Carné ${f.carneCpa})" : f.nombre,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: TemaContador.textoFuerte),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    ),
  );
}
