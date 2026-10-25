# GridSight — Frontend

App Flutter (Dart) para o desafio Tecsys — Planejamento Otimizado de
Cobertura de Radiofrequência para Redes de Sensores em Sistemas de
Distribuição de Energia.

Layout responsivo: celular, tablet e desktop/web, com navegação que se
adapta à largura da tela.

## Como rodar

```bash
flutter pub get
flutter run -d chrome      # web
flutter run -d windows     # desktop (ou -d macos / -d linux)
flutter run                # Android/iOS com emulador ou dispositivo conectado
```

Requer Flutter SDK >= 3.3. Login: usuário `admin`, senha `gridsight123`.

Por padrão o app fala com o backend Spring Boot (`useBackend = true` em
`lib/main.dart`, apontando pra `http://localhost:8080/api`). Troque para
`false` pra rodar 100% offline com dados simulados (útil sem o backend
de pé, ex.: numa apresentação).

## Responsividade

- **< 640px (celular):** AppBar + `NavigationBar` inferior com as seções principais.
- **640–1100px (tablet):** `NavigationRail` recolhido, só ícones.
- **> 1100px (desktop):** `NavigationRail` estendido, ícone + texto.

## Estrutura de pastas

```
lib/
  main.dart                 -> ponto de entrada, injeta o repositório de dados e o AppState
  theme/app_theme.dart      -> cores e tema Material 3
  models/                   -> Asset, CandidateSite, CoverageParams, ScenarioResult
  services/
    data_repository.dart         -> contrato (interface) de acesso a dados
    mock_data_repository.dart    -> implementação simulada (offline)
    api_data_repository.dart     -> implementação real (HTTP -> Spring Boot)
    scenario_api_service.dart    -> histórico de cenários (HTTP -> Spring Boot)
    optimization_service.dart    -> algoritmo guloso de cobertura máxima
    geo_utils.dart                -> distância geográfica (Haversine)
  state/app_state.dart      -> estado global da aplicação (Provider)
  screens/                  -> uma tela por funcionalidade (login, painel, importação,
                                parâmetros, mapa, indicadores, comparar cenários)
  widgets/                  -> componentes reutilizáveis (KPI card, modais de criação manual)
```

## Algoritmo de otimização

Heurística gulosa de **cobertura máxima** (*maximum coverage greedy*): a
cada passo escolhe o local candidato que cobre o maior número de ativos
ainda não cobertos dentro do alcance configurado, até atingir a meta de
cobertura ou o limite máximo de gateways. Evita testar todas as
combinações possíveis, atendendo ao requisito de eficiência com grandes
volumes de dados geográficos.

## Funcionalidades

- Login (credenciais fixas, tela de entrada)
- Importação de dados da BDGD por distribuidora
- Criação manual de ativos e locais candidatos (além da importação)
- Parametrização dos critérios de cobertura de radiofrequência
- Execução do algoritmo de otimização
- Marcação manual de gateway direto no mapa (sem depender só do algoritmo)
- Visualização geográfica (mapa) de ativos, candidatos, gateways e área de cobertura
- Indicadores de qualidade (% de cobertura, nº de gateways, gráficos)
- Comparação entre cenários, com exclusão individual ou em massa
- Suporte a múltiplas distribuidoras/áreas geográficas
