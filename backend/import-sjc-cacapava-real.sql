-- Ativos reais da BDGD/ANEEL (UCAT_PJ.csv), filtrados pra São José dos
-- Campos e Caçapava (MUN 3549904 / 3508504), só unidades ativas (SIT_ATIV=AT)
-- com coordenada válida. Fonte: dadosabertos.aneel.gov.br, código DIST=391.
USE tecsys_gateway;

INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-001', 'Santana (São José dos Campos)', 'IN', -23.16818987, -45.90621769, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-002', 'Coqueiro (São José dos Campos)', 'CO1', -23.16197368, -45.78600074, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-003', 'Vila Das Acacias (São José dos Campos)', 'PP1', -23.21038956, -45.86232598, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-004', 'Limoeiro (São José dos Campos)', 'IN', -23.16294736, -45.82471843, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-005', 'Vila Galvao (Caçapava)', 'IN', -23.13123333, -45.7461445, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-006', 'Limoeiro (São José dos Campos)', 'IN', -23.23724303, -45.9270055, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-007', 'Vila Santos (Caçapava)', 'IN', -23.09982759, -45.69108624, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-008', 'Jardim Das Industrias (São José dos Campos)', 'CO1', -23.24599286, -45.91870119, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-009', 'Vila Galvao (Caçapava)', 'IN', -23.11294905, -45.71833923, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-010', 'Jardim Motorama (São José dos Campos)', 'IN', -23.18735107, -45.82028074, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-011', 'Vila Das Acacias (São José dos Campos)', 'PP1', -23.21038956, -45.86232598, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-012', 'Eugenio De Melo (São José dos Campos)', 'CO1', -23.14826156, -45.7858512, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-013', 'Limoeiro (São José dos Campos)', 'IN', -23.23945057, -45.93542703, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-014', 'Santana (São José dos Campos)', 'IN', -23.16818987, -45.90621769, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-015', 'Vila Dirce (São José dos Campos)', 'IN', -23.17197981, -45.91678079, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-016', 'Vila Galvao (Caçapava)', 'IN', -23.13123333, -45.7461445, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-017', 'Parque Martim Cerere (São José dos Campos)', 'IN', -23.22336806, -45.85405405, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-018', 'Jardim Satelite (São José dos Campos)', 'CO1', -23.2162918, -45.89485858, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-019', 'Vila Galvao (Caçapava)', 'IN', -23.11294905, -45.71833923, 'EDP São Paulo');
INSERT INTO asset (id, name, type, latitude, longitude, distribuidora) VALUES ('bdgd-sjc-020', 'Eugenio De Melo (São José dos Campos)', 'IN', -23.1366537, -45.7588448, 'EDP São Paulo');

-- Total inserido: 20 ativos reais







