package com.tecsys.gatewayplanner.planning;

import java.util.ArrayList;
import java.util.List;

/**
 * Pedido de planejamento enviado pelo app (POST /api/planning/run).
 *
 * Só os parâmetros principais: alcance máximo, potência, meta de cobertura e
 * limite de gateways. Frequência (915 MHz), sensibilidade (-120 dBm) e alturas
 * (gateway 6 m, dispositivo 5 m) são as referências do cliente e ficam fixas
 * no servidor (ver {@link PlanningEngine}).
 *
 * Campos públicos de propósito: o Jackson lê direto, sem Lombok.
 */
public class PlanRequest {

    /** Alcance máximo (teto de distância) entre gateway e ativo, em km. */
    public double rangeKm = 2.5;
    /** Potência de transmissão, em dBm. */
    public double txPowerDbm = 20;
    /** Meta de cobertura, 0..1. */
    public double minCoverageTarget = 1.0;
    /** Limite de gateways (por grupo/distribuidora). */
    public int maxGateways = 12;
    /** Margem de segurança do enlace em dB; null = usa o padrão do servidor (0). */
    public Double fadeMarginDb;
    /** Altura da antena do gateway sobre o chão, em metros (padrão 6). */
    public double gatewayHeightM = 6;
    /** true = considera o relevo (SRTM); false = só distância. */
    public boolean useTerrain = true;
    /** Um grupo por distribuidora: cada uma só usa os próprios locais candidatos. */
    public List<Group> groups = new ArrayList<>();

    public static class Group {
        public String name;
        public List<Site> assets = new ArrayList<>();
        public List<Site> candidates = new ArrayList<>();
        /**
         * Se vier preenchido, NÃO otimiza: só avalia (cobertura, relevo) estes
         * gateways escolhidos à mão no mapa.
         */
        public List<String> manualGatewayIds;
    }

    public static class Site {
        public String id;
        public String name;
        public String type;
        public double lat;
        public double lon;
    }
}
