import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/asset.dart';
import '../models/scenario_result.dart';
import 'optimization_service.dart';

/// Relatório em PDF de um cenário: resumo, parâmetros, relevo, redundância,
/// mapa esquemático e lista de gateways.
///
/// Usa só as fontes padrão do PDF (Latin-1): acentos do português funcionam, e qualquer
/// caractere fora disso (raro, vindo de nomes da base) vira "?".
String _safe(String s) => String.fromCharCodes(s.runes.map((r) => r < 256 ? r : 63));

const _ink = PdfColor.fromInt(0xFF111827);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _teal = PdfColor.fromInt(0xFF14B8A6);
const _amber = PdfColor.fromInt(0xFFF4A300);
const _red = PdfColor.fromInt(0xFFE0523A);
const _purple = PdfColor.fromInt(0xFF8B5CF6);
const _line = PdfColor.fromInt(0xFFD1D5DB);

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

pw.Widget _h(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(_safe(text), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
    );

pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: pw.Text(_safe(text), textAlign: align, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: _ink)),
    );

pw.Widget _table(List<String> header, List<List<String>> rows, {Map<int, pw.TableColumnWidth>? widths}) {
  return pw.Table(
    border: pw.TableBorder.all(color: _line, width: 0.5),
    columnWidths: widths,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F4F6)),
        children: [for (final h in header) _cell(h, bold: true)],
      ),
      for (final r in rows) pw.TableRow(children: [for (final c in r) _cell(c)]),
    ],
  );
}

pw.Widget _keyValue(List<(String, String)> items) {
  return _table(
    const ['Item', 'Valor'],
    [for (final (k, v) in items) [k, v]],
    widths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
  );
}

/// Mapa esquemático (sem imagem de fundo): ativos cobertos/descobertos e gateways.
pw.Widget _schematicMap(ScenarioResult r, List<Asset> assets, Set<int> covered, {double width = 500, double height = 300}) {
  final lats = <double>[], lons = <double>[];
  for (final a in assets) {
    lats.add(a.latitude);
    lons.add(a.longitude);
  }
  for (final g in r.chosenGateways) {
    lats.add(g.latitude);
    lons.add(g.longitude);
  }
  if (lats.isEmpty) return pw.SizedBox(height: 0);
  final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
  final minLon = lons.reduce(math.min), maxLon = lons.reduce(math.max);
  final midLat = (minLat + maxLat) / 2;
  final kx = math.cos(midLat * math.pi / 180); // corrige a largura de 1 grau de longitude
  final spanX = math.max(1e-6, (maxLon - minLon) * kx);
  final spanY = math.max(1e-6, maxLat - minLat);
  final scale = math.min((width - 16) / spanX, (height - 16) / spanY);
  final offX = (width - spanX * scale) / 2, offY = (height - spanY * scale) / 2;

  double px(double lon) => offX + (lon - minLon) * kx * scale;
  double py(double lat) => offY + (lat - minLat) * scale;

  // No máximo ~3000 pontos desenhados, para o PDF não ficar pesado.
  final step = math.max(1, (assets.length / 3000).ceil());

  return pw.SizedBox(
    width: width,
    height: height,
    child: pw.CustomPaint(
      size: PdfPoint(width, height),
      painter: (PdfGraphics canvas, PdfPoint size) {
        canvas
          ..setFillColor(const PdfColor.fromInt(0xFFF9FAFB))
          ..drawRect(0, 0, width, height)
          ..fillPath()
          ..setStrokeColor(_line)
          ..setLineWidth(0.6)
          ..drawRect(0, 0, width, height)
          ..strokePath();
        for (var i = 0; i < assets.length; i += step) {
          final a = assets[i];
          canvas
            ..setFillColor(covered.contains(i) ? _teal : _red)
            ..drawEllipse(px(a.longitude), py(a.latitude), 1.5, 1.5)
            ..fillPath();
        }
        for (final g in r.chosenGateways) {
          canvas
            ..setFillColor(_purple)
            ..drawEllipse(px(g.longitude), py(g.latitude), 4.2, 4.2)
            ..fillPath()
            ..setStrokeColor(const PdfColor.fromInt(0xFFFFFFFF))
            ..setLineWidth(1)
            ..drawEllipse(px(g.longitude), py(g.latitude), 4.2, 4.2)
            ..strokePath();
        }
      },
    ),
  );
}

pw.Widget _legendDot(PdfColor c, String text) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
      pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: c, shape: pw.BoxShape.circle)),
      pw.SizedBox(width: 4),
      pw.Text(_safe(text), style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
    ]);

/// Monta o PDF. [assets] é a lista de ativos do mapa (usada só para o mapa esquemático).
Future<Uint8List> buildScenarioPdf({
  required ScenarioResult result,
  required List<Asset> assets,
  String distribuidoras = '',
}) async {
  final r = result;
  final terrain = r.terrain;
  final uncovered = r.totalAssets - r.coveredAssets;

  // Quais ativos estão cobertos (para o mapa): com relevo vem do backend; senão, pelo raio.
  final Set<int> covered;
  if (terrain != null) {
    covered = {for (var i = 0; i < assets.length; i++) if (terrain.isCovered(assets[i].id)) i};
  } else {
    covered = OptimizationService().coveredAssetIndexes(assets: assets, gateways: r.chosenGateways, rangeKm: r.params.effectiveRangeKm);
  }

  // Resumo por distribuidora e lista (limitada) dos ativos sem cobertura.
  final perDist = <List<String>>[];
  final uncoveredRows = <List<String>>[];
  var uncoveredTotal = 0;
  if (assets.isNotEmpty) {
    final tot = <String, int>{}, cov = <String, int>{};
    for (var i = 0; i < assets.length; i++) {
      final d = assets[i].distribuidora.isEmpty ? '(sem distribuidora)' : assets[i].distribuidora;
      tot[d] = (tot[d] ?? 0) + 1;
      if (covered.contains(i)) {
        cov[d] = (cov[d] ?? 0) + 1;
      } else {
        uncoveredTotal++;
        if (uncoveredRows.length < 300) {
          uncoveredRows.add([assets[i].name, d, assets[i].latitude.toStringAsFixed(5), assets[i].longitude.toStringAsFixed(5)]);
        }
      }
    }
    final nomes = tot.keys.toList()..sort();
    for (final d in nomes) {
      final t = tot[d]!, c = cov[d] ?? 0;
      perDist.add([d, '$t', '$c', '${t - c}', _pct(t == 0 ? 0 : c / t)]);
    }
  }

  final doc = pw.Document(title: _safe('GridSight - ${r.label}'), author: 'GridSight');
  final date = r.executedAt;
  String two(int n) => n.toString().padLeft(2, '0');
  final dateText = '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('GridSight - Planejamento de cobertura de radiofrequencia', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      pw.Text('Pagina ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
    ]),
    build: (ctx) => [
      pw.Text('Relatório do cenário', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 2),
      pw.Text(_safe(r.label), style: pw.TextStyle(fontSize: 13, color: _teal, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(_safe('Gerado em $dateText${distribuidoras.isEmpty ? '' : '  |  Distribuidoras: $distribuidoras'}'), style: const pw.TextStyle(fontSize: 9, color: _muted)),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
          _kpi('Cobertura', _pct(r.coveragePercent), _teal),
          _kpi('Gateways', '${r.gatewaysUsed}', _purple),
          _kpi('Ativos cobertos', '${r.coveredAssets}/${r.totalAssets}', _ink),
          _kpi('Descobertos', '$uncovered', uncovered > 0 ? _red : _ink),
        ]),
      ),

      _h('Resumo'),
      _keyValue([
        ('Ativos cobertos', '${r.coveredAssets} de ${r.totalAssets} (${_pct(r.coveragePercent)})'),
        ('Ativos sem cobertura', '$uncovered'),
        ('Gateways utilizados', '${r.gatewaysUsed}'),
        ('Tempo de processamento', '${r.processingTime.inMilliseconds} ms'),
      ]),

      _h('Parâmetros de rádio'),
      _keyValue([
        ('Alcance de referência', '${r.params.rangeKm.toStringAsFixed(2)} km'),
        ('Potência de transmissão', '${r.params.transmissionPowerDbm.toStringAsFixed(0)} dBm'),
        ('Alcance efetivo', '${r.params.effectiveRangeKm.toStringAsFixed(2)} km'),
        ('Altura da antena do gateway', '${r.params.gatewayHeightM.toStringAsFixed(1)} m'),
        ('Margem de segurança', '${r.params.fadeMarginDb.toStringAsFixed(1)} dB'),
        ('Meta de cobertura', '${(r.params.minCoverageTarget * 100).toStringAsFixed(0)}%'),
        ('Limite de gateways', '${r.params.maxGateways}'),
        ('Relevo', r.params.useTerrain ? 'considerado' : 'não considerado'),
      ]),

      if (terrain != null) ...[
        _h('Influência do relevo'),
        _keyValue([
          ('Cobertura só por distância (mesmos gateways)', '${terrain.coveredIgnoringTerrain} ativos'),
          ('Cobertura com relevo', '${terrain.coveredAssets} ativos'),
          ('Perdidos por causa do relevo', '${terrain.lostToTerrainIds.length} ativos'),
          ('Ativos alcançados por 2+ gateways', '${terrain.overlappedAssets}'),
          if (terrain.withoutTerrain != null) ('Gateways sem considerar relevo', '${terrain.withoutTerrain!.gateways}'),
        ]),
        _h('Redundância (segurança da rede)'),
        pw.Text(
          _safe('Dos ${terrain.coveredAssets} ativos cobertos, ${terrain.protectedCount} têm reserva (2 ou mais gateways) e ${terrain.singlePointCount} dependem de um único gateway.'),
          style: const pw.TextStyle(fontSize: 9.5, color: _ink),
        ),
        pw.SizedBox(height: 6),
        _table(
          const ['Gateway', 'Atende (melhor sinal)', 'Ficam sem sinal se cair'],
          [
            for (final g in r.chosenGateways)
              [g.name, '${terrain.linksOf(g.id).length}', '${terrain.dependentsOf(g.id)}'],
          ],
          widths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1.4), 2: const pw.FlexColumnWidth(1.6)},
        ),
      ],

      if (assets.isNotEmpty) ...[
        _h('Mapa esquemático'),
        _schematicMap(r, assets, covered),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          _legendDot(_purple, 'Gateway'),
          pw.SizedBox(width: 12),
          _legendDot(_teal, 'Ativo coberto'),
          pw.SizedBox(width: 12),
          _legendDot(_red, 'Ativo descoberto'),
        ]),
      ],

      _h('Gateways escolhidos'),
      if (r.chosenGateways.isEmpty)
        pw.Text('Nenhum gateway foi escolhido neste cenário.', style: const pw.TextStyle(fontSize: 9.5, color: _muted))
      else
        _table(
          const ['#', 'Nome', 'Tipo', 'Latitude', 'Longitude'],
          [
            for (var i = 0; i < r.chosenGateways.length; i++)
              [
                '${i + 1}',
                r.chosenGateways[i].name,
                r.chosenGateways[i].type,
                r.chosenGateways[i].latitude.toStringAsFixed(6),
                r.chosenGateways[i].longitude.toStringAsFixed(6),
              ],
          ],
          widths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(1.6),
            4: const pw.FlexColumnWidth(1.6),
          },
        ),

      if (assets.isNotEmpty) ...[
        _h('Resumo por distribuidora'),
        _table(
          const ['Distribuidora', 'Ativos', 'Cobertos', 'Descobertos', 'Cobertura'],
          perDist,
          widths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1.2), 4: const pw.FlexColumnWidth(1.2)},
        ),
        if (uncoveredRows.isNotEmpty) ...[
          _h('Ativos sem cobertura'),
          if (uncoveredTotal > uncoveredRows.length)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(_safe('Mostrando os primeiros ${uncoveredRows.length} de $uncoveredTotal ativos sem cobertura.'), style: const pw.TextStyle(fontSize: 9, color: _muted)),
            ),
          _table(
            const ['Ativo', 'Distribuidora', 'Latitude', 'Longitude'],
            uncoveredRows,
            widths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2.2), 2: const pw.FlexColumnWidth(1.3), 3: const pw.FlexColumnWidth(1.3)},
          ),
        ],
      ],

      if (terrain != null && terrain.warnings.isNotEmpty) ...[
        _h('Avisos'),
        for (final w in terrain.warnings) pw.Bullet(text: _safe(w), style: const pw.TextStyle(fontSize: 9, color: _ink)),
      ],
    ],
  ));

  return doc.save();
}

pw.Widget _kpi(String label, String value, PdfColor color) => pw.Column(children: [
      pw.Text(_safe(value), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
      pw.SizedBox(height: 2),
      pw.Text(_safe(label), style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
    ]);

String _fileName(ScenarioResult r) {
  final base = r.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return 'gridsight-${base.isEmpty ? 'cenario' : base}.pdf';
}

/// Abre a visualização/impressão do PDF (no navegador, dá para "Salvar como PDF").
Future<void> printScenarioPdf({required ScenarioResult result, required List<Asset> assets, String distribuidoras = ''}) async {
  final bytes = await buildScenarioPdf(result: result, assets: assets, distribuidoras: distribuidoras);
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName(result));
}

/// Baixa/compartilha o arquivo PDF.
Future<void> downloadScenarioPdf({required ScenarioResult result, required List<Asset> assets, String distribuidoras = ''}) async {
  final bytes = await buildScenarioPdf(result: result, assets: assets, distribuidoras: distribuidoras);
  await Printing.sharePdf(bytes: bytes, filename: _fileName(result));
}


/// PDF de uma tabela (lista de gateways, ativos sem sinal...): página deitada, cabeçalho repetido em cada página.
/// [flex] dá a largura relativa de cada coluna (padrão 1); a primeira coluna (#) é fixa e estreita.
Future<Uint8List> buildTablePdf({
  required String titulo,
  required List<String> resumo,
  required List<String> header,
  required List<List<String>> rows,
  Map<int, double> flex = const {},
}) async {
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('GridSight - pagina ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
    ),
    build: (ctx) => [
      pw.Text(_safe(titulo), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 4),
      for (final l in resumo) pw.Text(_safe(l), style: const pw.TextStyle(fontSize: 10, color: _ink)),
      pw.SizedBox(height: 10),
      _table(header, rows, widths: {
        0: const pw.FixedColumnWidth(26),
        for (var i = 1; i < header.length; i++) i: pw.FlexColumnWidth(flex[i] ?? 1),
      }),
    ],
  ));
  return doc.save();
}

/// Baixa/compartilha um PDF de tabela.
Future<void> downloadTablePdf({
  required String filename,
  required String titulo,
  required List<String> resumo,
  required List<String> header,
  required List<List<String>> rows,
  Map<int, double> flex = const {},
}) async {
  final bytes = await buildTablePdf(titulo: titulo, resumo: resumo, header: header, rows: rows, flex: flex);
  await Printing.sharePdf(bytes: bytes, filename: filename);
}
