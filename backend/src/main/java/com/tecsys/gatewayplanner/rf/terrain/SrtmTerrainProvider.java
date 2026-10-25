package com.tecsys.gatewayplanner.rf.terrain;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.logging.Logger;
import java.util.zip.GZIPInputStream;

import java.nio.ShortBuffer;

/**
 * Lê elevação de arquivos SRTM {@code .hgt} (1 arco-segundo ≈ 30 m, ou 3 ≈ 90 m)
 * guardados numa pasta. Cada arquivo cobre 1° x 1° e é nomeado pelo canto
 * sudoeste (ex.: {@code S24W047.hgt} cobre lat -24..-23, lon -47..-46).
 *
 * Se {@code autoDownload} estiver ligado e o arquivo não existir, tenta baixar
 * de {@code elevation-tiles-prod.s3.amazonaws.com/skadi} (cópia pública do SRTM,
 * sem login) e guardar na pasta. Falha de download vira "sem dado" (NaN), nunca
 * exceção — o cálculo de RF então cai para espaço livre naquele enlace e avisa.
 *
 * Os arquivos são mapeados em memória (não carregados no heap) e a leitura é
 * segura para uso em várias threads.
 */
public final class SrtmTerrainProvider implements TerrainProvider {

    private static final Logger LOG = Logger.getLogger(SrtmTerrainProvider.class.getName());
    private static final short VOID = -32768;
    private static final String SKADI = "https://elevation-tiles-prod.s3.amazonaws.com/skadi/";

    private record Tile(ShortBuffer data, int size) {
    }

    private final Path dir;
    private final boolean autoDownload;
    // Chave numérica (não String.format a cada consulta): a leitura de elevação roda milhões de vezes por estudo.
    private final ConcurrentHashMap<Integer, Optional<Tile>> tiles = new ConcurrentHashMap<>();

    public SrtmTerrainProvider(Path dir, boolean autoDownload) {
        this.dir = dir;
        this.autoDownload = autoDownload;
    }

    /** Nome do arquivo (sem extensão) do ladrilho que contém o ponto. */
    public static String tileName(double lat, double lon) {
        int la = (int) Math.floor(lat), lo = (int) Math.floor(lon);
        return String.format("%s%02d%s%03d", la >= 0 ? "N" : "S", Math.abs(la), lo >= 0 ? "E" : "W", Math.abs(lo));
    }

    @Override
    public double elevationM(double lat, double lon) {
        if (Double.isNaN(lat) || Double.isNaN(lon)) return Double.NaN;
        int tileLat = (int) Math.floor(lat), tileLon = (int) Math.floor(lon);
        int key = (tileLat + 90) * 360 + (tileLon + 180);
        Optional<Tile> cached = tiles.get(key);
        if (cached == null) cached = tiles.computeIfAbsent(key, k -> load(tileName(lat, lon)));
        Tile t = cached.orElse(null);
        if (t == null) return Double.NaN;

        int n = t.size();
        double r = (tileLat + 1 - lat) * (n - 1); // linha 0 = borda norte
        double c = (lon - tileLon) * (n - 1);
        int r0 = clamp((int) Math.floor(r), 0, n - 2), c0 = clamp((int) Math.floor(c), 0, n - 2);
        double fr = r - r0, fc = c - c0;

        double h00 = h(t, r0, c0), h01 = h(t, r0, c0 + 1), h10 = h(t, r0 + 1, c0), h11 = h(t, r0 + 1, c0 + 1);
        if (Double.isNaN(h00) || Double.isNaN(h01) || Double.isNaN(h10) || Double.isNaN(h11)) {
            // Pontos "vazios" do SRTM (água/sombra): usa a média dos válidos.
            double sum = 0;
            int cnt = 0;
            for (double v : new double[]{h00, h01, h10, h11}) {
                if (!Double.isNaN(v)) {
                    sum += v;
                    cnt++;
                }
            }
            return cnt == 0 ? Double.NaN : sum / cnt;
        }
        double top = h00 * (1 - fc) + h01 * fc;
        double bottom = h10 * (1 - fc) + h11 * fc;
        return top * (1 - fr) + bottom * fr;
    }

    @Override
    public double elevationFastM(double lat, double lon) {
        if (Double.isNaN(lat) || Double.isNaN(lon)) return Double.NaN;
        int tileLat = (int) Math.floor(lat), tileLon = (int) Math.floor(lon);
        int key = (tileLat + 90) * 360 + (tileLon + 180);
        Optional<Tile> cached = tiles.get(key);
        if (cached == null) cached = tiles.computeIfAbsent(key, k -> load(tileName(lat, lon)));
        Tile t = cached.orElse(null);
        if (t == null) return Double.NaN;
        int n = t.size();
        int r = clamp((int) Math.round((tileLat + 1 - lat) * (n - 1)), 0, n - 1);
        int c = clamp((int) Math.round((lon - tileLon) * (n - 1)), 0, n - 1);
        short v = t.data().get(r * n + c);
        return v == VOID ? elevationM(lat, lon) : v; // ponto vazio do SRTM: usa a média dos vizinhos
    }

    private static double h(Tile t, int row, int col) {
        short v = t.data().get(row * t.size() + col);
        return v == VOID ? Double.NaN : v;
    }

    private static int clamp(int v, int lo, int hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    private Optional<Tile> load(String name) {
        try {
            Path file = dir.resolve(name + ".hgt");
            if (!Files.exists(file) && autoDownload) download(name, file);
            if (!Files.exists(file)) {
                LOG.warning("Sem dado de relevo para o ladrilho " + name + " (esperado em " + file.toAbsolutePath() + ")");
                return Optional.empty();
            }
            long len = Files.size(file);
            int n = (int) Math.round(Math.sqrt(len / 2.0));
            if ((long) n * n * 2 != len || (n != 1201 && n != 3601)) {
                LOG.warning("Arquivo .hgt com tamanho inesperado (" + len + " bytes): " + file);
                return Optional.empty();
            }
            try (FileChannel ch = FileChannel.open(file, StandardOpenOption.READ)) {
                MappedByteBuffer buf = ch.map(FileChannel.MapMode.READ_ONLY, 0, len); // big-endian por padrão
                return Optional.of(new Tile(buf.asShortBuffer(), n));
            }
        } catch (IOException | RuntimeException e) {
            LOG.warning("Falha ao ler o ladrilho " + name + ": " + e);
            return Optional.empty();
        }
    }

    private void download(String name, Path target) {
        String url = SKADI + name.substring(0, 3) + "/" + name + ".hgt.gz";
        Path tmp = null;
        try {
            Files.createDirectories(dir);
            HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15))
                    .followRedirects(HttpClient.Redirect.NORMAL).build();
            HttpRequest req = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofMinutes(3)).GET().build();
            HttpResponse<InputStream> resp = client.send(req, HttpResponse.BodyHandlers.ofInputStream());
            if (resp.statusCode() != 200) {
                LOG.warning("Download de " + url + " retornou HTTP " + resp.statusCode());
                return;
            }
            tmp = Files.createTempFile(dir, name, ".part");
            try (InputStream in = new GZIPInputStream(resp.body()); OutputStream out = Files.newOutputStream(tmp)) {
                in.transferTo(out);
            }
            Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING);
            LOG.info("Ladrilho de relevo baixado: " + target);
        } catch (IOException | InterruptedException | RuntimeException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            LOG.warning("Não consegui baixar " + url + ": " + e);
            try {
                if (tmp != null) Files.deleteIfExists(tmp);
            } catch (IOException ignored) {
            }
        }
    }
}
