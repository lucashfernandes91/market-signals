import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

const numericStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
double? number(dynamic value) {
  final parsed = double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

String priceText(dynamic value) {
  final n = number(value);
  if (n == null) return '—';
  final digits = n == 0 || n.abs() >= 1
      ? 2
      : n.abs() >= .01
          ? 4
          : 8;
  final parts = n.toStringAsFixed(digits).split('.');
  final grouped = parts.first
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return '$grouped,${parts.last}';
}

String compactText(dynamic value) {
  final n = number(value);
  if (n == null) return '—';
  for (final unit in [(1e12, 'tri'), (1e9, 'bi'), (1e6, 'mi'), (1e3, 'mil')]) {
    if (n.abs() >= unit.$1) {
      return '${(n / unit.$1).toStringAsFixed(2).replaceAll('.', ',')} ${unit.$2}';
    }
  }
  return priceText(n);
}

String percentText(double? value) => value == null
    ? '—'
    : '${value > 0 ? '+' : ''}${value.toStringAsFixed(2).replaceAll('.', ',')}%';

bool quoteFresh(Map<String, dynamic>? quote, DateTime now) {
  if (quote == null ||
      '${quote['stale']}' == 'true' ||
      quote['source_status'] == 'stale' ||
      quote['source_status'] == 'unavailable') {
    return false;
  }
  final at = DateTime.tryParse('${quote['timestamp']}');
  return at != null &&
      now.difference(at).inSeconds <= 20 &&
      number(quote['price']) != null;
}

List<double> closes(List<Map<String, dynamic>> candles) =>
    candles.map((c) => number(c['close'])).whereType<double>().toList();

double? candleChange(List<Map<String, dynamic>> candles) {
  if (candles.isEmpty) return null;
  final first = number(candles.first['open']);
  final last = number(candles.last['close']);
  if (first == null || last == null || first <= 0) return null;
  return (last - first) / first * 100;
}

class ChangeBadge extends StatelessWidget {
  const ChangeBadge(this.value, {this.compact = false, super.key});
  final double? value;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final color = value == null || value == 0
        ? AppTheme.muted
        : value! > 0
            ? AppTheme.positive
            : AppTheme.negative;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(7)),
      child: Text(percentText(value),
          style: numericStyle.copyWith(
              color: color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700)),
    );
  }
}

class CoinAvatar extends StatelessWidget {
  const CoinAvatar(this.symbol, {super.key, this.size = 40});
  final String symbol;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = switch (symbol) {
      'BTC' => const Color(0xFFD57A08),
      'ETH' => const Color(0xFF536BC1),
      'SOL' => const Color(0xFF7252C1),
      _ => AppTheme.accent,
    };
    return ExcludeSemantics(
        child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: color.withValues(alpha: .10), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: symbol == 'BTC'
          ? Icon(Icons.currency_bitcoin, color: color, size: size * .64)
          : Text(symbol,
              style: TextStyle(
                  fontSize: size * .26,
                  color: color,
                  fontWeight: FontWeight.w800)),
    ));
  }
}

class MarketHeader extends StatelessWidget {
  const MarketHeader(
      {required this.title,
      required this.subtitle,
      required this.onRefresh,
      this.onProfile,
      this.trailingAction,
      this.showRefresh = true,
      super.key});
  final String title;
  final String subtitle;
  final VoidCallback onRefresh;
  final VoidCallback? onProfile;
  final Widget? trailingAction;
  final bool showRefresh;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        child: LayoutBuilder(
            builder: (context, constraints) => Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Row(children: [
                          Icon(Icons.radar, size: 16, color: AppTheme.accent),
                          SizedBox(width: 6),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('MARKET RADAR',
                                  style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.muted)),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 13)),
                      ])),
                  if (trailingAction != null) trailingAction!,
                  if (onProfile != null)
                    IconButton(
                        tooltip: 'Abrir perfil',
                        onPressed: onProfile,
                        constraints: const BoxConstraints.tightFor(
                            width: 44, height: 44),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.account_circle_outlined,
                            size: 30)),
                  if (showRefresh && constraints.maxWidth >= 340)
                    IconButton.filledTonal(
                        tooltip: 'Atualizar dados',
                        onPressed: onRefresh,
                        constraints: const BoxConstraints.tightFor(
                            width: 44, height: 44),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.ink),
                        icon: const Icon(Icons.refresh_rounded)),
                ])),
      );
}

enum AsyncStateKind { loading, empty, unavailable }

class AsyncStatePanel extends StatelessWidget {
  const AsyncStatePanel.loading({
    this.label = 'Carregando dados…',
    this.minHeight = 220,
    super.key,
  })  : kind = AsyncStateKind.loading,
        title = null,
        description = null,
        onRetry = null,
        actionLabel = null,
        onAction = null,
        actionIcon = null,
        icon = null;

  const AsyncStatePanel.empty({
    required this.title,
    required this.description,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.minHeight = 220,
    super.key,
  })  : assert((actionLabel == null) == (onAction == null)),
        kind = AsyncStateKind.empty,
        label = null,
        onRetry = null;

  const AsyncStatePanel.unavailable({
    required this.title,
    required this.description,
    required this.onRetry,
    this.icon = Icons.cloud_off_outlined,
    this.minHeight = 220,
    super.key,
  })  : kind = AsyncStateKind.unavailable,
        label = null,
        actionLabel = null,
        onAction = null,
        actionIcon = null;

  final AsyncStateKind kind;
  final String? label;
  final String? title;
  final String? description;
  final VoidCallback? onRetry;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final isLoading = kind == AsyncStateKind.loading;
    final heading = title ?? label!;
    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  Semantics(
                    label: label,
                    liveRegion: true,
                    child: const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  )
                else
                  Icon(icon, size: 30, color: AppTheme.muted),
                const SizedBox(height: 12),
                Text(
                  heading,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted, height: 1.5),
                  ),
                ],
                if (onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: onAction,
                      icon: Icon(actionIcon ?? Icons.add_rounded),
                      label: Text(actionLabel!),
                    ),
                  ),
                if (onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PriceChart extends StatelessWidget {
  const PriceChart(
      {required this.values,
      this.height = 180,
      this.compact = false,
      super.key});
  final List<double> values;
  final double height;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
          height: height,
          child: const Center(
              child: Text('Histórico indisponível',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12))));
    }
    final color =
        values.last >= values.first ? AppTheme.positive : AppTheme.negative;
    return Semantics(
      label:
          'Gráfico de preços. Início ${priceText(values.first)}, fim ${priceText(values.last)}.',
      child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _LinePainter(values, color, compact))),
    );
  }
}

enum ChartMode { line, candles }

class InteractivePriceChart extends StatefulWidget {
  const InteractivePriceChart({
    required this.candles,
    required this.mode,
    this.selectedIndex,
    this.onSelected,
    this.height = 220,
    super.key,
  });

  final List<Map<String, dynamic>> candles;
  final ChartMode mode;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;
  final double height;

  @override
  State<InteractivePriceChart> createState() => _InteractivePriceChartState();
}

class _InteractivePriceChartState extends State<InteractivePriceChart> {
  void _select(Offset localPosition, double width) {
    if (widget.candles.length < 2 || width <= 0) return;
    final ratio = (localPosition.dx / width).clamp(0.0, 1.0);
    final index = (ratio * (widget.candles.length - 1)).round();
    widget.onSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.selectedIndex;
    final selected = index != null && index < widget.candles.length
        ? widget.candles[index]
        : null;
    final selectedPrice = selected == null
        ? null
        : number(selected['close'] ?? selected['price']);
    final selectedTime = selected == null
        ? null
        : DateTime.tryParse('${selected['timestamp']}')?.toLocal();
    final label = selectedPrice == null
        ? 'Gráfico de preços. Toque em um ponto para consultar preço e horário.'
        : 'Ponto selecionado: ${priceText(selectedPrice)} em ${selectedTime?.toLocal()}.';
    return Semantics(
      label: label,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _select(details.localPosition, constraints.maxWidth),
          onHorizontalDragUpdate: (details) =>
              _select(details.localPosition, constraints.maxWidth),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _InteractiveChartPainter(
                      widget.candles,
                      widget.mode,
                      widget.selectedIndex,
                    ),
                  ),
                ),
                if (selected != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: AppTheme.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                        child: Text(
                          '${priceText(selectedPrice)} · ${selectedTime == null ? '—' : '${selectedTime.day.toString().padLeft(2, '0')}/${selectedTime.month.toString().padLeft(2, '0')} ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'}',
                          style: numericStyle.copyWith(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InteractiveChartPainter extends CustomPainter {
  _InteractiveChartPainter(this.candles, this.mode, this.selectedIndex);
  final List<Map<String, dynamic>> candles;
  final ChartMode mode;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.length < 2) return;
    final values = [
      for (final candle in candles)
        ...[
          number(candle['high']),
          number(candle['low']),
        ].whereType<double>(),
    ];
    if (values.isEmpty) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final span = maxValue - minValue;
    const padding = 14.0;
    Offset point(int index, double value) => Offset(
          padding + index * (size.width - padding * 2) / (candles.length - 1),
          span == 0
              ? size.height / 2
              : padding +
                  (maxValue - value) / (span) * (size.height - padding * 2),
        );

    final grid = Paint()
      ..color = AppTheme.line
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = padding + i * (size.height - padding * 2) / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (mode == ChartMode.line) {
      final path = Path();
      for (var i = 0; i < candles.length; i++) {
        final value = number(candles[i]['close']);
        if (value == null) continue;
        final current = point(i, value);
        i == 0
            ? path.moveTo(current.dx, current.dy)
            : path.lineTo(current.dx, current.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppTheme.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      final candleWidth = (size.width / candles.length * .55).clamp(2.0, 12.0);
      for (var i = 0; i < candles.length; i++) {
        final open = number(candles[i]['open']);
        final close = number(candles[i]['close']);
        final high = number(candles[i]['high']);
        final low = number(candles[i]['low']);
        if (open == null || close == null || high == null || low == null) {
          continue;
        }
        final center = point(i, close).dx;
        final color = close >= open ? AppTheme.positive : AppTheme.negative;
        final wick = Paint()
          ..color = color
          ..strokeWidth = 1.2;
        canvas.drawLine(point(i, high), point(i, low), wick);
        final top = point(i, math.max(open, close)).dy;
        final bottom = point(i, math.min(open, close)).dy;
        canvas.drawRect(
          Rect.fromLTRB(center - candleWidth / 2, top, center + candleWidth / 2,
              math.max(bottom, top + 1)),
          Paint()..color = color,
        );
      }
    }

    final index = selectedIndex;
    if (index != null && index >= 0 && index < candles.length) {
      final value = number(candles[index]['close']);
      if (value != null) {
        final selected = point(index, value);
        canvas.drawLine(
          Offset(selected.dx, 0),
          Offset(selected.dx, size.height),
          Paint()
            ..color = AppTheme.accent.withValues(alpha: .45)
            ..strokeWidth = 1,
        );
        canvas.drawCircle(selected, 5, Paint()..color = AppTheme.accent);
        canvas.drawCircle(selected, 2, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveChartPainter old) =>
      old.candles != candles ||
      old.mode != mode ||
      old.selectedIndex != selectedIndex;
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color, this.compact);
  final List<double> values;
  final Color color;
  final bool compact;
  @override
  void paint(Canvas canvas, Size size) {
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final span = maxValue - minValue;
    final padding = compact ? 3.0 : 12.0;
    final points = List.generate(
        values.length,
        (i) => Offset(
            padding + i * (size.width - padding * 2) / (values.length - 1),
            span == 0
                ? size.height / 2
                : padding +
                    (maxValue - values[i]) /
                        span *
                        (size.height - padding * 2)));
    if (!compact) {
      final grid = Paint()
        ..color = AppTheme.line
        ..strokeWidth = 1;
      for (var i = 0; i < 4; i++) {
        final y = padding + i * (size.height - padding * 2) / 3;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (!compact) {
      final fill = Path.from(path)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: .17),
                color.withValues(alpha: 0)
              ],
            ).createShader(Offset.zero & size));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 1.8 : 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    if (!compact) {
      canvas.drawCircle(points.last, 5, Paint()..color = Colors.white);
      canvas.drawCircle(points.last, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.color != color;
}
