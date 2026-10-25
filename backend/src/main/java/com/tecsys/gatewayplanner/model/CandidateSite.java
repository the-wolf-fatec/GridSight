package com.tecsys.gatewayplanner.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Um local candidato à instalação de um gateway (poste, subestação, etc.).
 * Corresponde 1:1 ao modelo `CandidateSite` do app Flutter — exceto pelo
 * campo `distribuidora`, que existe aqui só para permitir o filtro no
 * banco. Fica de fora do JSON de resposta (GET), mas ainda é aceito na
 * entrada (POST) — por isso WRITE_ONLY, e não @JsonIgnore (que bloquearia
 * os dois sentidos e faria o POST sempre salvar distribuidora nula).
 */
@Entity
@Table(name = "candidate_site", indexes = {
        @Index(name = "idx_candidate_distribuidora", columnList = "distribuidora")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class CandidateSite {

    @Id
    private String id;

    private String name;

    private String type; // ex: poste, subestacao

    private Double latitude;

    private Double longitude;

    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    private String distribuidora;
}
