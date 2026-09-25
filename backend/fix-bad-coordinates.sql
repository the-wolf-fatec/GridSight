-- Acha qualquer ativo ou candidato com latitude/longitude fora da faixa
-- válida (lat: -90 a 90, lon: -180 a 180). É isso que está quebrando o
-- mapa (LatLngBounds.fromPoints não aceita coordenada inválida).

USE tecsys_gateway;

SELECT 'asset' AS tabela, id, name, latitude, longitude FROM asset
WHERE latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180;

SELECT 'candidate_site' AS tabela, id, name, latitude, longitude FROM candidate_site
WHERE latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180;

-- Depois de achar a linha, ou corrija a coordenada certa:
-- UPDATE asset SET latitude = -23.442424 WHERE id = 'ID_AQUI';
-- ou apague, se foi só um teste sem querer:
-- DELETE FROM asset WHERE id = 'ID_AQUI';
-- (troque "asset" por "candidate_site" se o problema estiver lá)
