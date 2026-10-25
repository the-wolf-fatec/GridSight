import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/asset.dart';
import '../models/terrain_analysis.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../services/optimization_service.dart';
import '../widgets/section_title.dart';
import 'import_screen.dart' show distribuidoraColor;

// Chave grátis do CartoDB (carto.com/basemaps/apikey), opcional.
const String? cartoApiKey = null;

// Cor dos gateways escolhidos pelo ALGORITMO (pra distinguir dos marcados
// manualmente no mapa, que continuam em âmbar/energy).
const Color _algoGatewayColor = Color(0xFF8B5CF6); // roxo

// Ativo que está ao alcance de um gateway em linha reta, mas perdeu o sinal
// por causa do relevo (morro no caminho). É a marca visual da influência do relevo.
const Color _lostColor = Color(0xFFD946EF); // magenta

// Região padrão em que o mapa abre — centro aproximado do ESTADO DE SÃO
// PAULO inteiro (não mais só São José dos Campos), já que os dados hoje
// cobrem várias distribuidoras espalhadas pelo estado. Zoom baixo o
// suficiente pra mostrar o estado inteiro de uma vez; a busca ou navegação
// manual ainda funcionam pra focar numa região específica depois.
const LatLng _defaultCenter = LatLng(-22.3, -48.5);
const double _defaultZoom = 7;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.active = true});
  final bool active; // true quando esta é a aba selecionada no momento

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  bool showAssets = true, showCandidates = true, showGateways = true, showCoverage = true;
  bool showRelief = false; // camada de relevo (sombreado + altitude) do backend
  bool showCircles = true; // (fixo ligado) // círculo do alcance máximo (sem relevo), para comparar com a área real
  String? _selectedGatewayId; // gateway tocado: destaca círculo x área com relevo
  bool _addMode = false; // true = tocar no mapa cria um local candidato ali
  final _map = MapController();
  final _opt = OptimizationService();
  final _distance = const Distance();
  final _searchCtrl = TextEditingController();
  List<_PlaceResult> _searchResults = [];
  bool _searching = false;

  // Pisca-pisca dos buracos do relevo (só roda com a camada "Relevo" ligada).
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _blinkOpacity = Tween<double>(begin: 0.12, end: 0.95).animate(CurvedAnimation(parent: _blink, curve: Curves.easeInOut));

  String? _blinkAssetId; // ativo sem sinal tocado: pisca por alguns segundos
  Timer? _blinkAssetTimer;

  void _blinkAsset(String id) {
    _blinkAssetTimer?.cancel();
    setState(() => _blinkAssetId = id);
    if (!_blink.isAnimating) _blink.repeat(reverse: true);
    _blinkAssetTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _blinkAssetId = null);
      _syncBlink();
    });
  }

  bool _peaksBlink = false; // sugestões de pontos altos na tela: a área sem cobertura pisca

  void _syncBlink() {
    if (!showRelief && !_peaksBlink && _blinkAssetId != null) return;
    if (showRelief || _peaksBlink) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
    } else {
      _blink.stop();
    }
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Volta pra região padrão sempre que o usuário troca PRA essa aba —
    // sem isso, a câmera podia ficar presa numa posição antiga se o mapa
    // já tivesse sido montado antes em segundo plano.
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _map.move(_defaultCenter, _defaultZoom));
    }
  }

  @override
  void dispose() {
    _blinkAssetTimer?.cancel();
    _blink.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Busca um lugar (cidade, bairro, endereço) via geocodificação e move o
  /// mapa pra lá — é o jeito de "escolher qualquer região", já que não
  /// ajustamos mais o zoom automaticamente pra caber todos os dados.
  Timer? _searchDebounce;

  // Espera um pouco depois que a pessoa PARA de digitar antes de buscar de
  // verdade — sem isso, cada letra dispara um pedido pro Nominatim, que só
  // aceita 1 por segundo e começa a bloquear depois de 2-3 buscas seguidas.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 600), () => _searchPlace(query));
  }

  Future<void> _searchPlace(String query) async {
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final app = context.read<AppState>();
      // Passa pelo backend (proxy) em vez de chamar o Nominatim direto —
      // o app sozinho não consegue (CORS no Web, bloqueio de rede no
      // Android), mesmo motivo que já tínhamos com os tiles do mapa.
      final base = app.backendBaseUrl ?? 'http://localhost:8080/api';
      final uri = Uri.parse('$base/geocode?q=${Uri.encodeQueryComponent(query)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        setState(() => _searchResults = list.map((e) => _PlaceResult(name: e['display_name'] as String, lat: double.parse(e['lat'] as String), lon: double.parse(e['lon'] as String))).toList());
      }
    } catch (_) {
      // Busca é um extra — se falhar (backend fora do ar, etc.), só não
      // mostra resultado, não quebra o resto do mapa.
    }
    setState(() => _searching = false);
  }

  /// Busca cidade/bairro a partir de uma coordenada (reverse geocoding),
  /// usado na hora de mostrar detalhe de um ativo/candidato tocado no
  /// mapa. Retorna null se falhar — a tela de info mostra só o que já
  /// sabe (nome, tipo, lat/lon) nesse caso, sem travar.
  Future<Map<String, String>?> _reverseGeocode(double lat, double lon) async {
    try {
      final app = context.read<AppState>();
      final base = app.backendBaseUrl ?? 'http://localhost:8080/api';
      final uri = Uri.parse('$base/geocode/reverse?lat=$lat&lon=$lon');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final addr = (data['address'] as Map<String, dynamic>?) ?? {};
      final cidade = (addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['village'] ?? '') as String;
      final bairro = (addr['suburb'] ?? addr['neighbourhood'] ?? addr['quarter'] ?? '') as String;
      return {'cidade': cidade, 'bairro': bairro};
    } catch (_) {
      return null;
    }
  }

  /// Mostra nome, tipo, cidade, bairro e lat/lon de um ativo ou candidato
  /// tocado no mapa. Pra candidato que ainda não é gateway, mostra também
  /// um botão de confirmação — só vira gateway depois de tocar em "OK",
  /// nunca direto no primeiro toque.

  // Buracos do relevo que de fato têm ativo sem sinal dentro (o resto não é desenhado).
  TerrainAnalysis? _shadowTerrain;
  int _shadowAssetCount = -1;
  Map<String, List<List<LatLng>>> _shadowCache = const {};

  Map<String, List<List<LatLng>>> _populatedShadows(AppState app, TerrainAnalysis terrain) {
    if (identical(_shadowTerrain, terrain) && _shadowAssetCount == app.assets.length) return _shadowCache;
    // Garantia de coerência: nenhum pedaço magenta pode conter um ativo que tem sinal.
    final served = [for (final a in app.assets) if (terrain.linkByAsset.containsKey(a.id)) LatLng(a.latitude, a.longitude)];
    // Só vale como "sem sinal" onde há rede: a até 6 km de algum ativo (grade de 0,02° para ser rápido).
    final grid = <String, List<LatLng>>{};
    String key(double la, double lo) => '${(la / 0.02).floor()}_${(lo / 0.02).floor()}';
    for (final a in app.assets) {
      grid.putIfAbsent(key(a.latitude, a.longitude), () => []).add(LatLng(a.latitude, a.longitude));
    }
    bool nearAsset(List<LatLng> poly) {
      final la = poly.fold<double>(0, (s, q) => s + q.latitude) / poly.length;
      final lo = poly.fold<double>(0, (s, q) => s + q.longitude) / poly.length;
      final i = (la / 0.02).floor(), j = (lo / 0.02).floor();
      for (var di = -1; di <= 1; di++) {
        for (var dj = -1; dj <= 1; dj++) {
          final l = grid['${i + di}_${j + dj}'];
          if (l != null && l.any((pt) => _nearQuad(poly, pt, 6.0))) return true;
        }
      }
      return false;
    }
    final out = <String, List<List<LatLng>>>{};
    terrain.shadows.forEach((gid, polys) {
      out[gid] = [
        for (final poly in polys)
          if (nearAsset(poly) && !served.any((pt) => _inQuad(poly, pt))) poly,
      ];
    });
    _shadowTerrain = terrain;
    _shadowAssetCount = app.assets.length;
    return _shadowCache = out;
  }

  /// O centro do quadrilátero fica a até [km] do ponto (aproximação plana, suficiente para 1–2 km).
  static bool _nearQuad(List<LatLng> poly, LatLng pt, double km) {
    var la = 0.0, lo = 0.0;
    for (final q in poly) {
      la += q.latitude;
      lo += q.longitude;
    }
    la /= poly.length;
    lo /= poly.length;
    final dy = (la - pt.latitude) * 111.2;
    final dx = (lo - pt.longitude) * 111.2 * math.cos(pt.latitude * math.pi / 180);
    return dx * dx + dy * dy <= km * km;
  }

  static bool _inQuad(List<LatLng> poly, LatLng pt) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.latitude > pt.latitude) != (b.latitude > pt.latitude) &&
          pt.longitude < (b.longitude - a.longitude) * (pt.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Toque numa área magenta: explica por que ali a transmissão não funciona.
  void _explainShadowTap(BuildContext context, AppState app, LatLng point) {
    final result = app.currentResult;
    final TerrainAnalysis? terrain = result?.terrain as TerrainAnalysis?;
    if (result == null || terrain == null || !(showRelief || _peaksBlink)) return;
    final ringKm = math.min(100.0, result.params.effectiveRangeKm as double);

    final cells = terrain.shadows.values.any((l) => l.isNotEmpty);
    final shadows = cells ? _populatedShadows(app, terrain) : const <String, List<List<LatLng>>>{};

    // gateway mais próximo cuja área sem sinal contém o toque
    dynamic best;
    List<LatLng>? hitCell;
    var bestKm = double.infinity;
    for (final g in result.chosenGateways) {
      if (_selectedGatewayId != null && _selectedGatewayId != g.id) continue;
      final gp0 = LatLng(g.latitude as double, g.longitude as double);
      final d = _distance.as(LengthUnit.Kilometer, gp0, point);
      if (d > ringKm) continue;
      List<LatLng>? cell;
      if (cells) {
        for (final poly in (shadows[g.id] ?? const <List<LatLng>>[])) {
          if (_inQuad(poly, point)) {
            cell = poly;
            break;
          }
        }
        if (cell == null) continue;
      } else {
        final fp0 = terrain.footprints[g.id];
        if (fp0 == null || fp0.length < 3 || _inQuad(fp0, point)) continue;
      }
      if (d < bestKm) {
        bestKm = d;
        best = g;
        hitCell = cell;
      }
    }
    if (best == null) return;
    final g = best;
    final gp = LatLng(g.latitude as double, g.longitude as double);

    final lostHere = [
      for (final a in app.assets)
        if (terrain.lostToTerrainIds.contains(a.id) &&
            (hitCell != null
                ? (_inQuad(hitCell, LatLng(a.latitude, a.longitude)) || _nearQuad(hitCell, LatLng(a.latitude, a.longitude), 1.5))
                : (_distance.as(LengthUnit.Kilometer, gp, LatLng(a.latitude, a.longitude)) <= ringKm &&
                    !_inQuad(terrain.footprints[g.id]!, LatLng(a.latitude, a.longitude)))))
          a,
    ];
    final obs = terrain.obstacles[g.id] ?? const <TerrainObstacle>[];
    final names = <String>[];
    for (final a in lostHere.take(3)) {
      final z = terrain.lostInfo[a.id];
      names.add(z != null && z.hasElevation ? '${a.name} (${z.elevationM.round()} m)' : '${a.name}');
    }
    final plural = lostHere.length == 1 ? '' : 's';
    final more = lostHere.length > 3 ? '…' : '';
    final morros = obs.take(3).map((o) => '${o.elevationM.round()} m').join(', ');
    final parts = <String>[
      'O relevo bloqueia o sinal do gateway nesta área, a ${bestKm.toStringAsFixed(1)} km dele.',
      if (lostHere.isNotEmpty) '${lostHere.length} ativo$plural sem sinal: ${names.join(', ')}$more.',
      if (obs.isNotEmpty) 'Morros no caminho: $morros.',
    ];
    _showPlaceInfo(
      context,
      name: 'Área sem transmissão',
      type: 'Gateway ${g.name}',
      lat: point.latitude,
      lon: point.longitude,
      note: parts.join('\n'),
      noteColor: _lostColor,
    );
  }

  /// Pontos de um círculo geodésico de [km] de raio (para poder furá-lo com o contorno real).
  List<LatLng> _circlePoints(LatLng c, double km, {int n = 96}) =>
      [for (var i = 0; i < n; i++) _distance.offset(c, km * 1000, i * 360.0 / n)];

  void _showPlaceInfo(
      BuildContext context, {
        required String name,
        required String type,
        required double lat,
        required double lon,
        VoidCallback? onConfirmGateway,
        String? note,
        Color noteColor = AppColors.textSecondary,
      }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) {
        return FutureBuilder<Map<String, String>?>(
          future: _reverseGeocode(lat, lon),
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final cidade = snapshot.data?['cidade'] ?? '';
            final bairro = snapshot.data?['bairro'] ?? '';
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(type, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 14),
                if (loading)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                else ...[
                  _infoRow('Cidade', cidade.isEmpty ? 'não identificada' : cidade),
                  _infoRow('Bairro', bairro.isEmpty ? 'não identificado' : bairro),
                ],
                _infoRow('Latitude', lat.toStringAsFixed(6)),
                _infoRow('Longitude', lon.toStringAsFixed(6)),
                if (note != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: noteColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: noteColor.withOpacity(0.5))),
                    child: Text(note, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                  ),
                ],
                if (onConfirmGateway != null) ...[
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Cancelar'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onConfirmGateway();
                        },
                        child: const Text('OK, marcar como gateway'),
                      ),
                    ),
                  ]),
                ],
              ]),
            );
          },
        );
      },
    );
  }

  void _goToPlace(_PlaceResult place) {
    _map.move(LatLng(place.lat, place.lon), 13);
    setState(() {
      _searchResults = [];
      _searchCtrl.clear();
    });
    FocusScope.of(context).unfocus();
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

  /// Índices (em app.assets) dos ativos que ficam dentro do alcance de um gateway específico.
  List<int> _assetsCoveredBy(AppState app, dynamic gateway, double rangeKm) {
    final gp = LatLng(gateway.latitude, gateway.longitude);
    final out = <int>[];
    for (var i = 0; i < app.assets.length; i++) {
      final a = app.assets[i];
      if (_distance.as(LengthUnit.Kilometer, gp, LatLng(a.latitude, a.longitude)) <= rangeKm) out.add(i);
    }
    return out;
  }

  /// Mostra por que este gateway específico foi escolhido pelo algoritmo:
  /// em que ordem, e quais ativos ele cobre. Tem um botão pra desmarcar
  /// dentro do próprio cartão, então o toque no gateway deixou de
  /// desmarcar na hora — agora sempre explica primeiro.
  void _showGatewayInfo(BuildContext context, AppState app, dynamic gateway, dynamic result) {
    final isManual = app.manualGatewayIds.contains(gateway.id as String);
    final order = result.chosenGateways.indexOf(gateway) + 1;
    final total = result.chosenGateways.length as int;
    final TerrainAnalysis? terrain = result.terrain as TerrainAnalysis?;
    // Com relevo: só os ativos que ESTE gateway atende (melhor sinal), com a potência recebida.
    // Sem relevo: todos os ativos dentro do raio, como antes.
    final List<String> coveredLabels;
    if (terrain != null) {
      final nameById = {for (final a in app.assets) a.id: a.name};
      coveredLabels = [
        for (final l in terrain.linksOf(gateway.id as String)) '${nameById[l.assetId] ?? l.assetId} · ${l.rxDbm.toStringAsFixed(0)} dBm',
      ];
    } else {
      final coveredIdx = _assetsCoveredBy(app, gateway, result.params.effectiveRangeKm as double);
      coveredLabels = [for (final i in coveredIdx) app.assets[i].name as String];
    }

    final String explanation;
    if (isManual) {
      explanation = 'Marcado por você. Atende ${coveredLabels.length} ativo${coveredLabels.length == 1 ? '' : 's'}.';
    } else {
      explanation = '${order}º de $total gateways.';
    }

    // Alcance máximo x área real com relevo (só quando há contorno calculado)
    String? shapeSummary;
    final fp = terrain?.footprints[gateway.id as String];
    if (terrain != null && fp != null && fp.isNotEmpty) {
      final ringKm = math.min(100.0, (result.params.effectiveRangeKm as double));
      final gp = LatLng(gateway.latitude as double, gateway.longitude as double);
      final radii = [for (final pt in fp) _distance.as(LengthUnit.Kilometer, gp, pt)];
      final areaPct = (radii.map((r) => r * r).reduce((a, b) => a + b) / radii.length / (ringKm * ringKm) * 100).clamp(0, 100);
      shapeSummary = 'Cobre ${areaPct.toStringAsFixed(0)}% do círculo.';
      final obs = terrain.obstacles[gateway.id as String] ?? const [];
      if (obs.isNotEmpty) {
        shapeSummary = '$shapeSummary Morros: ${obs.take(4).map((o) => '${o.elevationM.round()} m').join(', ')}.';
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: isManual ? AppColors.energy : _algoGatewayColor, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(gateway.name as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              ]),
              const SizedBox(height: 12),
              if (shapeSummary != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.energy.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.energy.withOpacity(0.5))),
                  child: Text(shapeSummary, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                explanation,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Text(terrain != null ? 'Atende ${coveredLabels.length} ativo${coveredLabels.length == 1 ? '' : 's'} (sinal recebido):' : 'Cobre ${coveredLabels.length} ativo${coveredLabels.length == 1 ? '' : 's'}:',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              if (coveredLabels.isEmpty)
                const Text('Nenhum ativo atendido por este gateway.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final label in coveredLabels) Chip(label: Text(label, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    app.toggleManualGateway(gateway);
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Desmarcar como gateway'),
                ),
              ),
            ]),
          ),
        ),
      ),
    ).whenComplete(() {
      // volta a mostrar todos os gateways quando o cartão fecha
      if (mounted) setState(() => _selectedGatewayId = null);
    });
  }

  /// Modo "adicionar no mapa": enquanto ativo, tocar em qualquer ponto do
  /// mapa pede um nome e cria um local candidato ali na hora — sem
  /// precisar abrir o formulário e digitar latitude/longitude na mão.
  Future<void> _handleAddTap(BuildContext context, AppState app, LatLng point) async {
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'Poste');
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo local candidato'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nome do local', hintText: 'Ex.: Poste Rua das Flores')),
          const SizedBox(height: 12),
          TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Tipo', hintText: 'Ex.: Poste, Subestação')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop((nameCtrl.text.trim(), typeCtrl.text.trim())), child: const Text('Criar aqui')),
        ],
      ),
    );
    if (result == null || result.$1.isEmpty) return;

    await app.addManualCandidateSite(name: result.$1, type: result.$2.isEmpty ? 'Manual' : result.$2, latitude: point.latitude, longitude: point.longitude);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${result.$1}" criado — toque em outro ponto pra continuar, ou desligue o modo adicionar.'), duration: const Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.dataImported || app.candidateSites.isEmpty) return _emptyState();

    // (não ajustamos mais o zoom automaticamente pra caber todos os dados —
    // veja o comentário perto de _defaultCenter no topo do arquivo)
    // Sempre abre na região padrão (não mais no primeiro ativo importado) —
    // com dados espalhados pelo território inteiro, isso evitava o mapa
    // abrir "no meio do nada" dependendo de qual ativo vem primeiro na lista.
    final result = app.currentResult;
    final TerrainAnalysis? terrain = result?.terrain;
    final Set<int> covered;
    if (result == null) {
      covered = <int>{};
    } else if (terrain != null) {
      // com relevo: quem manda é o backend (sinal enlace a enlace), não o raio
      covered = {for (var i = 0; i < app.assets.length; i++) if (terrain.isCovered(app.assets[i].id)) i};
    } else {
      covered = _opt.coveredAssetIndexes(assets: app.assets, gateways: result.chosenGateways, rangeKm: result.params.effectiveRangeKm);
    }
    final chosenIds = result?.chosenGateways.map((g) => g.id).toSet() ?? {};
    final hasFootprints = terrain != null && terrain.footprints.isNotEmpty;
    final hasShadows = hasFootprints; // círculo verde + área grande sem sinal (círculo menos o contorno real)

    // Raio do círculo "ideal" (sem relevo). O backend limita a 100 km quando usa relevo.
    final ringKm = result == null ? 0.0 : (terrain != null ? math.min(100.0, result.params.effectiveRangeKm) : result.params.effectiveRangeKm);

    // Descobre de qual distribuidora é cada local candidato (pra colorir no
    // mapa) — usa o agrupamento feito na hora da importação, já que o
    // próprio CandidateSite pode não trazer esse campo de volta do backend.
    final candidateDistribuidoraById = <String, String>{};
    for (final entry in app.candidateSitesByDistribuidora.entries) {
      for (final c in entry.value) candidateDistribuidoraById[c.id] = entry.key;
    }

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
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: _defaultZoom,
                    // Rodinha do mouse pra cima = zoom in (mais foco);
                    // pra baixo = zoom out (menos foco). Só tem efeito em
                    // desktop/web (com mouse de verdade) — no celular,
                    // continua o pinça-pra-zoom normal.
                    // InteractiveFlag.all já inclui zoom pela rodinha do
                    // mouse nessa versão do flutter_map (8.x) — não existe
                    // mais um parâmetro separado scrollWheelVelocity.
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                    onTap: (tapPosition, point) {
                      if (_addMode) {
                        _handleAddTap(context, app, point);
                      } else {
                        _explainShadowTap(context, app, point);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl(app),
                      userAgentPackageName: 'com.gridsight.app',
                      errorTileCallback: (tile, error, stack) => debugPrint('Tile falhou: $error'),
                    ),
                    if (showRelief && app.backendBaseUrl != null)
                      TileLayer(
                        urlTemplate: '${app.backendBaseUrl}/terrain/tiles/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.gridsight.app',
                        errorTileCallback: (tile, error, stack) => debugPrint('Tile de relevo falhou: $error'),
                      ),
                    // Círculo do alcance máximo (como seria sem relevo): é o que o relevo "quebra".
                    if (showCircles && result != null && terrain != null && hasFootprints)
                      CircleLayer(circles: [
                        for (final g in result.chosenGateways)
                          if (_selectedGatewayId == null || _selectedGatewayId == g.id)
                            CircleMarker(
                              point: LatLng(g.latitude, g.longitude),
                              radius: ringKm * 1000,
                              useRadiusInMeter: true,
                              color: _selectedGatewayId == g.id ? Colors.white.withOpacity(0.08) : Colors.transparent,
                              borderColor: Colors.white.withOpacity(_selectedGatewayId == g.id ? 0.95 : 0.8),
                              borderStrokeWidth: _selectedGatewayId == g.id ? 2.5 : 1.6,
                            ),
                      ]),
                    // Alcance de cada gateway (círculo inteiro) com "buracos" onde o relevo bloqueia.
                    if (showCircles && result != null && terrain != null && hasShadows)
                      PolygonLayer(polygons: [
                        for (final g in result.chosenGateways)
                          if (_selectedGatewayId == null || _selectedGatewayId == g.id)
                            Polygon(
                              points: _circlePoints(LatLng(g.latitude, g.longitude), ringKm),
                              color: AppColors.coverage.withOpacity(_selectedGatewayId == g.id ? 0.30 : 0.18),
                              borderColor: Colors.white.withOpacity(0.8),
                              borderStrokeWidth: 1.6,
                            ),
                      ]),
                    // Área sem sinal: pedaços do círculo que NENHUM gateway escolhido atende por causa do relevo. Pisca com o botão "Relevo".
                    if ((showRelief || _peaksBlink) && result != null && terrain != null && hasShadows)
                      FadeTransition(
                        opacity: _blinkOpacity,
                        child: PolygonLayer(polygons: [
                          for (final g in result.chosenGateways)
                            if (_selectedGatewayId == null || _selectedGatewayId == g.id)
                              for (final poly in (_populatedShadows(app, terrain)[g.id] ?? const <List<LatLng>>[]))
                                Polygon(points: poly, color: _lostColor, borderStrokeWidth: 1.2, borderColor: _lostColor),
                        ]),
                      ),
                    // Pontos altos sugeridos para gateways novos.
                    if (app.peakSuggestions.isNotEmpty)
                      MarkerLayer(markers: [
                        for (final pk in app.peakSuggestions)
                          Marker(
                            point: pk.point,
                            width: 96,
                            height: 52,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _showPlaceInfo(
                                context,
                                name: 'Ponto alto de ${pk.elevationM.round()} m',
                                type: 'Sugestão de gateway · ${pk.group}',
                                lat: pk.point.latitude,
                                lon: pk.point.longitude,
                                note: 'Recuperaria ${pk.newlyCovered} ativos sem sinal.',
                                noteColor: AppColors.energy,
                                onConfirmGateway: () => app.usePeak(pk),
                              ),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.change_history, size: 24, color: AppColors.energy, shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.energy)),
                                  child: Text('${pk.elevationM.round()} m · +${pk.newlyCovered}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                                ),
                              ]),
                            ),
                          ),
                      ]),
                    // Altura dos morros que impedem o sinal.
                    if ((showRelief || _peaksBlink) && result != null && terrain != null && hasFootprints)
                      MarkerLayer(markers: [
                        for (final g in result.chosenGateways)
                          if (_selectedGatewayId == null || _selectedGatewayId == g.id)
                            for (final o in (terrain.obstacles[g.id] ?? const <TerrainObstacle>[]).take(_selectedGatewayId == null ? 2 : 6))
                              Marker(
                                point: o.point,
                                width: 210,
                                height: 40,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _showPlaceInfo(
                                    context,
                                    name: 'Morro de ${o.elevationM.round()} m',
                                    type: 'Morro',
                                    lat: o.point.latitude,
                                    lon: o.point.longitude,
                                    note: 'O sinal não passa: o morro tem ${o.elevationM.round()} m e fica ${o.aboveLineOfSightM.round()} m acima da linha de alcance, a ${o.distanceKm.toStringAsFixed(1)} km do gateway.',
                                    noteColor: _lostColor,
                                  ),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.landscape, size: 20, color: _lostColor, shadows: const [Shadow(color: Colors.black54, blurRadius: 3)]),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                                      child: Text('${o.elevationM.round()} m · área sem cobertura (relevo)', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                                    ),
                                  ]),
                                ),
                              ),
                      ]),
                    // Com relevo: contorno REAL de onde o sinal chega (irregular, morros recortam a área).
                    if (showCoverage && result != null && terrain != null && hasFootprints && !hasShadows)
                      PolygonLayer(polygons: [
                        for (final g in result.chosenGateways)
                          if (terrain.footprints[g.id] != null && (_selectedGatewayId == null || _selectedGatewayId == g.id))
                            Polygon(
                              points: terrain.footprints[g.id]!,
                              color: (_selectedGatewayId == g.id ? AppColors.energy : AppColors.coverage).withOpacity(_selectedGatewayId == g.id ? 0.35 : 0.22),
                              borderColor: (_selectedGatewayId == g.id ? AppColors.energy : AppColors.coverage).withOpacity(0.9),
                              borderStrokeWidth: _selectedGatewayId == g.id ? 2.5 : 1.5,
                            ),
                      ]),
                    if (showCircles && result != null && terrain != null && !hasFootprints)
                      CircleLayer(circles: [
                        for (final g in result.chosenGateways)
                          CircleMarker(point: LatLng(g.latitude, g.longitude), radius: ringKm * 1000, useRadiusInMeter: true, color: Colors.transparent, borderColor: Colors.white.withOpacity(0.8), borderStrokeWidth: 1.6),
                      ]),
                    if (showCoverage && result != null && !hasFootprints)
                      CircleLayer(circles: [
                        for (final g in result.chosenGateways)
                          CircleMarker(point: LatLng(g.latitude, g.longitude), radius: result.params.effectiveRangeKm * 1000, useRadiusInMeter: true, color: AppColors.coverage.withOpacity(0.14), borderColor: AppColors.coverage.withOpacity(0.6), borderStrokeWidth: 1.5),
                      ]),
                    // Morro que isola o ativo tocado (altitude escrita).
                    if (terrain != null && _blinkAssetId != null && terrain.lostInfo[_blinkAssetId]?.blocker != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: terrain.lostInfo[_blinkAssetId]!.blocker!.point,
                          width: 220,
                          height: 44,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.landscape, size: 22, color: _lostColor, shadows: const [Shadow(color: Colors.black54, blurRadius: 3)]),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(4)),
                              child: Text('${terrain.lostInfo[_blinkAssetId]!.blocker!.elevationM.round()} m · área sem cobertura (relevo)', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        ),
                      ]),
                    if (showAssets)
                      MarkerLayer(markers: [
                        for (var i = 0; i < app.assets.length; i++)
                          Marker(
                            point: LatLng(app.assets[i].latitude, app.assets[i].longitude),
                            width: 26,
                            height: 26,
                            child: () {
                              final asset = app.assets[i];
                              final isLost = terrain != null && !covered.contains(i) && terrain.lostToTerrainIds.contains(asset.id);
                              final dot = _tapDot(
                                () {
                                  if (isLost) _blinkAsset(asset.id);
                                  final (note, noteColor) = _assetNote(app, terrain, asset);
                                  _showPlaceInfo(context, name: asset.name, type: 'Ativo · ${asset.type}', lat: asset.latitude, lon: asset.longitude, note: note, noteColor: noteColor);
                                },
                                isLost && _blinkAssetId == asset.id ? 20 : 14,
                                covered.contains(i) ? AppColors.coverage : (isLost ? _lostColor : AppColors.alert),
                                Colors.white,
                                isLost && _blinkAssetId == asset.id ? 2.5 : 1.5,
                              );
                              return isLost && (_blinkAssetId == asset.id || showRelief || _peaksBlink) ? FadeTransition(opacity: _blinkOpacity, child: dot) : dot;
                            }(),
                          ),
                      ]),
                    if (showCandidates)
                      MarkerLayer(markers: [
                        for (final c in app.candidateSites)
                          if (!chosenIds.contains(c.id))
                            Marker(
                              point: LatLng(c.latitude, c.longitude),
                              width: 22,
                              height: 22,
                              child: _tapDot(
                                    () => _showPlaceInfo(
                                  context,
                                  name: c.name,
                                  type: 'Local candidato · ${c.type}',
                                  lat: c.latitude,
                                  lon: c.longitude,
                                  onConfirmGateway: () => app.toggleManualGateway(c),
                                ),
                                14,
                                (candidateDistribuidoraById[c.id] != null ? distribuidoraColor(candidateDistribuidoraById[c.id]!) : AppColors.textSecondary).withOpacity(0.75),
                                AppColors.textSecondary,
                                1.6,
                              ),
                            ),
                      ]),
                    if (showGateways && result != null)
                      MarkerLayer(markers: [
                        for (final g in result.chosenGateways)
                          Marker(
                            point: LatLng(g.latitude, g.longitude),
                            width: 30,
                            height: 30,
                            child: _tapDot(
                                  () {
                                    setState(() => _selectedGatewayId = g.id);
                                    _showGatewayInfo(context, app, g, result);
                                  },
                              26,
                              app.manualGatewayIds.contains(g.id) ? AppColors.energy : _algoGatewayColor,
                              Colors.white,
                              2.5,
                            ),
                          ),
                      ]),
                  ],
                ),
              ),
              Positioned(top: wide ? 12 : 8, left: wide ? 12 : 8, child: _Legend(distribuidoras: app.candidateSitesByDistribuidora.keys.toList(), hasTerrain: terrain != null)),
              Positioned(
                top: wide ? 12 : 8,
                right: wide ? 12 : 8,
                child: Column(children: [
                  _recenterButton(() => _fitNow(app)),
                  const SizedBox(height: 8),
                  _addModeButton(_addMode, () => setState(() => _addMode = !_addMode)),
                  if (terrain != null && (terrain.lostToTerrainIds.isNotEmpty || app.peakSuggestions.isNotEmpty)) ...[
                    const SizedBox(height: 8),
                    _peakButton(
                      active: app.peakSuggestions.isNotEmpty,
                      busy: app.suggestingPeaks,
                      onPressed: () async {
                        if (app.peakSuggestions.isNotEmpty) {
                          app.clearPeakSuggestions();
                          setState(() => _peaksBlink = false);
                          _syncBlink();
                          return;
                        }
                        await app.suggestPeaks();
                        if (!mounted) return;
                        setState(() => _peaksBlink = app.peakSuggestions.isNotEmpty);
                        _syncBlink();
                        if (app.peakMessage != null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.peakMessage!)));
                        }
                      },
                    ),
                  ],
                ]),
              ),
              // Lista de resultados da busca — abre PRA CIMA, ancorada bem
              // em cima da barra de busca (que fica embaixo do mapa).
              if (_searchResults.isNotEmpty)
                Positioned(
                  bottom: (wide ? 12 : 90) + 52,
                  left: wide ? 12 : 8,
                  right: wide ? 12 : 8,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.surface,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        reverse: true, // resultado mais relevante fica colado na barra de busca, embaixo da lista
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (context, i) {
                          final r = _searchResults[_searchResults.length - 1 - i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined, size: 18),
                            title: Text(r.name, style: const TextStyle(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => _goToPlace(r),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              // Barra de busca de região — fica embaixo do mapa (acima do
              // botão fixo "Camadas e otimização" no celular), com a lista
              // de resultados abrindo pra CIMA (acima dela mesma), não pra baixo.
              Positioned(
                bottom: wide ? 12 : 90,
                left: wide ? 12 : 8,
                right: wide ? 12 : 8,
                child: Material(
                  color: AppColors.surface.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(10),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar cidade, bairro ou endereço...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searching
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                          : (_searchCtrl.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() { _searchCtrl.clear(); _searchResults = []; }))
                          : null),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    ),
                  ),
                ),
              ),
              if (_addMode)
                Positioned(
                  top: wide ? 12 : 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.energy, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                      child: const Text('Modo adicionar ligado — toque em qualquer ponto do mapa', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              Positioned(bottom: 6, right: 8, child: Text(app.backendBaseUrl != null ? '© OpenStreetMap contributors' : '© OpenStreetMap contributors © CARTO', style: const TextStyle(fontSize: 9, color: Colors.black54))),
            ]),
          ),
        );

        final List<(String, bool, ValueChanged<bool>)> toggles = [
          ('Ativos', showAssets, (v) => setState(() => showAssets = v)),
          ('Locais candidatos', showCandidates, (v) => setState(() => showCandidates = v)),
          ('Gateways escolhidos', showGateways, (v) => setState(() => showGateways = v)),
          if (!hasFootprints) ('Área de cobertura', showCoverage, (v) => setState(() => showCoverage = v)),
          if (app.backendBaseUrl != null) ('Relevo', showRelief, (v) => setState(() { showRelief = v; _syncBlink(); })),
        ];
        final controls = _controls(app, result, toggles);

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
                child: Text('Toque num local candidato (quadrado cinza) pra marcá-lo como gateway na hora. Toque num gateway (âmbar) pra ver por que foi escolhido. Use o botão de "+" no mapa pra criar candidatos tocando onde quiser.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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

class _PlaceResult {
  final String name;
  final double lat;
  final double lon;
  const _PlaceResult({required this.name, required this.lat, required this.lon});
}

Widget _dot(Color color) => Container(decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: Colors.white, width: 1.5)));

Widget _infoRow(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Row(children: [
    SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
    Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
  ]),
);

Widget _tapDot(VoidCallback onTap, double size, Color color, Color border, double borderWidth) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Center(child: Container(width: size, height: size, decoration: BoxDecoration(borderRadius: BorderRadius.circular(size > 20 ? 5 : 2), color: color, border: Border.all(color: border, width: borderWidth)))),
);

Widget _peakButton({required bool active, required bool busy, required VoidCallback onPressed}) => Tooltip(
  message: active ? 'Limpar sugestões' : 'Sugerir pontos altos',
  child: Material(
    color: active ? AppColors.energy.withOpacity(0.9) : AppColors.surface.withOpacity(0.92),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: busy ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(active ? Icons.close : Icons.landscape, color: active ? Colors.black : AppColors.energy, size: 20),
      ),
    ),
  ),
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

Widget _addModeButton(bool active, VoidCallback onPressed) => Material(
  color: active ? AppColors.energy : AppColors.surface.withOpacity(0.92),
  borderRadius: BorderRadius.circular(10),
  child: InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onPressed,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
      child: Icon(active ? Icons.close : Icons.add_location_alt, color: active ? Colors.white : AppColors.textPrimary, size: 20),
    ),
  ),
);

class _Legend extends StatelessWidget {
  const _Legend({required this.distribuidoras, this.hasTerrain = false});
  final List<String> distribuidoras;
  final bool hasTerrain;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.92), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _legendItem(AppColors.coverage, 'Ativo coberto', BoxShape.circle),
      _legendItem(AppColors.alert, 'Ativo não coberto', BoxShape.circle),
      if (hasTerrain) _legendItem(_lostColor, 'Ativo sem sinal (relevo)', BoxShape.circle),
      if (hasTerrain) _legendItem(Colors.white70, 'Alcance sem relevo', BoxShape.circle, filled: false),
      if (hasTerrain) _legendItem(_lostColor.withOpacity(0.6), 'Área sem transmissão (relevo)', BoxShape.rectangle, size: 11),
      if (hasTerrain) _legendItem(AppColors.coverage, 'Cobertura com relevo', BoxShape.rectangle, size: 11),
      if (distribuidoras.isEmpty)
        _legendItem(AppColors.textSecondary, 'Local candidato', BoxShape.rectangle, filled: false)
      else
        for (final d in distribuidoras) _legendItem(distribuidoraColor(d), 'Candidato ($d)', BoxShape.rectangle, size: 11),
      _legendItem(_algoGatewayColor, 'Gateway (algoritmo)', BoxShape.rectangle, size: 13),
      _legendItem(AppColors.energy, 'Gateway (manual)', BoxShape.rectangle, size: 13),
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

Widget _controls(AppState app, dynamic result, List<(String, bool, ValueChanged<bool>)> toggles) {
  final TerrainAnalysis? terrain = result?.terrain as TerrainAnalysis?;
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
        if (app.updatingManual)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Expanded(child: Text('Recalculando a cobertura com relevo...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            ]),
          ),
        if (app.terrainError != null) _noticeBox(app.terrainError!, AppColors.energy),
        const SizedBox(height: 14),
        if (result != null) ...[
          const Text('Resultado', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _resultLine('Cobertura', '${(result.coveragePercent * 100).toStringAsFixed(1)}%'),
          _resultLine('Gateways usados', '${result.gatewaysUsed}'),
          _resultLine('Ativos cobertos', '${result.coveredAssets} / ${result.totalAssets}'),
          _resultLine('Relevo', result.params.useTerrain ? 'considerado' : 'não considerado'),
          _resultLine('Tempo de processamento', '${result.processingTime.inMilliseconds} ms'),
        ],
        if (terrain != null && result != null && result.params.useTerrain) ...[
          const SizedBox(height: 14),
          _TerrainInfluence(terrain: terrain, totalAssets: result.totalAssets as int, gatewaysUsed: result.gatewaysUsed as int),
        ],
        if (result != null && !(result.params.useTerrain as bool))
          _noticeBox('Este cenário não considerou o relevo.', AppColors.primaryLight),
      ]),
    ),
  );
}

Widget _noticeBox(String text, Color color) => Container(
  margin: const EdgeInsets.only(top: 10),
  padding: const EdgeInsets.all(10),
  width: double.infinity,
  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.5))),
  child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
);

/// Painel que responde "o relevo está influenciando?": compara o planejamento
/// ignorando o relevo com o que acontece quando ele entra na conta.
class _TerrainInfluence extends StatelessWidget {
  const _TerrainInfluence({required this.terrain, required this.totalAssets, required this.gatewaysUsed});
  final TerrainAnalysis terrain;
  final int totalAssets;
  final int gatewaysUsed;

  String _pct(int n) => totalAssets == 0 ? '0%' : '${(n / totalAssets * 100).toStringAsFixed(1)}% ($n de $totalAssets)';

  @override
  Widget build(BuildContext context) {
    final w = terrain.withoutTerrain;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.terrain, size: 16, color: AppColors.coverage),
          SizedBox(width: 6),
          Text('Influência do relevo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        _infLine('Sem relevo', '${w?.gateways ?? gatewaysUsed} gateways'),
        _infLine('Com relevo', '$gatewaysUsed gateways', color: (w != null && gatewaysUsed > w.gateways) ? AppColors.energy : null),
        for (final warning in terrain.warnings) _noticeBox(warning, AppColors.energy),
      ]),
    );
  }
}

Widget _infLine(String label, String value, {Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
    Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
  ]),
);

/// Texto de "o que aconteceu com este ativo" para o cartão de detalhes.
(String?, Color) _assetNote(AppState app, TerrainAnalysis? terrain, Asset asset) {
  final result = app.currentResult;
  const dist = Distance();
  final here = LatLng(asset.latitude, asset.longitude);
  if (result == null) return (null, AppColors.textSecondary);
  final rangeKm = terrain != null ? math.min(100.0, result.params.effectiveRangeKm) : result.params.effectiveRangeKm;

  double? nearestKm(Iterable<dynamic> sites) {
    double? best;
    for (final g in sites) {
      final d = dist.as(LengthUnit.Kilometer, here, LatLng(g.latitude as double, g.longitude as double));
      if (best == null || d < best) best = d;
    }
    return best;
  }

  if (terrain != null) {
    final link = terrain.linkByAsset[asset.id];
    if (link != null) {
      String gatewayName = link.gatewayId;
      for (final c in app.candidateSites) {
        if (c.id == link.gatewayId) {
          gatewayName = c.name;
          break;
        }
      }
      final marginDb = link.rxDbm + 120; // folga acima da sensibilidade (-120 dBm)
      final edge = marginDb < 5 ? ' (no limite)' : '';
      return ('Atendido por $gatewayName · ${link.rxDbm.toStringAsFixed(0)} dBm$edge', AppColors.coverage);
    }
    if (terrain.lostToTerrainIds.contains(asset.id)) {
      final info = terrain.lostInfo[asset.id];
      final b = info?.blocker;
      final parts = <String>[
        'Sem sinal: o relevo bloqueia.',
        if (info != null && info.hasElevation) 'Altitude: ${info.elevationM.round()} m.',
        if (b != null) 'Morro: ${b.elevationM.round()} m, a ${b.distanceKm.toStringAsFixed(1)} km do gateway.',
      ];
      return (parts.join('\n'), _lostColor);
    }
  } else {
    final d = nearestKm(result.chosenGateways);
    if (d != null && d <= rangeKm) return ('Dentro do alcance (${d.toStringAsFixed(1)} km do gateway).', AppColors.coverage);
  }

  // Fora do alcance: diz o motivo.
  if (result.chosenGateways.isEmpty) return ('Fora do alcance: nenhum gateway escolhido.', AppColors.alert);
  final near = nearestKm(result.chosenGateways)!;
  if (near > rangeKm) {
    final pool = app.candidateSitesByDistribuidora[asset.distribuidora] ?? app.candidateSites;
    final cand = nearestKm(pool.where((c) => !result.chosenGateways.any((g) => g.id == c.id)));
    if (cand != null && cand <= rangeKm) {
      return ('Fora do alcance: gateway escolhido mais próximo a ${near.toStringAsFixed(1)} km (alcance ${rangeKm.toStringAsFixed(1)} km). '
          'Há candidato a ${cand.toStringAsFixed(1)} km não escolhido (limite de gateways).', AppColors.alert);
    }
    return ('Fora do alcance: gateway mais próximo a ${near.toStringAsFixed(1)} km (alcance ${rangeKm.toStringAsFixed(1)} km).', AppColors.alert);
  }
  return ('Sinal insuficiente.', AppColors.alert);
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