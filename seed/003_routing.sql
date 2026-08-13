-- ===========================================================================
-- REGRAS DE ENCAMINHAMENTO — NUCLEO CLINICO DO PRODUTO
-- ===========================================================================
--
-- AVISO: este conjunto e ILUSTRATIVO, para validar o mecanismo na Fase 1.
-- Nenhuma regra aqui passou por revisao clinica. Antes de qualquer piloto com
-- pessoas reais, a tabela inteira exige dupla aprovacao (editor != revisor
-- clinico) e vinculo a protocolo oficial da Atencao Basica — e o packer bloqueia
-- a assinatura enquanto a suite golden nao estiver 100% verde (PRD risco R5).
--
-- MODELO: forma normal disjuntiva. Uma regra dispara quando existe um `group_no`
-- em que TODOS os termos sao satisfeitos (E dentro do grupo, OU entre grupos).
-- `negated = 1` exige a AUSENCIA do token.
--
-- Menor `priority` vence. As red flags da espec.md sao exatamente o subconjunto
-- cujo outcome tem o maior `severity_level` — o gate deterministico as avalia
-- ANTES de qualquer inferencia, e o LLM jamais rebaixa o resultado (INV-1).

-- --- Desfechos -------------------------------------------------------------
-- `severity_level` inteiro torna max(gate, llm) uma comparacao trivial e deixa
-- espaco para niveis intermediarios (ex.: 50 = UBS no mesmo dia) sem migracao.
INSERT INTO routing_outcome (id, severity_level, card_id, venue_id) VALUES
('ROUTINE_UBS', 10,  'card.routine',   'UBS'),
('EMERGENCY',  100,  'card.emergency', 'UPA');

-- --- Red flags (EMERGENCY) -------------------------------------------------
INSERT INTO routing_rule (id, priority, outcome_id, rationale, clinical_source) VALUES
('rf.chest_pain',      10, 'EMERGENCY',
 'Dor toracica pode indicar sindrome coronariana aguda.', 'PLACEHOLDER: revisao clinica pendente'),
('rf.breathless',      11, 'EMERGENCY',
 'Dispneia e sinal de alarme independentemente da causa.', 'PLACEHOLDER: revisao clinica pendente'),
('rf.airway_swelling', 12, 'EMERGENCY',
 'Inchaco de garganta sugere comprometimento de via aerea.', 'PLACEHOLDER: revisao clinica pendente'),
('rf.bleeding_critical', 13, 'EMERGENCY',
 'Sangramento intenso ou em gestante exige avaliacao imediata.', 'PLACEHOLDER: revisao clinica pendente'),
('rf.sudden_headache',  14, 'EMERGENCY',
 'Cefaleia subita e intensa levanta suspeita de evento vascular.', 'PLACEHOLDER: revisao clinica pendente'),
('rf.palpitation',      15, 'EMERGENCY',
 'Palpitacao com dor ou falta de ar sugere arritmia sintomatica.', 'PLACEHOLDER: revisao clinica pendente'),
('rf.infant_fever',     16, 'EMERGENCY',
 'Febre em bebe demanda avaliacao rapida.', 'PLACEHOLDER: revisao clinica pendente');

INSERT INTO routing_rule_term (rule_id, group_no, token_id, negated) VALUES
-- peito + dor
('rf.chest_pain', 0, 'chest', 0),
('rf.chest_pain', 0, 'pain',  0),
-- falta de ar isolada
('rf.breathless', 0, 'breathless', 0),
-- garganta + inchaco
('rf.airway_swelling', 0, 'throat',   0),
('rf.airway_swelling', 0, 'swelling', 0),
-- sangramento intenso OU sangramento em gestante  (dois grupos = OU)
('rf.bleeding_critical', 0, 'bleeding', 0),
('rf.bleeding_critical', 0, 'severe',   0),
('rf.bleeding_critical', 1, 'bleeding', 0),
('rf.bleeding_critical', 1, 'pregnant', 0),
-- cabeca + dor + subito
('rf.sudden_headache', 0, 'head',   0),
('rf.sudden_headache', 0, 'pain',   0),
('rf.sudden_headache', 0, 'sudden', 0),
-- palpitacao + (dor OU falta de ar)
('rf.palpitation', 0, 'palpitation', 0),
('rf.palpitation', 0, 'pain',        0),
('rf.palpitation', 1, 'palpitation', 0),
('rf.palpitation', 1, 'breathless',  0),
-- bebe + febre
('rf.infant_fever', 0, 'infant', 0),
('rf.infant_fever', 0, 'fever',  0);

-- --- Encaminhamentos de rotina (ROUTINE_UBS) -------------------------------
INSERT INTO routing_rule (id, priority, outcome_id, rationale, clinical_source) VALUES
('rt.headache',   100, 'ROUTINE_UBS',
 'Cefaleia sem inicio subito e conduta da Atencao Basica.', 'PLACEHOLDER: revisao clinica pendente'),
('rt.fever',      110, 'ROUTINE_UBS',
 'Febre sem sinal de alarme e conduta da Atencao Basica.', 'PLACEHOLDER: revisao clinica pendente'),
('rt.cough',      120, 'ROUTINE_UBS', 'Tosse sem dispneia.', 'PLACEHOLDER: revisao clinica pendente'),
('rt.wound',      130, 'ROUTINE_UBS', 'Corte leve: curativo na UBS.', 'PLACEHOLDER: revisao clinica pendente'),
('rt.gastro',     140, 'ROUTINE_UBS', 'Vomito ou diarreia sem sinal de alarme.', 'PLACEHOLDER: revisao clinica pendente'),
('rt.skin',       150, 'ROUTINE_UBS', 'Manchas de pele sem sinal sistemico.', 'PLACEHOLDER: revisao clinica pendente'),
('rt.pain_other', 160, 'ROUTINE_UBS', 'Dor localizada sem sinal de alarme.', 'PLACEHOLDER: revisao clinica pendente');

INSERT INTO routing_rule_term (rule_id, group_no, token_id, negated) VALUES
-- cabeca + dor, DESDE QUE nao subito  (exercita o termo negado)
('rt.headache', 0, 'head',   0),
('rt.headache', 0, 'pain',   0),
('rt.headache', 0, 'sudden', 1),
('rt.fever',  0, 'fever',    0),
('rt.cough',  0, 'cough',    0),
('rt.wound',  0, 'cut',      0),
('rt.gastro', 0, 'vomit',    0),
('rt.gastro', 1, 'diarrhea', 0),
('rt.skin',   0, 'rash',     0),
('rt.pain_other', 0, 'pain', 0);
