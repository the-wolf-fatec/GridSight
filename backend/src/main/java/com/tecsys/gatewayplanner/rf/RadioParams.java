package com.tecsys.gatewayplanner.rf;

/**
 * Parâmetros de rádio de um estudo de cobertura.
 *
 * Os valores padrão são as referências passadas pelo cliente (915 MHz, 21 dBm,
 * -120 dBm de sensibilidade, gateway a 6 m e dispositivo a 5 m). Não são
 * obrigatórios: o usuário pode mudar qualquer um deles por cenário.
 *
 * Campos públicos de propósito: o Jackson (Spring) lê e escreve direto, e o
 * motor de RF continua sem depender do Spring.
 */
public class RadioParams {

    /** Frequência em MHz. */
    public double frequencyMhz = 915;
    /** Potência de transmissão do dispositivo/gateway, em dBm. */
    public double txPowerDbm = 21;
    /** Sensibilidade do receptor, em dBm (número negativo). */
    public double rxSensitivityDbm = -120;
    /** Ganho da antena do gateway, em dBi. */
    public double gatewayAntennaGainDbi = 0;
    /** Ganho da antena do dispositivo, em dBi. */
    public double deviceAntennaGainDbi = 0;
    /** Perdas do sistema (cabos, conectores, caixa...), em dB. */
    public double systemLossDb = 0;
    /** Margem de desvanecimento/clutter (árvores, prédios que o relevo não mostra), em dB. */
    public double fadeMarginDb = 0;
    /** Altura da antena do gateway sobre o solo, em metros. */
    public double gatewayHeightM = 6;
    /** Altura da antena do dispositivo sobre o solo, em metros. */
    public double deviceHeightM = 5;
    /**
     * Distância máxima analisada por enlace, em km. Serve para limitar o
     * cálculo (sem isso seriam todos os pares). Em espaço livre o orçamento
     * de enlace de 141 dB chegaria a centenas de km, então este teto é o que
     * mantém o estudo realista e rápido.
     */
    public double maxRangeKm = 10;
    /** true = considera o perfil do terreno; false = só distância (espaço livre). */
    public boolean useTerrain = true;

    /** Perda de propagação máxima tolerada (dB) para o enlace ainda fechar. */
    public double linkBudgetDb() {
        return txPowerDbm + gatewayAntennaGainDbi + deviceAntennaGainDbi
                - systemLossDb - fadeMarginDb - rxSensitivityDbm;
    }

    /** Potência recebida (dBm) para uma dada perda de propagação. */
    public double rxPowerDbm(double pathLossDb) {
        return txPowerDbm + gatewayAntennaGainDbi + deviceAntennaGainDbi - systemLossDb - pathLossDb;
    }

    /** Lança IllegalArgumentException se algum valor não faz sentido. */
    public void validate() {
        if (!(frequencyMhz >= 30 && frequencyMhz <= 6000))
            throw new IllegalArgumentException("Frequência fora de 30–6000 MHz: " + frequencyMhz);
        if (!(rxSensitivityDbm < 0))
            throw new IllegalArgumentException("A sensibilidade deve ser negativa (dBm), ex.: -120.");
        if (!(gatewayHeightM >= 0 && deviceHeightM >= 0))
            throw new IllegalArgumentException("Alturas de antena não podem ser negativas.");
        if (!(maxRangeKm > 0 && maxRangeKm <= 100))
            throw new IllegalArgumentException("Alcance máximo analisado deve estar entre 0 e 100 km.");
        if (systemLossDb < 0 || fadeMarginDb < 0)
            throw new IllegalArgumentException("Perdas e margem não podem ser negativas.");
    }

    public RadioParams copy() {
        RadioParams c = new RadioParams();
        c.frequencyMhz = frequencyMhz;
        c.txPowerDbm = txPowerDbm;
        c.rxSensitivityDbm = rxSensitivityDbm;
        c.gatewayAntennaGainDbi = gatewayAntennaGainDbi;
        c.deviceAntennaGainDbi = deviceAntennaGainDbi;
        c.systemLossDb = systemLossDb;
        c.fadeMarginDb = fadeMarginDb;
        c.gatewayHeightM = gatewayHeightM;
        c.deviceHeightM = deviceHeightM;
        c.maxRangeKm = maxRangeKm;
        c.useTerrain = useTerrain;
        return c;
    }
}
