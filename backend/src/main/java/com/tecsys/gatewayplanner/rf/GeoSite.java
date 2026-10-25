package com.tecsys.gatewayplanner.rf;

/** Ponto georreferenciado usado pelo motor de RF (ativo a cobrir ou local candidato). */
public record GeoSite(String id, String name, String type, double lat, double lon) {
}
