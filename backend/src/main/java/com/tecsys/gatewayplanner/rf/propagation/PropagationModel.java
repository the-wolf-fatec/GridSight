package com.tecsys.gatewayplanner.rf.propagation;

import com.tecsys.gatewayplanner.rf.RadioParams;

/**
 * Modelo de propagação. Trocar a implementação (ex.: Longley-Rice/ITM, usado
 * pelo Radio Mobile) não exige mexer no resto do motor.
 */
public interface PropagationModel {

    /** Perda de propagação entre o gateway (tx) e o dispositivo (rx). */
    LinkResult evaluate(double txLat, double txLon, double rxLat, double rxLon, RadioParams params);
}
