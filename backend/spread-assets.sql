-- Espalha os 20 ativos do seed original (AT-001 a AT-020) mais afastados
-- uns dos outros dentro de cada núcleo (de ~150-300m para ~700m do centro
-- do núcleo, em formato de cruz N/L/S/O), pra ficarem visualmente
-- distinguíveis no mapa em vez de amontoados.
--
-- Só faz UPDATE por id — não toca nos ativos criados manualmente pelo
-- modal (id começando em 'manual-') nem no histórico de cenários.
--
-- Os núcleos continuam a ~5-6 km um do outro, então esse espalhamento não
-- risca de misturar um núcleo com o vizinho, e o alcance padrão de 2,5 km
-- ainda cobre um núcleo inteiro com 1-2 gateways.

USE tecsys_gateway;

-- Núcleo A (noroeste)
UPDATE asset SET latitude = -23.147994, longitude = -45.912000 WHERE id = 'AT-001';
UPDATE asset SET latitude = -23.154300, longitude = -45.905140 WHERE id = 'AT-002';
UPDATE asset SET latitude = -23.160606, longitude = -45.912000 WHERE id = 'AT-003';
UPDATE asset SET latitude = -23.154300, longitude = -45.918860 WHERE id = 'AT-004';

-- Núcleo B (nordeste)
UPDATE asset SET latitude = -23.147894, longitude = -45.862300 WHERE id = 'AT-005';
UPDATE asset SET latitude = -23.154200, longitude = -45.855440 WHERE id = 'AT-006';
UPDATE asset SET latitude = -23.160506, longitude = -45.862300 WHERE id = 'AT-007';
UPDATE asset SET latitude = -23.154200, longitude = -45.869160 WHERE id = 'AT-008';

-- Núcleo C (sudoeste)
UPDATE asset SET latitude = -23.197894, longitude = -45.912000 WHERE id = 'AT-009';
UPDATE asset SET latitude = -23.204200, longitude = -45.905140 WHERE id = 'AT-010';
UPDATE asset SET latitude = -23.210506, longitude = -45.912000 WHERE id = 'AT-011';
UPDATE asset SET latitude = -23.204200, longitude = -45.918860 WHERE id = 'AT-012';

-- Núcleo D (sudeste)
UPDATE asset SET latitude = -23.197894, longitude = -45.862200 WHERE id = 'AT-013';
UPDATE asset SET latitude = -23.204200, longitude = -45.855340 WHERE id = 'AT-014';
UPDATE asset SET latitude = -23.210506, longitude = -45.862200 WHERE id = 'AT-015';
UPDATE asset SET latitude = -23.204200, longitude = -45.869060 WHERE id = 'AT-016';

-- Núcleo E (centro)
UPDATE asset SET latitude = -23.172894, longitude = -45.887200 WHERE id = 'AT-017';
UPDATE asset SET latitude = -23.179200, longitude = -45.880340 WHERE id = 'AT-018';
UPDATE asset SET latitude = -23.185506, longitude = -45.887200 WHERE id = 'AT-019';
UPDATE asset SET latitude = -23.179200, longitude = -45.894060 WHERE id = 'AT-020';
