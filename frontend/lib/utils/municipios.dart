import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;

/// Cidade mais próxima de qualquer coordenada, sem internet.
///
/// Usa a lista dos 5.570 municípios do IBGE (sede de cada um, em
/// `assets/data/municipios.csv`). Serve para dizer a cidade de TODOS os ativos,
/// candidatos e gateways na hora. É aproximado: perto da divisa de dois
/// municípios pode apontar o vizinho. O bairro vem do OpenStreetMap, ao tocar.
class Municipios {
  Municipios._();

  static final List<_Cidade> _todas = [];
  static final Map<int, List<_Cidade>> _grade = {};
  static bool _pronto = false;
  static Future<void>? _carregando;

  static int _chave(int i, int j) => i * 100000 + j;

  static Future<void> carregar() => _carregando ??= _ler();

  static Future<void> _ler() async {
    try {
      final txt = await rootBundle.loadString('assets/data/municipios.csv');
      for (final linha in txt.split('\n')) {
        final p = linha.trim().split(';');
        if (p.length < 4) continue;
        final lat = double.tryParse(p[2]), lon = double.tryParse(p[3]);
        if (lat == null || lon == null) continue;
        final c = _Cidade(p[0], p[1], lat, lon);
        _todas.add(c);
        _grade.putIfAbsent(_chave((lat / 0.5).floor(), (lon / 0.5).floor()), () => []).add(c);
      }
      _pronto = true;
    } catch (_) {
      _pronto = false;
    }
  }

  /// "Cidade - UF" mais próxima, ou null se a lista ainda não carregou.
  static String? maisProxima(double lat, double lon) {
    final c = _nearest(lat, lon);
    return c == null ? null : '${c.nome} - ${c.uf}';
  }

  /// Sigla do estado (ex.: "BA") do município mais próximo, ou null se a lista ainda não carregou.
  static String? ufMaisProxima(double lat, double lon) => _nearest(lat, lon)?.uf;

  static bool get pronto => _pronto;

  static _Cidade? _nearest(double lat, double lon) {
    if (!_pronto) return null;
    final i = (lat / 0.5).floor(), j = (lon / 0.5).floor();
    _Cidade? best;
    var bestD = double.infinity;
    for (var r = 0; r <= 12; r++) {
      for (var di = -r; di <= r; di++) {
        for (var dj = -r; dj <= r; dj++) {
          if (math.max(di.abs(), dj.abs()) != r) continue; // só o anel r
          final l = _grade[_chave(i + di, j + dj)];
          if (l == null) continue;
          for (final c in l) {
            final d = _d2(lat, lon, c.lat, c.lon);
            if (d < bestD) {
              bestD = d;
              best = c;
            }
          }
        }
      }
      // um anel a mais depois de achar o primeiro, para não errar na borda da grade
      if (best != null && r >= 1) {
        final minNext = r * 0.5 * 111.0 * 0.8; // 0,8 = cos(35°), pior caso em longitude
        if (math.sqrt(bestD) <= minNext) break;
      }
    }
    return best;
  }

  /// Distância aproximada ao quadrado, em km² (plano local, basta para comparar).
  static double _d2(double la1, double lo1, double la2, double lo2) {
    final dy = (la1 - la2) * 111.0;
    final dx = (lo1 - lo2) * 111.0 * math.cos(la1 * math.pi / 180);
    return dx * dx + dy * dy;
  }
}

class _Cidade {
  final String nome, uf;
  final double lat, lon;
  const _Cidade(this.nome, this.uf, this.lat, this.lon);
}
