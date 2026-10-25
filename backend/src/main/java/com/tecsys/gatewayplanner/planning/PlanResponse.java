package com.tecsys.gatewayplanner.planning;

import java.util.List;

/** Resultado do planejamento, já no formato que o app usa para desenhar o mapa. */
public record PlanResponse(
        boolean terrainUsed,
        /** Havia arquivos .hgt carregados? Se não, o "relevo" caiu para distância e o app avisa. */
        boolean terrainDataFound,
        List<String> chosenGatewayIds,
        int totalAssets,
        int coveredAssets,
        List<Link> links,
        /** Ativos sem sinal por causa do relevo: estão dentro do raio de um gateway (escolhido ou candidato), mas o terreno bloqueia o caminho. */
        List<String> lostToTerrainAssetIds,
        /** Quantos ativos o mesmo conjunto de gateways cobriria só por distância. */
        int coveredIgnoringTerrain,
        /** Ativos alcançados por 2 ou mais gateways (sobreposição de cobertura). */
        int overlappedAssets,
        /** Comparação: o que o planejamento SEM relevo escolheria. */
        Comparison withoutTerrain,
        /** Área estimada de cobertura de cada gateway escolhido (polígono lat/lon). */
        List<Footprint> footprints,
        List<String> warnings,
        long elapsedMs,
        /** Para cada ativo sem sinal por causa do relevo: altitude do local e o morro que bloqueia. */
        List<LostAsset> lostDetails) {

    /**
     * @param gatewayId   gateway de referência (o mais próximo ao alcance)
     * @param elevationM  altitude do local do ativo (m)
     * @param blocker     morro que mais passa acima da visada até o ativo; null se o terreno não mostra bloqueio claro
     */
    public record LostAsset(String assetId, double elevationM, String gatewayId, Obstacle blocker) {
    }

    /** Ponto alto sugerido para um gateway novo: quantos ativos hoje sem sinal ele recuperaria. */
    public record PeakSuggestion(String id, String group, double lat, double lon, double elevationM, int newlyCovered) {
    }

    /** Um ativo atendido por um gateway (o de melhor sinal). */
    public record Link(String assetId, String gatewayId, double distanceKm, double rxDbm) {
    }

    /**
     * Planejamento ignorando relevo: quantos gateways escolheria e o que acontece
     * com ESSES gateways quando o relevo é considerado.
     */
    public record Comparison(int gateways, int coveredByDistance, int coveredWithTerrain) {
    }

    /**
     * @param shadows pedaços do círculo de alcance onde NENHUM gateway escolhido chega por causa do relevo;
     *                cada um é um quadrilátero [lat,lon] x4 (podem ficar no meio do alcance, atrás de uma serra)
     */
    public record Footprint(String gatewayId, List<double[]> points, List<Obstacle> obstacles, List<List<double[]>> shadows) {
    }

    /**
     * Ponto do relevo que impede o sinal numa direção: altitude em metros acima do nível do mar,
     * quanto ele passa acima da linha de visada e a distância até o gateway.
     */
    public record Obstacle(double lat, double lon, double elevationM, double aboveLineOfSightM, double distanceKm) {
    }
}
