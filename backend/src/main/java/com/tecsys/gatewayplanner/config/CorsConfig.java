package com.tecsys.gatewayplanner.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Libera o backend para ser chamado pelo app Flutter (web, desktop ou
 * emulador), que roda em uma origem diferente do servidor Spring Boot.
 * Sem isso, o navegador (no caso do Flutter Web) bloqueia as requisições
 * por política de CORS, mesmo com o backend respondendo normalmente.
 */
@Configuration
public class CorsConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns("*") // em produção, restrinja para o domínio real do front
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*");
    }

    // Alternativa via Bean, caso prefira (mantida comentada como referência):
    // @Bean
    // public CorsFilter corsFilter() {
    //     CorsConfiguration config = new CorsConfiguration();
    //     config.setAllowedOriginPatterns(List.of("*"));
    //     config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    //     config.setAllowedHeaders(List.of("*"));
    //     UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    //     source.registerCorsConfiguration("/api/**", config);
    //     return new CorsFilter(source);
    // }
}
