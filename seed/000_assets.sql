-- Assets do pacote semente.
--
-- Os arquivos sao PLACEHOLDERS gerados por `seed/assets/generate-placeholders.mjs`
-- a partir deste proprio SQL (zero drift entre tabela e disco). O catalogo real de
-- icones vem do marco M1, apos validacao em campo com o publico-alvo — nenhum icone
-- aqui foi validado para compreensao (brainstorm.md M1).
--
-- O packer calcula sha256 e bytes de cada arquivo em tempo de build; os valores
-- gravados aqui sao ignorados e reescritos.

INSERT INTO asset (ref, kind, path, sha256, bytes) VALUES
-- partes do corpo
('icon.head',        'icon', 'assets/icon.head.svg',        '', 0),
('icon.chest',       'icon', 'assets/icon.chest.svg',       '', 0),
('icon.belly',       'icon', 'assets/icon.belly.svg',       '', 0),
('icon.back',        'icon', 'assets/icon.back.svg',        '', 0),
('icon.throat',      'icon', 'assets/icon.throat.svg',      '', 0),
('icon.arm',         'icon', 'assets/icon.arm.svg',         '', 0),
('icon.leg',         'icon', 'assets/icon.leg.svg',         '', 0),
('icon.skin',        'icon', 'assets/icon.skin.svg',        '', 0),
-- sintomas
('icon.pain',        'icon', 'assets/icon.pain.svg',        '', 0),
('icon.fever',       'icon', 'assets/icon.fever.svg',       '', 0),
('icon.bleeding',    'icon', 'assets/icon.bleeding.svg',    '', 0),
('icon.breathless',  'icon', 'assets/icon.breathless.svg',  '', 0),
('icon.dizzy',       'icon', 'assets/icon.dizzy.svg',       '', 0),
('icon.vomit',       'icon', 'assets/icon.vomit.svg',       '', 0),
('icon.diarrhea',    'icon', 'assets/icon.diarrhea.svg',    '', 0),
('icon.cough',       'icon', 'assets/icon.cough.svg',       '', 0),
('icon.swelling',    'icon', 'assets/icon.swelling.svg',    '', 0),
('icon.rash',        'icon', 'assets/icon.rash.svg',        '', 0),
('icon.cut',         'icon', 'assets/icon.cut.svg',         '', 0),
('icon.palpitation', 'icon', 'assets/icon.palpitation.svg', '', 0),
-- modificadores
('icon.severe',      'icon', 'assets/icon.severe.svg',      '', 0),
('icon.sudden',      'icon', 'assets/icon.sudden.svg',      '', 0),
('icon.persistent',  'icon', 'assets/icon.persistent.svg',  '', 0),
('icon.pregnant',    'icon', 'assets/icon.pregnant.svg',    '', 0),
('icon.infant',      'icon', 'assets/icon.infant.svg',      '', 0),
('icon.elderly',     'icon', 'assets/icon.elderly.svg',     '', 0),
-- locais
('icon.ubs',         'icon', 'assets/icon.ubs.svg',         '', 0),
('icon.upa',         'icon', 'assets/icon.upa.svg',         '', 0),
('icon.hospital',    'icon', 'assets/icon.hospital.svg',    '', 0),
-- cartoes de resultado e informacao
('icon.card.routine',   'icon', 'assets/icon.card.routine.svg',   '', 0),
('icon.card.emergency', 'icon', 'assets/icon.card.emergency.svg', '', 0),
('icon.card.docs',      'icon', 'assets/icon.card.docs.svg',      '', 0),
('icon.card.flow',      'icon', 'assets/icon.card.flow.svg',      '', 0),
-- servicos
('icon.svc.vaccine',   'icon', 'assets/icon.svc.vaccine.svg',   '', 0),
('icon.svc.dressing',  'icon', 'assets/icon.svc.dressing.svg',  '', 0),
('icon.svc.consult',   'icon', 'assets/icon.svc.consult.svg',   '', 0),
('icon.svc.emergency', 'icon', 'assets/icon.svc.emergency.svg', '', 0),
-- documentos
('icon.doc.sus',     'icon', 'assets/icon.doc.sus.svg',     '', 0),
('icon.doc.id',      'icon', 'assets/icon.doc.id.svg',      '', 0),
('icon.doc.address', 'icon', 'assets/icon.doc.address.svg', '', 0),
('img.doc.sus',      'image', 'assets/img.doc.sus.svg',     '', 0),
('img.doc.id',       'image', 'assets/img.doc.id.svg',      '', 0),
('img.doc.address',  'image', 'assets/img.doc.address.svg', '', 0),
-- passos do fluxo de atendimento
('icon.step.reception', 'icon', 'assets/icon.step.reception.svg', '', 0),
('icon.step.triage',    'icon', 'assets/icon.step.triage.svg',    '', 0),
('icon.step.consult',   'icon', 'assets/icon.step.consult.svg',   '', 0),
('icon.step.pharmacy',  'icon', 'assets/icon.step.pharmacy.svg',  '', 0);
