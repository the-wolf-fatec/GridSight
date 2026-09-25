package com.tecsys.gatewayplanner.model;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Um ativo da rede elétrica (ponto a ser coberto), tipicamente importado
 * da BDGD. Corresponde 1:1 ao modelo `Asset` do app Flutter.
 */
@Entity
@Table(name = "asset", indexes = {
        @Index(name = "idx_asset_distribuidora", columnList = "distribuidora")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Asset {

    @Id
    private String id;

    private String name;

    private String type; // ex: Sensor de Corrente, Medidor Inteligente, Chave Telecomandada

    private Double latitude;

    private Double longitude;

    private String distribuidora;
}
