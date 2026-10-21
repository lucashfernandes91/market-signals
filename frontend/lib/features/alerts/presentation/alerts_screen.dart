import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../market/models/market.dart';
import '../../market/presentation/market_screen.dart';
import '../../market/presentation/market_widgets.dart';
import '../../notifications/presentation/notifications_screen.dart';

final alertsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.watch(apiClientProvider).get('/alerts/');
  final items = raw is List
      ? raw
      : (raw as Map<String, dynamic>)['results'] as List<dynamic>? ?? const [];
  return items.cast<Map<String, dynamic>>();
});

final alertEventsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, alertId) async {
  final raw =
      await ref.watch(apiClientProvider).get('/alerts/$alertId/events/');
  final items = raw is List
      ? raw
      : (raw as Map<String, dynamic>)['results'] as List<dynamic>? ?? const [];
  return items.cast<Map<String, dynamic>>();
});

Future<bool> showCreateAlert(
  BuildContext context,
  WidgetRef ref, {
  Market? market,
  double? initialPrice,
}) async {
  final values = await Future.wait([
    ref.read(marketsProvider.future),
    ref.read(currencyConversionProvider.future),
  ]);
  final markets = values[0] as List<Market>;
  final conversion = values[1] as CurrencyConversion;
  if (!context.mounted) return false;
  final draft = await showDialog<_AlertDraft>(
    context: context,
    builder: (_) => _AlertEditor(
      markets: markets,
      initialMarket: market,
      initialPrice: initialPrice,
      conversion: conversion,
    ),
  );
  if (draft == null) return false;
  if (!context.mounted) return false;
  final ready = await requireAccount(
    context,
    ref,
    action: 'salvar este alerta',
  );
  if (!ready || !context.mounted) return false;
  try {
    await ref.read(apiClientProvider).post(
          '/alerts/',
          draft.toJson(status: 'active'),
        );
    ref.invalidate(alertsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Alerta criado.'),
      ));
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Não foi possível criar o alerta: $error'),
      ));
    }
    return false;
  }
}

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  var _showPaused = false;

  @override
  Widget build(BuildContext context) {
    final authenticated = ref.watch(sessionControllerProvider).isAuthenticated;
    if (!authenticated) {
      return const _GuestAlertsScreen();
    }
    final alerts = ref.watch(alertsProvider);
    final loadedAlerts = alerts.asData?.value;
    final hasVisibleAlerts = loadedAlerts?.any(
            (item) => item['status'] == (_showPaused ? 'paused' : 'active')) ??
        false;
    return Scaffold(
      floatingActionButton: hasVisibleAlerts
          ? FloatingActionButton.extended(
              onPressed: () => _editAlert(context, ref),
              icon: const Icon(Icons.add_alert),
              label: const Text('Novo alerta'),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(alertsProvider);
            await ref.read(alertsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              MarketHeader(
                title: 'Alertas',
                subtitle: 'Acompanhe preços, variações e volume.',
                onRefresh: () => ref.invalidate(alertsProvider),
                showRefresh: false,
                trailingAction: IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()),
                  ),
                  icon: const Icon(Icons.history),
                  tooltip: 'Histórico de notificações',
                ),
              ),
              alerts.when(
                loading: () => const AsyncStatePanel.loading(
                  label: 'Carregando alertas…',
                  minHeight: 240,
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AsyncStatePanel.unavailable(
                    title: 'Alertas indisponíveis',
                    description: 'Não foi possível atualizar seus alertas.',
                    onRetry: () => ref.invalidate(alertsProvider),
                  ),
                ),
                data: (items) {
                  final visibleItems = items
                      .where((item) =>
                          item['status'] == (_showPaused ? 'paused' : 'active'))
                      .toList();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF0FF),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(children: [
                            Icon(Icons.notifications_active_outlined,
                                color: AppTheme.accent),
                            SizedBox(width: 13),
                            Expanded(
                                child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Monitoramento contínuo',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                SizedBox(height: 3),
                                Text(
                                    'O servidor acompanha suas condições mesmo com o app fechado.',
                                    style: TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 12,
                                        height: 1.4)),
                              ],
                            )),
                          ]),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Ativos'),
                              selected: !_showPaused,
                              onSelected: (_) =>
                                  setState(() => _showPaused = false),
                            ),
                            ChoiceChip(
                              label: const Text('Pausados'),
                              selected: _showPaused,
                              onSelected: (_) =>
                                  setState(() => _showPaused = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (visibleItems.isEmpty)
                          AsyncStatePanel.empty(
                            title: _showPaused
                                ? 'Nenhum alerta pausado'
                                : 'Crie seu primeiro alerta',
                            description: _showPaused
                                ? 'Alertas pausados aparecerão aqui.'
                                : 'Acompanhe preço, variação ou volume automaticamente.',
                            icon: Icons.add_alert_outlined,
                            actionLabel: _showPaused && items.isNotEmpty
                                ? 'Ver alertas ativos'
                                : 'Criar alerta',
                            actionIcon: _showPaused && items.isNotEmpty
                                ? Icons.notifications_active_outlined
                                : Icons.add_alert_outlined,
                            onAction: _showPaused && items.isNotEmpty
                                ? () => setState(() => _showPaused = false)
                                : () => _editAlert(context, ref),
                            minHeight: 220,
                          )
                        else
                          for (final item in visibleItems)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _alertCard(context, ref, item),
                            ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertCard(
      BuildContext context, WidgetRef ref, Map<String, dynamic> alert) {
    final market = alert['market'] as Map<String, dynamic>?;
    final active = alert['status'] == 'active';
    final conversion = ref.watch(currencyConversionProvider).valueOrNull;
    final base = market?['base_asset'] as Map<String, dynamic>?;
    final displaySymbol = conversion == null
        ? '${market?['canonical_symbol'] ?? '-'}'
        : '${base?['symbol'] ?? '-'}-${conversion.currency.code}';
    return Card(
      child: ListTile(
        minTileHeight: 82,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (active ? AppTheme.positive : AppTheme.muted)
                .withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            active ? Icons.notifications_active : Icons.notifications_paused,
            color: active ? AppTheme.positive : AppTheme.muted,
          ),
        ),
        title: Text(alert['name']?.toString() ?? 'Alerta'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child:
              Text('$displaySymbol · ${_conditionSummary(alert, conversion)}'),
        ),
        onTap: () => _editAlert(context, ref, alert: alert),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: active ? 'Pausar alerta' : 'Retomar alerta',
            onPressed: () => _handleAction(
              context,
              ref,
              alert,
              active ? _AlertAction.pause : _AlertAction.resume,
            ),
            icon: Icon(active ? Icons.pause_circle : Icons.play_circle),
          ),
          PopupMenuButton<_AlertAction>(
            tooltip: 'Mais ações',
            onSelected: (action) => _handleAction(context, ref, alert, action),
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: _AlertAction.history, child: Text('Histórico')),
              const PopupMenuItem(
                  value: _AlertAction.edit, child: Text('Editar')),
              const PopupMenuItem(
                  value: _AlertAction.delete, child: Text('Excluir')),
            ],
          ),
        ]),
      ),
    );
  }

  String _conditionSummary(
      Map<String, dynamic> alert, CurrencyConversion? conversion) {
    final conditions = alert['conditions'] as List<dynamic>? ?? const [];
    if (conditions.isEmpty) return alert['status']?.toString() ?? '-';
    final condition = conditions.first as Map<String, dynamic>;
    final type = switch ('${condition['condition_type']}') {
      'PRICE_ABOVE' => 'preço acima de',
      'PRICE_BELOW' => 'preço abaixo de',
      'PRICE_CHANGE_PERCENT' => 'variação de preço',
      'VOLUME_CHANGE_PERCENT' => 'variação de volume',
      _ => 'condição',
    };
    final percent = '${condition['condition_type']}'.endsWith('_PERCENT');
    final raw = condition['value_numeric'];
    final value = !percent && conversion != null
        ? multiplyCurrency(raw, conversion.rate)
        : '$raw';
    final suffix = percent ? '%' : ' ${conversion?.currency.code ?? 'USDT'}';
    return '$type ${priceText(value)}$suffix';
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> alert,
    _AlertAction action,
  ) async {
    try {
      switch (action) {
        case _AlertAction.history:
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AlertHistoryScreen(alert: alert),
          ));
        case _AlertAction.edit:
          await _editAlert(context, ref, alert: alert);
        case _AlertAction.pause:
          await ref
              .read(apiClientProvider)
              .post('/alerts/${alert['id']}/pause/');
          ref.invalidate(alertsProvider);
        case _AlertAction.resume:
          await ref
              .read(apiClientProvider)
              .post('/alerts/${alert['id']}/resume/');
          ref.invalidate(alertsProvider);
        case _AlertAction.delete:
          final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Excluir este alerta?'),
                  content: const Text(
                      'O monitoramento desta condição será encerrado.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Excluir'),
                    ),
                  ],
                ),
              ) ??
              false;
          if (!confirmed) return;
          await ref.read(apiClientProvider).delete('/alerts/${alert['id']}/');
          ref.invalidate(alertsProvider);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _editAlert(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? alert,
  }) async {
    final values = await Future.wait([
      ref.read(marketsProvider.future),
      ref.read(currencyConversionProvider.future),
    ]);
    final markets = values[0] as List<Market>;
    final conversion = values[1] as CurrencyConversion;
    if (!context.mounted) {
      return;
    }
    final draft = await showDialog<_AlertDraft>(
      context: context,
      builder: (_) => _AlertEditor(
        markets: markets,
        alert: alert,
        conversion: conversion,
      ),
    );
    if (draft == null) {
      return;
    }
    final body = draft.toJson(status: alert?['status']?.toString() ?? 'active');
    try {
      if (alert == null) {
        await ref.read(apiClientProvider).post('/alerts/', body);
      } else {
        await ref.read(apiClientProvider).put('/alerts/${alert['id']}/', body);
      }
      ref.invalidate(alertsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _GuestAlertsScreen extends ConsumerWidget {
  const _GuestAlertsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded,
                  size: 42, color: AppTheme.accent),
              const SizedBox(height: 16),
              Text('Alertas precisam de uma conta',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'Acompanhe o mercado livremente. Entre apenas para salvar regras e receber avisos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => requireAccount(
                  context,
                  ref,
                  action: 'criar alertas',
                ),
                icon: const Icon(Icons.login),
                label: const Text('Entrar ou criar conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AlertAction { history, edit, pause, resume, delete }

class AlertHistoryScreen extends ConsumerWidget {
  const AlertHistoryScreen({required this.alert, super.key});
  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${alert['id']}';
    final events = ref.watch(alertEventsProvider(id));
    final market = alert['market'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico do alerta'),
        actions: [
          IconButton(
            tooltip: 'Atualizar histórico',
            onPressed: () => ref.invalidate(alertEventsProvider(id)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AsyncStatePanel.unavailable(
          title: 'Histórico indisponível',
          description: 'Não foi possível carregar os disparos deste alerta.',
          onRetry: () => ref.invalidate(alertEventsProvider(id)),
        ),
        data: (items) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${alert['name'] ?? 'Alerta'}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text('${market?['canonical_symbol'] ?? '-'}',
                        style: const TextStyle(color: AppTheme.muted)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              const AsyncStatePanel.empty(
                title: 'Nenhum disparo ainda',
                description:
                    'Quando a condição for atingida, o evento aparecerá aqui.',
                icon: Icons.history_rounded,
              )
            else
              for (final event in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AlertEventCard(event: event),
                ),
          ],
        ),
      ),
    );
  }
}

class _AlertEventCard extends StatelessWidget {
  const _AlertEventCard({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.tryParse('${event['triggered_at']}')?.toLocal();
    final status = switch ('${event['notification_status']}') {
      'sent' => 'Notificação enviada',
      'failed' => 'Falha no envio',
      'queued' => 'Na fila',
      _ => 'Pendente',
    };
    return Card(
      child: ListTile(
        minTileHeight: 76,
        leading: const Icon(Icons.bolt_rounded, color: AppTheme.accent),
        title: Text(
          priceText(event['observed_value']),
          style: numericStyle.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(timestamp == null
            ? status
            : '$status · ${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'),
      ),
    );
  }
}

class _AlertDraft {
  const _AlertDraft({
    required this.name,
    required this.marketId,
    required this.conditionType,
    required this.operator,
    required this.value,
    required this.cooldownSeconds,
    this.windowSeconds,
  });

  final String name;
  final String marketId;
  final String conditionType;
  final String operator;
  final String value;
  final int cooldownSeconds;
  final int? windowSeconds;

  Map<String, dynamic> toJson({required String status}) => {
        'market_id': marketId,
        'name': name,
        'status': status,
        'logic': 'AND',
        'cooldown_seconds': cooldownSeconds,
        'conditions': [
          {
            'condition_type': conditionType,
            'operator': operator,
            'value_numeric': value,
            'window_seconds': windowSeconds,
            'position': 0,
          },
        ],
      };
}

class _AlertEditor extends StatefulWidget {
  const _AlertEditor({
    required this.markets,
    required this.conversion,
    this.alert,
    this.initialMarket,
    this.initialPrice,
  });
  final List<Market> markets;
  final CurrencyConversion conversion;
  final Map<String, dynamic>? alert;
  final Market? initialMarket;
  final double? initialPrice;

  @override
  State<_AlertEditor> createState() => _AlertEditorState();
}

class _AlertEditorState extends State<_AlertEditor> {
  late final List<Map<String, dynamic>> _conditions =
      (widget.alert?['conditions'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
  late final Map<String, dynamic>? _condition =
      _conditions.isEmpty ? null : _conditions.first;
  late final TextEditingController _name =
      TextEditingController(text: widget.alert?['name']?.toString() ?? '');
  late final TextEditingController _value = TextEditingController(
    text: _initialValue(),
  );
  late final TextEditingController _cooldown = TextEditingController(
      text: widget.alert?['cooldown_seconds']?.toString() ?? '300');
  late final TextEditingController _window = TextEditingController(
      text: _condition?['window_seconds']?.toString() ?? '3600');
  late String? _marketId =
      (widget.alert?['market'] as Map<String, dynamic>?)?['id']?.toString() ??
          widget.initialMarket?.id;
  late String _type =
      _condition?['condition_type']?.toString() ?? 'PRICE_ABOVE';
  late String _operator = _condition?['operator']?.toString() ?? 'gt';

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _cooldown.dispose();
    _window.dispose();
    super.dispose();
  }

  bool get _requiresWindow => _type.endsWith('_PERCENT');

  String _initialValue() {
    final raw = _condition?['value_numeric'];
    if (raw == null) return widget.initialPrice?.toString() ?? '';
    final type = _condition?['condition_type']?.toString() ?? 'PRICE_ABOVE';
    return type.endsWith('_PERCENT')
        ? '$raw'
        : multiplyCurrency(raw, widget.conversion.rate);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.alert == null ? 'Novo alerta' : 'Editar alerta'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: 'Selecionar mercado',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _selectMarket,
                    child: InputDecorator(
                      isEmpty: _selectedMarket == null,
                      decoration: const InputDecoration(
                        labelText: 'Mercado',
                        suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                      ),
                      child: Text(_selectedMarket?.symbol ?? 'Selecionar'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Avisar quando'),
                  items: const [
                    DropdownMenuItem(
                        value: 'PRICE_ABOVE', child: Text('Subir acima de')),
                    DropdownMenuItem(
                        value: 'PRICE_BELOW', child: Text('Cair abaixo de')),
                    DropdownMenuItem(
                        value: 'PRICE_CHANGE_PERCENT',
                        child: Text('Subir mais de (%)')),
                    DropdownMenuItem(
                        value: 'VOLUME_CHANGE_PERCENT',
                        child: Text('Volume subir mais de (%)')),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? _type),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: _value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        labelText: _requiresWindow
                            ? 'Percentual de variação'
                            : 'Valor em ${widget.conversion.currency.code}')),
                if (_requiresWindow) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: const {'300', '900', '3600', '14400', '86400'}
                            .contains(_window.text)
                        ? _window.text
                        : null,
                    decoration:
                        const InputDecoration(labelText: 'Em quanto tempo'),
                    items: const [
                      DropdownMenuItem(value: '300', child: Text('5 minutos')),
                      DropdownMenuItem(value: '900', child: Text('15 minutos')),
                      DropdownMenuItem(value: '3600', child: Text('1 hora')),
                      DropdownMenuItem(value: '14400', child: Text('4 horas')),
                      DropdownMenuItem(value: '86400', child: Text('24 horas')),
                    ],
                    onChanged: (value) =>
                        setState(() => _window.text = value ?? '3600'),
                  ),
                ],
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8),
                  minTileHeight: 44,
                  title: const Text('Opções avançadas'),
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _operator,
                      decoration: const InputDecoration(labelText: 'Precisão'),
                      items: const [
                        DropdownMenuItem(value: 'gt', child: Text('Maior que')),
                        DropdownMenuItem(
                            value: 'gte', child: Text('Maior ou igual')),
                        DropdownMenuItem(value: 'lt', child: Text('Menor que')),
                        DropdownMenuItem(
                            value: 'lte', child: Text('Menor ou igual')),
                      ],
                      onChanged: (value) =>
                          setState(() => _operator = value ?? _operator),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cooldown,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Intervalo entre avisos (segundos)'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: _save, child: const Text('Salvar')),
        ],
      );

  Market? get _selectedMarket => widget.markets.cast<Market?>().firstWhere(
        (market) => market?.id == _marketId,
        orElse: () => null,
      );

  Future<void> _selectMarket() async {
    final marketId = await showDialog<String>(
      context: context,
      builder: (_) => _MarketPickerDialog(
        markets: widget.markets,
        selectedMarketId: _marketId,
      ),
    );
    if (marketId != null && mounted) {
      setState(() => _marketId = marketId);
    }
  }

  void _save() {
    final marketId = _marketId;
    if (marketId == null ||
        _name.text.trim().isEmpty ||
        double.tryParse(_value.text) == null) {
      return;
    }
    final cooldown = int.tryParse(_cooldown.text) ?? 300;
    final window = _requiresWindow ? int.tryParse(_window.text) : null;
    if (_requiresWindow && (window == null || window < 1)) {
      return;
    }
    final displayValue = double.parse(_value.text);
    final storedValue =
        _requiresWindow ? displayValue : displayValue / widget.conversion.rate;
    Navigator.pop(
      context,
      _AlertDraft(
        name: _name.text.trim(),
        marketId: marketId,
        conditionType: _type,
        operator: _operator,
        value: storedValue.toString(),
        cooldownSeconds: cooldown < 0 ? 0 : cooldown,
        windowSeconds: window,
      ),
    );
  }

  String get _summary {
    final value = _value.text.trim().isEmpty ? '...' : _value.text.trim();
    final market = widget.markets.cast<Market?>().firstWhere(
          (item) => item?.id == _marketId,
          orElse: () => widget.initialMarket,
        );
    final name = market?.displayName ?? 'este ativo';
    return switch (_type) {
      'PRICE_ABOVE' =>
        'Avisar quando $name subir acima de $value ${widget.conversion.currency.code}.',
      'PRICE_BELOW' =>
        'Avisar quando $name cair abaixo de $value ${widget.conversion.currency.code}.',
      'PRICE_CHANGE_PERCENT' =>
        'Avisar quando $name subir mais de $value% em $_windowLabel.',
      'VOLUME_CHANGE_PERCENT' =>
        'Avisar quando o volume de $name subir mais de $value% em $_windowLabel.',
      _ => 'Configure a condição do alerta.',
    };
  }

  String get _windowLabel => switch (_window.text) {
        '300' => '5 minutos',
        '900' => '15 minutos',
        '3600' => '1 hora',
        '14400' => '4 horas',
        '86400' => '24 horas',
        _ => '${_window.text} segundos',
      };
}

class _MarketPickerDialog extends StatefulWidget {
  const _MarketPickerDialog({
    required this.markets,
    required this.selectedMarketId,
  });

  final List<Market> markets;
  final String? selectedMarketId;

  @override
  State<_MarketPickerDialog> createState() => _MarketPickerDialogState();
}

class _MarketPickerDialogState extends State<_MarketPickerDialog> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Market> get _filteredMarkets {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.markets;
    return widget.markets.where((market) {
      final searchable = [
        market.symbol,
        market.displayName,
        market.base,
        market.quote,
        market.providerSymbol,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final markets = _filteredMarkets;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return AlertDialog(
      title: const Text('Selecionar mercado'),
      content: SizedBox(
        width: double.maxFinite,
        height: maxHeight.clamp(280.0, 520.0),
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: 'Buscar mercado',
                hintText: 'Ex.: BTC, Bitcoin ou BTCUSDT',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: markets.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum mercado encontrado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: markets.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final market = markets[index];
                        final selected = market.id == widget.selectedMarketId;
                        return ListTile(
                          selected: selected,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          title: Text(market.symbol),
                          subtitle: Text(market.displayName),
                          trailing:
                              selected ? const Icon(Icons.check_rounded) : null,
                          onTap: () => Navigator.pop(context, market.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
