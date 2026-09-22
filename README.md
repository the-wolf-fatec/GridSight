# GridSight

Planejamento Otimizado de Cobertura de Radiofrequência para Redes de
Sensores em Sistemas de Distribuição de Energia — Desafio Tecsys.

**Participante:** Carlos José Diniz Intrieri
**Curso:** Desenvolvimento de Software Multiplataforma — 5º DSM
**Parceiro:** Tecsys

## O desafio

Empresas de energia elétrica espalham sensores pela rede de distribuição
para monitorar equipamentos e identificar problemas. Esses sensores
"conversam" com a empresa por radiofrequência, através de gateways
instalados em pontos estratégicos (postes, subestações) capazes de
"ouvir" os sensores próximos.

O problema é de otimização espacial: dado um conjunto de ativos a cobrir
e um conjunto de locais candidatos à instalação de gateway, escolher o
melhor subconjunto de candidatos para maximizar a cobertura com o menor
número de gateways possível — sem testar força bruta todas as
combinações, já que o volume de dados geográficos (BDGD) pode ser grande.

## Backlog

| Nº | User Story | Prioridade | Dificuldade | Pontos |
|---|---|---|---|---|
| 1 | Como Planejador, desejo importar os dados geográficos da BDGD para carregar os ativos da rede elétrica no sistema | Alta | Alta | 8 |
| 2 | Como Planejador, desejo visualizar os ativos (pontos a cobrir) em um mapa para entender a área que precisa de cobertura | Alta | Média | 5 |
| 3 | Como Planejador, desejo cadastrar/importar os locais candidatos à instalação de gateways (postes, subestações, etc.) | Alta | Média | 5 |
| 4 | Como Planejador, desejo configurar os parâmetros técnicos de cobertura de radiofrequência para caracterizar o cenário de comunicação | Alta | Média | 5 |
| 5 | Como Planejador, desejo executar o algoritmo de otimização de posicionamento de gateways para obter uma configuração eficiente de cobertura | Alta | Muito Alta | 13 |
| 6 | Como Planejador, desejo visualizar no mapa a cobertura obtida (gateways escolhidos e área coberta) para avaliar o resultado | Alta | Alta | 8 |
| 7 | Como Planejador, desejo visualizar indicadores de qualidade do resultado (% de cobertura, nº de gateways) para avaliar a eficiência da solução | Média | Média | 5 |
| 8 | Como Planejador, desejo comparar diferentes cenários de planejamento (parâmetros distintos) para escolher a melhor configuração | Média | Alta | 8 |
| 9 | Como Planejador, desejo utilizar dados de diferentes áreas geográficas ou distribuidoras para não ficar restrito a uma única base de dados | Média | Média | 5 |
| 10 | Como Planejador, desejo consultar o manual de instalação e o manual do usuário para saber como configurar e operar o sistema | Baixa | Baixa | 2 |

**Total: 64 pontos**

### Cobertura do backlog neste projeto

| US | Onde está implementada |
|---|---|
| 1 | Importação de Dados (busca por distribuidora, MySQL via backend) |
| 2 | Aba Mapa — marcadores de ativos |
| 3 | Aba Importação (+ criação manual de candidato) |
| 4 | Aba Parâmetros — alcance, potência, meta, máx. de gateways |
| 5 | `OptimizationService` — heurística gulosa de cobertura máxima |
| 6 | Aba Mapa — gateways escolhidos, área de cobertura, toggle manual |
| 7 | Aba Indicadores — KPIs + gráficos (rosca e barras) |
| 8 | Aba Comparar Cenários — histórico + gráfico de barras comparativo |
| 9 | Seletor de distribuidora, dados isolados por distribuidora |
| 10 | Este README (manual de instalação e do usuário, abaixo) |

## Estrutura do repositório

```
tecsys-gateway-project/
├── frontend/   → App Flutter (Dart) — interface do Planejador
└── backend/    → API Spring Boot + Hibernate + MySQL
```

## Manual de instalação

1. **Backend**
   - Ajuste a senha do MySQL em `backend/src/main/resources/application.properties`
   - `cd backend && mvn spring-boot:run` (o Hibernate cria as tabelas sozinho)
   - (Opcional) dados de exemplo: `mysql -u root -p tecsys_gateway < backend/seed-data.sql`
2. **Frontend**
   - `cd frontend && flutter pub get`
   - `flutter run -d chrome` (ou windows/macos/linux/android/ios)
   - `frontend/lib/main.dart` já está com `useBackend = true`, apontando pra `http://localhost:8080/api`

Veja `backend/README.md` e `frontend/README.md` para detalhes (endpoints, estrutura de pastas, etc.).

## Manual do usuário

1. **Login** — usuário `admin`, senha `gridsight123` (credenciais fixas, sem cadastro de usuário).
2. **Painel** — visão geral com KPIs; permite criar ativo/candidato manualmente.
3. **Importação de Dados** — escolha a distribuidora e clique em "Importar dados".
4. **Parâmetros** — ajuste alcance, potência, meta de cobertura e máximo de gateways.
5. **Mapa** — clique em "Executar otimização" para calcular os gateways, ou toque num local candidato pra marcá-lo/desmarcá-lo como gateway manualmente.
6. **Indicadores** — % de cobertura, gateways usados, tempo de processamento.
7. **Comparar Cenários** — histórico de execuções, com gráfico comparativo e opção de apagar um ou todos.

## Como as duas partes se conectam

```
MySQL  ←──JDBC──→  Spring Boot (backend/)  ←──HTTP/JSON──→  Flutter (frontend/)
```

O Mapa também usa o backend como proxy dos tiles do OpenStreetMap
(`TileProxyController`), pra contornar o bloqueio de User-Agent do OSM no
Flutter Web.

## Alternando entre modo online e offline

Em `frontend/lib/main.dart`:
```dart
const bool useBackend = true;  // false = roda 100% offline com dados simulados
```
"# GridSight" 
