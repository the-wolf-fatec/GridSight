# GridSight — Backend

Backend em Spring Boot (monolito), Hibernate/JPA e MySQL, para o desafio
Tecsys — Planejamento de Cobertura de Radiofrequência.

Este backend serve os dados que o app Flutter (`tecsys_gateway_planner`)
consome através de `lib/services/api_data_repository.dart`.

## Pré-requisitos

- Java 17+
- Maven (ou use o wrapper `./mvnw`, se preferir gerar um com `mvn wrap`)
- MySQL 8+ rodando localmente (ou acessível pela rede)

## Configuração

1. Abra `src/main/resources/application.properties` e ajuste:
   ```properties
   spring.datasource.username=root
   spring.datasource.password=SUA_SENHA_AQUI
   ```
2. Não é necessário criar o banco manualmente — a URL de conexão já usa
   `createDatabaseIfNotExist=true`, então o banco `tecsys_gateway` é criado
   sozinho na primeira conexão. Se preferir criar à mão:
   ```sql
   CREATE DATABASE tecsys_gateway;
   ```

## Rodando

```bash
mvn spring-boot:run
```

Na primeira execução, o Hibernate cria automaticamente as 4 tabelas
(`asset`, `candidate_site`, `scenario`, `scenario_gateway`) a partir das
classes em `model/`. Você não precisa escrever nenhum `CREATE TABLE`.

O servidor sobe em `http://localhost:8080`.

## Populando com dados de exemplo (opcional)

Depois que o backend tiver subido ao menos uma vez (tabelas já criadas),
rode:

```bash
mysql -u root -p tecsys_gateway < seed-data.sql
```

## Endpoints disponíveis

| Método | Endpoint | Descrição |
|---|---|---|
| GET | `/api/distribuidoras` | Lista as distribuidoras disponíveis |
| GET | `/api/assets?distribuidora=X` | Ativos daquela distribuidora |
| POST | `/api/assets` | Cria um ativo manualmente |
| GET | `/api/assets/manual` | Só os ativos criados manualmente (restauração pós-F5) |
| GET | `/api/candidate-sites?distribuidora=X` | Locais candidatos daquela distribuidora |
| POST | `/api/candidate-sites` | Cria um local candidato manualmente |
| GET | `/api/candidate-sites/manual` | Só os locais candidatos criados manualmente |
| GET | `/api/scenarios` | Histórico de cenários (mais recente primeiro) |
| POST | `/api/scenarios` | Salva um cenário calculado no Flutter |
| DELETE | `/api/scenarios/{id}` | Remove um cenário do histórico |
| DELETE | `/api/scenarios` | Apaga todo o histórico de cenários |
| GET | `/api/tiles/{z}/{x}/{y}.png` | Proxy dos tiles do OpenStreetMap (ver abaixo) |

### Exemplo de corpo para `POST /api/scenarios`

```json
{
  "label": "Cenário 1",
  "distribuidora": "EDP São Paulo",
  "rangeKm": 2.5,
  "transmissionPower": 20,
  "minCoverageTarget": 0.95,
  "maxGateways": 12,
  "totalAssets": 30,
  "coveredAssets": 26,
  "processingTimeMs": 12,
  "chosenGatewayIds": ["CS-001", "CS-003"]
}
```
Os IDs em `chosenGatewayIds` precisam já existir na tabela `candidate_site`
(ou seja, terem vindo de uma resposta anterior de `GET /api/candidate-sites`).

## Conectando o Flutter a este backend

Em `lib/main.dart` do app Flutter, troque:
```dart
final DataRepository repository = MockDataRepository();
```
por:
```dart
final DataRepository repository = ApiDataRepository(baseUrl: 'http://localhost:8080/api');
```

Se for testar em um emulador Android, troque `localhost` por `10.0.2.2`
(o alias padrão do emulador para a máquina host).

## Proxy de tiles do OpenStreetMap

O tile server oficial do OSM bloqueia (403) requisições com User-Agent
genérico, e no Flutter Web o navegador nunca deixa o app sobrescrever
esse header de verdade. O `TileProxyController` resolve isso: o Flutter
pede os tiles pro próprio backend, que repassa a chamada pro OSM com um
User-Agent identificado. Configure seu contato real em
`TileProxyController.USER_AGENT` antes de publicar o projeto.

## Estrutura do projeto

```
src/main/java/com/tecsys/gatewayplanner/
├── GatewayPlannerApplication.java   → classe principal
├── config/CorsConfig.java           → libera o Flutter chamar a API
├── model/                           → entidades JPA (Hibernate cria as tabelas)
│   ├── Asset.java
│   ├── CandidateSite.java
│   └── Scenario.java
├── repository/                      → interfaces JpaRepository (CRUD pronto)
├── dto/                             → formato de entrada/saída da API de Scenario
├── service/                         → regra de negócio
└── controller/                      → endpoints REST
```

## Sobre o `ddl-auto=update`

Em desenvolvimento, `update` deixa o Hibernate criar/ajustar as tabelas
automaticamente sempre que você mudar uma classe `@Entity`, sem apagar
dados existentes. **Não é recomendado em produção** — lá, o ideal é usar
`validate` (o Hibernate só confere se o schema bate, sem alterar nada) e
controlar mudanças de schema com uma ferramenta de migração versionada,
como Flyway ou Liquibase.
