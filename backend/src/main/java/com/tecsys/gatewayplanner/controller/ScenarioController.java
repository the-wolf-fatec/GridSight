package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.dto.ScenarioRequest;
import com.tecsys.gatewayplanner.dto.ScenarioResponse;
import com.tecsys.gatewayplanner.service.ScenarioService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/scenarios")
public class ScenarioController {

    private final ScenarioService scenarioService;

    public ScenarioController(ScenarioService scenarioService) {
        this.scenarioService = scenarioService;
    }

    // GET /api/scenarios -> histórico completo, mais recente primeiro
    @GetMapping
    public List<ScenarioResponse> list() {
        return scenarioService.findAll();
    }

    // POST /api/scenarios -> salva um cenário calculado no Flutter
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ScenarioResponse create(@Valid @RequestBody ScenarioRequest request) {
        return scenarioService.save(request);
    }

    // DELETE /api/scenarios/{id} -> usado pelo botão de lixeira em Comparar Cenários
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) {
        scenarioService.delete(id);
    }

    // DELETE /api/scenarios -> apaga TODO o histórico. Usado pelo botão
    // "Apagar tudo" em Comparar Cenários.
    @DeleteMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteAll() {
        scenarioService.deleteAll();
    }
}
