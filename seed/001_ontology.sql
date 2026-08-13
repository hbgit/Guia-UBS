-- Ontologia de sintomas: o vocabulario que o usuario compoe tocando em icones.
--
-- Os `id` sao CONTRATO IMUTAVEL. Renomear um token orfana silenciosamente as regras
-- que o referenciam — por isso o packer bloqueia a assinatura quando encontra orfao.
-- Para retirar um token de circulacao use `deprecated = 1`, nunca DELETE.

INSERT INTO symptom_token (id, kind, icon_ref, sort_order, deprecated) VALUES
-- partes do corpo
('head',        'body_part', 'icon.head',    10, 0),
('throat',      'body_part', 'icon.throat',  20, 0),
('chest',       'body_part', 'icon.chest',   30, 0),
('belly',       'body_part', 'icon.belly',   40, 0),
('back',        'body_part', 'icon.back',    50, 0),
('arm',         'body_part', 'icon.arm',     60, 0),
('leg',         'body_part', 'icon.leg',     70, 0),
('skin',        'body_part', 'icon.skin',    80, 0),
-- sintomas
('pain',        'symptom', 'icon.pain',        10, 0),
('fever',       'symptom', 'icon.fever',       20, 0),
('breathless',  'symptom', 'icon.breathless',  30, 0),
('bleeding',    'symptom', 'icon.bleeding',    40, 0),
('palpitation', 'symptom', 'icon.palpitation', 50, 0),
('dizzy',       'symptom', 'icon.dizzy',       60, 0),
('vomit',       'symptom', 'icon.vomit',       70, 0),
('diarrhea',    'symptom', 'icon.diarrhea',    80, 0),
('cough',       'symptom', 'icon.cough',       90, 0),
('swelling',    'symptom', 'icon.swelling',   100, 0),
('rash',        'symptom', 'icon.rash',       110, 0),
('cut',         'symptom', 'icon.cut',        120, 0),
-- modificadores (intensidade, tempo e perfil)
('severe',      'modifier', 'icon.severe',     10, 0),
('sudden',      'modifier', 'icon.sudden',     20, 0),
('persistent',  'modifier', 'icon.persistent', 30, 0),
('pregnant',    'modifier', 'icon.pregnant',   40, 0),
('infant',      'modifier', 'icon.infant',     50, 0),
('elderly',     'modifier', 'icon.elderly',    60, 0);

-- Rotulos. Redundantes ao icone: a interface nunca exige leitura (espec.md RNF-06).
-- O `audio_ref` fica nulo no pacote semente; a narracao entra com os audios do M2.
INSERT INTO token_translation (token_id, lang, label, audio_ref) VALUES
('head','pt','Cabeça',NULL),              ('head','es','Cabeza',NULL),
('throat','pt','Garganta',NULL),          ('throat','es','Garganta',NULL),
('chest','pt','Peito',NULL),              ('chest','es','Pecho',NULL),
('belly','pt','Barriga',NULL),            ('belly','es','Barriga',NULL),
('back','pt','Costas',NULL),              ('back','es','Espalda',NULL),
('arm','pt','Braço',NULL),                ('arm','es','Brazo',NULL),
('leg','pt','Perna',NULL),                ('leg','es','Pierna',NULL),
('skin','pt','Pele',NULL),                ('skin','es','Piel',NULL),
('pain','pt','Dor',NULL),                 ('pain','es','Dolor',NULL),
('fever','pt','Febre',NULL),              ('fever','es','Fiebre',NULL),
('breathless','pt','Falta de ar',NULL),   ('breathless','es','Falta de aire',NULL),
('bleeding','pt','Sangramento',NULL),     ('bleeding','es','Sangrado',NULL),
('palpitation','pt','Coração acelerado',NULL), ('palpitation','es','Corazón acelerado',NULL),
('dizzy','pt','Tontura',NULL),            ('dizzy','es','Mareo',NULL),
('vomit','pt','Vômito',NULL),             ('vomit','es','Vómito',NULL),
('diarrhea','pt','Diarreia',NULL),        ('diarrhea','es','Diarrea',NULL),
('cough','pt','Tosse',NULL),              ('cough','es','Tos',NULL),
('swelling','pt','Inchaço',NULL),         ('swelling','es','Hinchazón',NULL),
('rash','pt','Manchas na pele',NULL),     ('rash','es','Manchas en la piel',NULL),
('cut','pt','Corte',NULL),                ('cut','es','Corte',NULL),
('severe','pt','Muito forte',NULL),       ('severe','es','Muy fuerte',NULL),
('sudden','pt','Começou de repente',NULL),('sudden','es','Empezó de repente',NULL),
('persistent','pt','Não passa',NULL),     ('persistent','es','No pasa',NULL),
('pregnant','pt','Grávida',NULL),         ('pregnant','es','Embarazada',NULL),
('infant','pt','Bebê',NULL),              ('infant','es','Bebé',NULL),
('elderly','pt','Pessoa idosa',NULL),     ('elderly','es','Persona mayor',NULL);
