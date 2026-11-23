package com.tecsys.gatewayplanner.rf.terrain;

import java.awt.geom.Path2D;

/** Forma usada para recortar um tile (em pixels, 256x256): só o que está dentro dela é desenhado. */
public interface TileClip {

    /** O recorte em coordenadas de pixel do tile (z, tx, ty) no Web Mercator. */
    Path2D tileShape(int z, int tx, int ty);
}
