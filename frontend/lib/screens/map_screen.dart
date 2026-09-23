import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../services/optimization_service.dart';
import '../widgets/section_title.dart';

// Chave grátis do CartoDB (carto.com/basemaps/apikey), opcional.
const String? cartoApiKey = null;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.active = true});
  final bool active; // true quando esta é a aba selecionada no momento

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool showAssets = true, showCandidates = true, showGateways = true, showCoverage = true;
  final _map = MapController();
  final _opt = OptimizationService();
  String? _lastFitKey;

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recentraliza sempre que o usuário troca PRA essa aba — sem isso, a
    // câmera podia ficar presa numa posição antiga (às vezes fora da área
    // dos dados) se o mapa já tivesse sido montado antes em segundo plano.
    if (widget.active && !oldWidget.active) {
      final app = context.read<AppState>();
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitNow(app));
    }
  }

  void _fitIfNeeded(AppState app) {
    if (app.assets.isEmpty && app.candidateSites.isEmpty) return;
    final key = '${app.selectedDistribuidora}|${app.assets.length}|${app.candidateSites.length}';
    if (_lastFitKey == key) return;
    _lastFitKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitNow(app));
  }

  void _fitNow(AppState app) {
    bool valid(double lat, double lon) => lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
    final pts = [
      for (final a in app.assets) if (valid(a.latitude, a.longitude)) LatLng(a.latitude, a.longitude),
      for (final c in app.candidateSites) if (valid(c.latitude, c.longitude)) LatLng(c.latitude, c.longitude),
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.first, 13);
      return;
    }
    _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(56)));
  }

  // Tile server oficial do OSM bloqueia (403) User-Agent genérico no Flutter
  // Web. Com backend, pedimos pra ele (proxy com User-Agent real); sem, cai pro CartoDB.
  String _tileUrl(AppState app) {
    if (app.backendBaseUrl != null) return '${app.backendBaseUrl}/tiles/{z}/{x}/{y}.png';
    final k = cartoApiKey;
    return 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png${k != null ? '?key=$k' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.dataImported || app.candidateSites.isEmpty) return _emptyState();

    _fitIfNeeded(app);
    final center = app.assets.isNotEmpty ? LatLng(app.assets.first.latitude, app.assets.first.longitude) : const LatLng(-23.1791, -45.8872);
    final result = app.currentResult;
    final covered = result == null ? <int>{} : _opt.coveredAssetIndexes(assets: app.assets, gateways: result.chosenGateways, rangeKm: result.params.effectiveRangeKm);
    final chosenIds = result?.chosenGateways.map((g) => g.id).toSet() ?? {};

    return SafeArea(
      child: LayoutBuilder(builder: (context, cts) {
        final wide = cts.maxWidth > 900;
        final mapWidget = ClipRRect(
          borderRadius: BorderRadius.circular(wide ? 16 : 0),
          child: Container(
            color: AppColors.surfaceAlt, // fundo visível mesmo se o mapa falhar em carregar
            child: Stack(children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(initialCenter: center, initialZoom: 12),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl(app),
                      userAgentPackageName: 'com.gridsight.app',
                      errorTileCallback: (tile, error, stack) => debugPrint('Tile falhou: $error'),
                    ),
                    if (showCoverage && result != null)
                      CircleLayer(circles: [
                        for (final g in result.chosenGateways)
                          CircleMarker(point: LatLng(g.latitude, g.longitude), radius: result.params.effectiveRangeKm * 1000, useRadiusInMeter: true, color: AppColors.coverage.withOpacity(0.14), borderColor: AppColors.coverage.withOpacity(0.6), borderStrokeWidth: 1.5),
                      ]),
                    if (showAssets)
                      MarkerLayer(markers: [
                        for (var i = 0; i < app.assets.length; i++)
                          Marker(point: LatLng(app.assets[i].latitude, app.assets[i].longitude), width: 14, height: 14, child: _dot(covered.contains(i) ? AppColors.coverage : AppColors.alert)),
                      ]),
                    if (showCandidates)
                      MarkerLayer(markers: [
                        for (final c in app.candidateSites)
                          if (!chosenIds.contains(c.id))
                            Marker(point: LatLng(c.latitude, c.longitude), width: 22, height: 22, child: _tapDot(() => app.toggleManualGateway(c), 14, AppColors.surface.withOpacity(0.55), AppColors.textSecondary, 1.6)),
                      ]),
                    if (showGateways && result != null)
                      MarkerLayer(markers: [
                        for (final g in result.chosenGateways)
                          Marker(point: LatLng(g.latitude, g.longitude), width: 30, height: 30, child: _tapDot(() => app.toggleManualGateway(g), 26, AppColors.energy, Colors.white, 2.5)),
                      ]),
                  ],
                ),
              ),
              Positioned(top: wide ? 12 : 8, left: wide ? 12 : 8, child: const _Legend()),
              Positioned(top: wide ? 12 : 8, right: wide ? 12 : 8, child: _recenterButton(() => _fitNow(app))),
              Positioned(bottom: 6, right: 8, child: Text(app.backendBaseUrl != null ? '© OpenStreetMap contributors' : '© OpenStreetMap contributors © CARTO', style: const TextStyle(fontSize: 9, color: Colors.black54))),
            ]),
          ),
        );

        final controls = _controls(app, result, showAssets, showCandidates, showGateways, showCoverage,
            (v) => setState(() => showAssets = v), (v) => setState(() => showCandidates = v), (v) => setState(() => showGateways = v), (v) => setState(() => showCoverage = v));

        // Em telas largas: mapa + painel lado a lado, com título e dica
        // acima. Em celular/tablet: o mapa ocupa a tela quase inteira
        // (é o "produto principal" da tela), e os controles ficam num
        // painel deslizante, acessível por um botão flutuante — assim o
        // mapa fica bem visível por padrão, sem o painel fixo roubando
        // metade da altura da tela.
        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle(title: 'Mapa de Cobertura'),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Toque num local candidato (quadrado cinza) pra marcá-lo como gateway na hora. Toque de novo num gateway (âmbar) pra desmarcar.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: mapWidget),
                  const SizedBox(width: 16),
                  SizedBox(width: 300, child: SingleChildScrollView(child: controls)),
                ]),
              ),
            ]),
          );
        }

        return Stack(children: [
          Positioned.fill(child: mapWidget),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openControlsSheet(context, controls),
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(result == null ? 'Camadas e otimização' : 'Camadas · ${(result.coveragePercent * 100).toStringAsFixed(0)}% cobertura'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.textPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
        ]);
      }),
    );
  }

  void _openControlsSheet(BuildContext context, Widget controls) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(child: controls),
        ),
      ),
    );
  }
}

Widget _dot(Color color) => Container(decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: Colors.white, width: 1.5)));

Widget _tapDot(VoidCallback onTap, double size, Color color, Color border, double borderWidth) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: Container(width: size, height: size, decoration: BoxDecoration(borderRadius: BorderRadius.circular(size > 20 ? 5 : 2), color: color, border: Border.all(color: border, width: borderWidth)))),
    );

Widget _recenterButton(VoidCallback onPressed) => Material(
      color: AppColors.surface.withOpacity(0.92),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)), child: const Icon(Icons.center_focus_strong, color: AppColors.textPrimary, size: 20)),
      ),
    );

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.92), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _legendItem(AppColors.coverage, 'Ativo coberto', BoxShape.circle),
          _legendItem(AppColors.alert, 'Ativo não coberto', BoxShape.circle),
          _legendItem(AppColors.textSecondary, 'Local candidato', BoxShape.rectangle, filled: false),
          _legendItem(AppColors.energy, 'Gateway escolhido', BoxShape.rectangle, size: 13),
        ]),
      );
}

Widget _legendItem(Color color, String label, BoxShape shape, {bool filled = true, double size = 10}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: size, height: size, decoration: BoxDecoration(color: filled ? color : Colors.transparent, shape: shape, borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(2) : null, border: filled ? null : Border.all(color: color, width: 1.6))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
      ]),
    );

Widget _controls(AppState app, dynamic result, bool sa, bool sc, bool sg, bool sCov, ValueChanged<bool> oa, ValueChanged<bool> oc, ValueChanged<bool> og, ValueChanged<bool> oCov) {
  final toggles = [('Ativos', sa, oa), ('Locais candidatos', sc, oc), ('Gateways escolhidos', sg, og), ('Área de cobertura', sCov, oCov)];
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Camadas do mapa', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        for (final (label, value, onChanged) in toggles) SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(label, style: const TextStyle(fontSize: 13)), value: value, onChanged: onChanged),
        const Divider(height: 26),
        ElevatedButton.icon(
          onPressed: app.running ? null : () => app.runOptimization(),
          icon: app.running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background)) : const Icon(Icons.play_circle_outline),
          label: Text(app.running ? 'Otimizando...' : 'Executar otimização'),
        ),
        const SizedBox(height: 14),
        if (result != null) ...[
          const Text('Resultado', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _resultLine('Cobertura', '${(result.coveragePercent * 100).toStringAsFixed(1)}%'),
          _resultLine('Gateways usados', '${result.gatewaysUsed}'),
          _resultLine('Ativos cobertos', '${result.coveredAssets} / ${result.totalAssets}'),
          _resultLine('Tempo de processamento', '${result.processingTime.inMilliseconds} ms'),
        ],
      ]),
    ),
  );
}

Widget _resultLine(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ]),
    );

Widget _emptyState() => const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.map_outlined, size: 48, color: AppColors.textSecondary),
          SizedBox(height: 14),
          Text('Nenhum dado importado ainda', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          SizedBox(height: 6),
          Text('Vá até "Importação de Dados" para carregar os ativos e locais candidatos antes de visualizar o mapa.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      ),
    );
