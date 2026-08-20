/// Ponte entre o `icon_ref` do pack e um ícone desenhável.
///
/// ## Por que um mapa em código, e por enquanto
///
/// O pack referencia ícones por `ref` (`icon.chest`) e traz os arquivos SVG
/// como assets. Renderizá-los exige um renderizador de SVG e a extração dos
/// assets do pacote — trabalho da Fase 4, junto com os áudios.
///
/// Até lá, `ref` conhecido vira ícone do Material. **O padrão importa mais que
/// o mapa:** um `ref` que este binário não conhece devolve um ícone genérico
/// visível, nunca um espaço vazio. Ícone ausente numa interface iconográfica
/// não é degradação de estilo — é a opção inteira desaparecendo para quem não
/// lê o rótulo.
library;

import 'package:flutter/material.dart';

import '../../../content/domain/content_models.dart';

const Map<String, IconData> _icons = {
  // Partes do corpo
  'icon.head': Icons.face,
  'icon.throat': Icons.record_voice_over,
  'icon.chest': Icons.favorite_border,
  'icon.belly': Icons.circle_outlined,
  'icon.back': Icons.airline_seat_recline_normal,
  'icon.arm': Icons.back_hand,
  'icon.leg': Icons.directions_walk,
  'icon.skin': Icons.texture,
  // Sintomas
  'icon.pain': Icons.bolt,
  'icon.fever': Icons.thermostat,
  'icon.breathless': Icons.air,
  'icon.bleeding': Icons.water_drop,
  'icon.palpitation': Icons.monitor_heart,
  'icon.dizzy': Icons.blur_on,
  'icon.vomit': Icons.sick,
  'icon.diarrhea': Icons.wc,
  'icon.cough': Icons.masks,
  'icon.swelling': Icons.bubble_chart,
  'icon.rash': Icons.grain,
  'icon.cut': Icons.content_cut,
  // Modificadores
  'icon.severe': Icons.priority_high,
  'icon.sudden': Icons.flash_on,
  'icon.persistent': Icons.schedule,
  'icon.pregnant': Icons.pregnant_woman,
  'icon.infant': Icons.child_care,
  'icon.elderly': Icons.elderly,
  // Serviços
  'icon.svc.vaccine': Icons.vaccines,
  'icon.svc.dressing': Icons.healing,
  'icon.svc.consult': Icons.medical_information,
  'icon.svc.emergency': Icons.emergency_share,
  // Documentos
  'icon.doc.sus': Icons.credit_card,
  'icon.doc.id': Icons.badge,
  'icon.doc.address': Icons.home_work,
  // Passos do fluxo
  'icon.step.reception': Icons.support_agent,
  'icon.step.triage': Icons.monitor_heart,
  'icon.step.consult': Icons.medical_services,
  'icon.step.pharmacy': Icons.medication,
  // Locais e cartões
  'icon.ubs': Icons.local_hospital,
  'icon.upa': Icons.emergency,
  'icon.hospital': Icons.local_hospital,
  'icon.card.routine': Icons.check_circle,
  'icon.card.emergency': Icons.emergency,
  'icon.card.docs': Icons.badge,
  'icon.card.flow': Icons.list_alt,
};

/// Ícone genérico para `ref` desconhecido. Visível de propósito.
const IconData unknownIcon = Icons.help_outline;

IconData iconForRef(String ref) => _icons[ref] ?? unknownIcon;

IconData iconForToken(SymptomToken token) => iconForRef(token.iconRef);
