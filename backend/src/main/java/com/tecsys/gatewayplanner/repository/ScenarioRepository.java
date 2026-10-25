package com.tecsys.gatewayplanner.repository;

import com.tecsys.gatewayplanner.model.Scenario;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ScenarioRepository extends JpaRepository<Scenario, String> {

    List<Scenario> findAllByOrderByExecutedAtDesc();
}
