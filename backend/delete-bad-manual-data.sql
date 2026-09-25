USE tecsys_gateway;

-- Apaga os locais candidatos de teste com coordenada inválida
DELETE FROM candidate_site WHERE id IN (
  'manual-19fef88a-99d4-45b3-8538-d0292f83f162', -- Poste Alto (lat 442424)
  'manual-680a6e54-9a47-4ca3-bd74-cd4c231271fd'  -- Poste Norte (lat 14141)
);

-- Apaga os ativos de teste com coordenada inválida
DELETE FROM asset WHERE id IN (
  'manual-3da89d4a-312f-4052-a930-b6defc16e894', -- Boa Chave
  'manual-4d143c54-b767-4fb1-958b-dbc7e2b87bf6', -- Chave Final
  'manual-532bdf19-ace7-45f8-95d6-15d98df25823', -- Carlos
  'manual-582d61f8-e8cb-4edd-895c-9ca0c54b4954'  -- Religador de Primeira
);

-- Confere que sumiram
SELECT 'asset' AS tabela, id, name, latitude, longitude FROM asset
WHERE latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180;
SELECT 'candidate_site' AS tabela, id, name, latitude, longitude FROM candidate_site
WHERE latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180;
