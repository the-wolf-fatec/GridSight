-- Dados de exemplo, espalhados em 5 núcleos geográficos (~3-4 km de
-- distância entre eles), para que o algoritmo de otimização precise
-- escolher vários gateways mesmo com o alcance padrão (2.5 km) — em vez
-- de um único gateway cobrir tudo, como acontecia com o seed anterior
-- (muito concentrado).
--
-- Rode isso DEPOIS que o Spring Boot já tiver subido ao menos uma vez
-- (para que o Hibernate já tenha criado as tabelas).
--
-- Se você já rodou o seed antigo antes, apague os dados anteriores primeiro
-- (descomente as linhas abaixo) para não duplicar/conflitar IDs:
-- DELETE FROM scenario_gateway;
-- DELETE FROM asset; DELETE FROM candidate_site; DELETE FROM scenario;

USE tecsys_gateway;

-- Núcleo A (noroeste)
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES
('AT-001', 'Sensor de Corrente #1',  'Sensor de Corrente',   -23.147994, -45.912000, 'EDP São Paulo'),
('AT-002', 'Medidor Inteligente #1', 'Medidor Inteligente',  -23.154300, -45.905140, 'EDP São Paulo'),
('AT-003', 'Chave Telecomandada #1', 'Chave Telecomandada',  -23.160606, -45.912000, 'EDP São Paulo'),
('AT-004', 'Religador #1',           'Religador',            -23.154300, -45.918860, 'EDP São Paulo');

-- Núcleo B (nordeste)
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES
('AT-005', 'Sensor de Corrente #2',  'Sensor de Corrente',   -23.147894, -45.862300, 'EDP São Paulo'),
('AT-006', 'Medidor Inteligente #2', 'Medidor Inteligente',  -23.154200, -45.855440, 'EDP São Paulo'),
('AT-007', 'Chave Telecomandada #2', 'Chave Telecomandada',  -23.160506, -45.862300, 'EDP São Paulo'),
('AT-008', 'Religador #2',           'Religador',            -23.154200, -45.869160, 'EDP São Paulo');

-- Núcleo C (sudoeste)
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES
('AT-009', 'Sensor de Corrente #3',  'Sensor de Corrente',   -23.197894, -45.912000, 'EDP São Paulo'),
('AT-010', 'Medidor Inteligente #3', 'Medidor Inteligente',  -23.204200, -45.905140, 'EDP São Paulo'),
('AT-011', 'Chave Telecomandada #3', 'Chave Telecomandada',  -23.210506, -45.912000, 'EDP São Paulo'),
('AT-012', 'Religador #3',           'Religador',            -23.204200, -45.918860, 'EDP São Paulo');

-- Núcleo D (sudeste)
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES
('AT-013', 'Sensor de Corrente #4',  'Sensor de Corrente',   -23.197894, -45.862200, 'EDP São Paulo'),
('AT-014', 'Medidor Inteligente #4', 'Medidor Inteligente',  -23.204200, -45.855340, 'EDP São Paulo'),
('AT-015', 'Chave Telecomandada #4', 'Chave Telecomandada',  -23.210506, -45.862200, 'EDP São Paulo'),
('AT-016', 'Religador #4',           'Religador',            -23.204200, -45.869060, 'EDP São Paulo');

-- Núcleo E (centro)
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES
('AT-017', 'Sensor de Corrente #5',  'Sensor de Corrente',   -23.172894, -45.887200, 'EDP São Paulo'),
('AT-018', 'Medidor Inteligente #5', 'Medidor Inteligente',  -23.179200, -45.880340, 'EDP São Paulo'),
('AT-019', 'Chave Telecomandada #5', 'Chave Telecomandada',  -23.185506, -45.887200, 'EDP São Paulo'),
('AT-020', 'Religador #5',           'Religador',            -23.179200, -45.894060, 'EDP São Paulo');

-- Locais candidatos: um poste central em cada núcleo, mais um segundo
-- candidato de apoio em alguns núcleos, para o algoritmo ter opção de escolha.
INSERT INTO candidate_site (id, name, type, latitude, longitude, distribuidora) VALUES
('CS-001', 'Poste 1',        'poste',       -23.1541, -45.9122, 'EDP São Paulo'), -- núcleo A
('CS-002', 'Poste 2',        'poste',       -23.1560, -45.9105, 'EDP São Paulo'), -- núcleo A (apoio)
('CS-003', 'Poste 3',        'poste',       -23.1541, -45.8622, 'EDP São Paulo'), -- núcleo B
('CS-004', 'Subestação 1',   'subestacao',  -23.1520, -45.8640, 'EDP São Paulo'), -- núcleo B (apoio)
('CS-005', 'Poste 4',        'poste',       -23.2041, -45.9122, 'EDP São Paulo'), -- núcleo C
('CS-006', 'Poste 5',        'poste',       -23.2060, -45.9105, 'EDP São Paulo'), -- núcleo C (apoio)
('CS-007', 'Subestação 2',   'subestacao',  -23.2041, -45.8622, 'EDP São Paulo'), -- núcleo D
('CS-008', 'Poste 6',        'poste',       -23.2020, -45.8640, 'EDP São Paulo'), -- núcleo D (apoio)
('CS-009', 'Subestação 3',   'subestacao',  -23.1791, -45.8872, 'EDP São Paulo'), -- núcleo E
('CS-010', 'Poste 7',        'poste',       -23.1810, -45.8855, 'EDP São Paulo'); -- núcleo E (apoio)
