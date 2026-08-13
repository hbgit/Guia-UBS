-- Conteudo estatico: locais, cartoes de resposta, servicos, documentos e fluxo.
-- Carregado ANTES das regras porque `routing_outcome` referencia `card` e `venue`.
--
-- Semantica de cor fixa (design.html): verde = UBS/rotina, vermelho = emergencia,
-- azul = informacao. A cor carrega significado e nao pode ser trocada por estilo.

-- --- Locais de atendimento -------------------------------------------------
INSERT INTO venue (id, icon_ref, color_token) VALUES
('UBS',      'icon.ubs',      'green'),
('UPA',      'icon.upa',      'red'),
('HOSPITAL', 'icon.hospital', 'red');

INSERT INTO venue_translation (venue_id, lang, label, audio_ref) VALUES
('UBS','pt','UBS — posto de saúde',NULL),   ('UBS','es','UBS — centro de salud',NULL),
('UPA','pt','UPA — pronto atendimento',NULL), ('UPA','es','UPA — urgencias',NULL),
('HOSPITAL','pt','Hospital',NULL),          ('HOSPITAL','es','Hospital',NULL);

-- --- Cartoes de resposta ---------------------------------------------------
INSERT INTO card (id, kind, icon_ref, color_token, sort_order) VALUES
('card.routine',   'result', 'icon.card.routine',   'green', 10),
('card.emergency', 'result', 'icon.card.emergency', 'red',   20),
('card.docs',      'info',   'icon.card.docs',      'blue',  30),
('card.flow',      'info',   'icon.card.flow',      'blue',  40);

INSERT INTO card_translation (card_id, lang, title, body, audio_ref) VALUES
('card.routine','pt','Procure a UBS',
 'Não é emergência. Vá à UBS amanhã de manhã e leve seus documentos.',NULL),
('card.routine','es','Busque la UBS',
 'No es emergencia. Vaya a la UBS mañana por la mañana y lleve sus documentos.',NULL),
('card.emergency','pt','Procure emergência agora',
 'Vá à UPA ou ao hospital agora, ou ligue 192.',NULL),
('card.emergency','es','Busque emergencia ahora',
 'Vaya a la UPA o al hospital ahora, o llame al 192.',NULL),
('card.docs','pt','O que levar','Documentos necessários para ser atendido.',NULL),
('card.docs','es','Qué llevar','Documentos necesarios para ser atendido.',NULL),
('card.flow','pt','Como funciona a UBS','Passo a passo do atendimento.',NULL),
('card.flow','es','Cómo funciona la UBS','Paso a paso de la atención.',NULL);

-- --- Servicos --------------------------------------------------------------
INSERT INTO service (id, venue_id, icon_ref, sort_order) VALUES
('svc.vaccine',   'UBS', 'icon.svc.vaccine',   10),
('svc.dressing',  'UBS', 'icon.svc.dressing',  20),
('svc.consult',   'UBS', 'icon.svc.consult',   30),
('svc.emergency', 'UPA', 'icon.svc.emergency', 40);

INSERT INTO service_translation (service_id, lang, label, audio_ref) VALUES
('svc.vaccine','pt','Vacina',NULL),            ('svc.vaccine','es','Vacuna',NULL),
('svc.dressing','pt','Curativo',NULL),         ('svc.dressing','es','Curación',NULL),
('svc.consult','pt','Consulta',NULL),          ('svc.consult','es','Consulta',NULL),
('svc.emergency','pt','Atendimento de urgência',NULL),
('svc.emergency','es','Atención de urgencia',NULL);

-- --- Documentos ------------------------------------------------------------
INSERT INTO document (id, icon_ref, image_ref) VALUES
('doc.sus',     'icon.doc.sus',     'img.doc.sus'),
('doc.id',      'icon.doc.id',      'img.doc.id'),
('doc.address', 'icon.doc.address', 'img.doc.address');

INSERT INTO document_translation (document_id, lang, label, hint, audio_ref) VALUES
('doc.sus','pt','Cartão SUS','Se não tiver, faz na hora — é grátis.',NULL),
('doc.sus','es','Tarjeta SUS','Si no la tiene, se hace al momento — es gratis.',NULL),
('doc.id','pt','Identidade ou passaporte','Qualquer documento com foto serve.',NULL),
('doc.id','es','Identidad o pasaporte','Cualquier documento con foto sirve.',NULL),
('doc.address','pt','Comprovante de endereço','Conta de luz ou declaração do bairro.',NULL),
('doc.address','es','Comprobante de domicilio','Recibo de luz o declaración del barrio.',NULL);

-- Todo servico exige os tres documentos; o endereco e dispensavel na urgencia.
INSERT INTO service_document (service_id, document_id, required) VALUES
('svc.vaccine','doc.sus',1),   ('svc.vaccine','doc.id',1),   ('svc.vaccine','doc.address',0),
('svc.dressing','doc.sus',1),  ('svc.dressing','doc.id',1),  ('svc.dressing','doc.address',0),
('svc.consult','doc.sus',1),   ('svc.consult','doc.id',1),   ('svc.consult','doc.address',1),
('svc.emergency','doc.sus',0), ('svc.emergency','doc.id',1);

-- --- Fluxo de atendimento na UBS -------------------------------------------
INSERT INTO flow_step (id, venue_id, step_order, icon_ref) VALUES
('step.reception', 'UBS', 1, 'icon.step.reception'),
('step.triage',    'UBS', 2, 'icon.step.triage'),
('step.consult',   'UBS', 3, 'icon.step.consult'),
('step.pharmacy',  'UBS', 4, 'icon.step.pharmacy');

INSERT INTO flow_step_translation (step_id, lang, title, body, audio_ref) VALUES
('step.reception','pt','Recepção','Mostre seu documento no balcão.',NULL),
('step.reception','es','Recepción','Muestre su documento en el mostrador.',NULL),
('step.triage','pt','Acolhimento','O enfermeiro mede a pressão e escuta você.',NULL),
('step.triage','es','Acogida','El enfermero mide la presión y le escucha.',NULL),
('step.consult','pt','Consulta','Converse com o médico.',NULL),
('step.consult','es','Consulta','Hable con el médico.',NULL),
('step.pharmacy','pt','Farmácia','Pegue o remédio de graça, se receitado.',NULL),
('step.pharmacy','es','Farmacia','Retire el medicamento gratis, si es recetado.',NULL);
