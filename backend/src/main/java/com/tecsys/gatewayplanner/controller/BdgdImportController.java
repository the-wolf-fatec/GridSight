package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.model.Asset;
import com.tecsys.gatewayplanner.service.AssetService;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Importa ativos reais da planilha UCAT_PJ.csv (ou UCMT_PJ.csv, mesmo
 * layout) da BDGD/ANEEL — Unidades Consumidoras de Pessoas Jurídicas.
 *
 * Fonte: https://dadosabertos.aneel.gov.br/dataset/base-de-dados-geografica-da-distribuidora-bdgd
 *
 * O CSV usa ';' como separador, e a coluna DIST é um CÓDIGO NUMÉRICO
 * interno da ANEEL (não o nome da distribuidora) — por isso [distribuidora]
 * é informado por você na hora de importar, não é lido automaticamente
 * do arquivo. [distCode], se enviado, filtra só as linhas daquele código.
 */
@RestController
@RequestMapping("/api/assets")
public class BdgdImportController {

    private final AssetService assetService;

    public BdgdImportController(AssetService assetService) {
        this.assetService = assetService;
    }

    @PostMapping("/import-bdgd")
    public Map<String, Object> importBdgd(
            @RequestParam("file") MultipartFile file,
            @RequestParam("distribuidora") String distribuidora,
            @RequestParam(value = "distCode", required = false) String distCode
    ) throws IOException {
        List<Asset> toSave = new ArrayList<>();
        int totalLidas = 0, semCoordenada = 0, inativas = 0, foraDoFiltro = 0;

        try (BufferedReader reader = new BufferedReader(new InputStreamReader(file.getInputStream(), StandardCharsets.UTF_8))) {
            String headerLine = reader.readLine();
            if (headerLine == null) {
                return Map.of("erro", "Arquivo vazio");
            }
            String[] headers = headerLine.split(";", -1);
            Map<String, Integer> col = new HashMap<>();
            for (int i = 0; i < headers.length; i++) col.put(headers[i].trim(), i);

            int iId = col.getOrDefault("COD_ID_ENCR", -1);
            int iDist = col.getOrDefault("DIST", -1);
            int iSit = col.getOrDefault("SIT_ATIV", -1);
            int iBrr = col.getOrDefault("BRR", -1);
            int iClasSub = col.getOrDefault("CLAS_SUB", -1);
            int iCep = col.getOrDefault("CEP", -1);
            int iX = col.getOrDefault("POINT_X", -1);
            int iY = col.getOrDefault("POINT_Y", -1);

            if (iX < 0 || iY < 0) {
                return Map.of("erro", "Colunas POINT_X/POINT_Y não encontradas — esse CSV é do layout esperado da BDGD?");
            }

            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank()) continue;
                totalLidas++;
                String[] f = line.split(";", -1);
                if (f.length <= Math.max(iX, iY)) continue;

                if (iSit >= 0 && !"AT".equals(f[iSit].trim())) {
                    inativas++;
                    continue;
                }
                if (distCode != null && !distCode.isBlank() && iDist >= 0 && !distCode.trim().equals(f[iDist].trim())) {
                    foraDoFiltro++;
                    continue;
                }

                String xStr = f[iX].trim();
                String yStr = f[iY].trim();
                if (xStr.isEmpty() || yStr.isEmpty()) {
                    semCoordenada++;
                    continue;
                }

                double lon, lat;
                try {
                    lon = Double.parseDouble(xStr);
                    lat = Double.parseDouble(yStr);
                } catch (NumberFormatException e) {
                    semCoordenada++;
                    continue;
                }
                if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
                    semCoordenada++;
                    continue;
                }

                String id = "bdgd-" + (iId >= 0 && f.length > iId ? f[iId].substring(0, Math.min(16, f[iId].length())) : java.util.UUID.randomUUID().toString());
                String bairro = (iBrr >= 0 && f.length > iBrr && !f[iBrr].isBlank()) ? f[iBrr] : "";
                String cep = (iCep >= 0 && f.length > iCep) ? f[iCep] : "";
                String tipo = (iClasSub >= 0 && f.length > iClasSub && !f[iClasSub].isBlank()) ? f[iClasSub] : "UC";
                String nome = "UC " + (bairro.isBlank() ? cep : bairro);

                Asset asset = new Asset();
                asset.setId(id);
                asset.setName(nome.isBlank() ? "Unidade Consumidora" : nome);
                asset.setType(tipo);
                asset.setLatitude(lat);
                asset.setLongitude(lon);
                asset.setDistribuidora(distribuidora);
                toSave.add(asset);
            }
        }

        for (Asset a : toSave) assetService.save(a);

        Map<String, Object> result = new HashMap<>();
        result.put("linhasLidas", totalLidas);
        result.put("importadas", toSave.size());
        result.put("descartadasInativas", inativas);
        result.put("descartadasSemCoordenada", semCoordenada);
        result.put("descartadasForaDoFiltroDist", foraDoFiltro);
        return result;
    }
}