class Market {
  const Market({
    required this.id,
    required this.symbol,
    required this.base,
    required this.quote,
    this.name = '',
    this.provider = '',
    this.providerName = '',
    this.providerSymbol = '',
    this.sourceStatus = '',
    this.price,
    this.change24hPercent,
    this.volume24h,
    this.timestamp,
    this.stale,
  });
  final String id;
  final String symbol;
  final String base;
  final String quote;
  final String name;
  final String provider;
  final String providerName;
  final String providerSymbol;
  final String sourceStatus;
  final String? price;
  final String? change24hPercent;
  final String? volume24h;
  final DateTime? timestamp;
  final bool? stale;
  String get displayName => name.isEmpty ? base : name;
  String displaySymbol(String currency) => '$base-$currency';
  String get sourceLabel {
    if (providerName.trim().isNotEmpty) return providerName.trim();
    if (provider.trim().isNotEmpty) return provider.trim();
    return 'Fonte não identificada';
  }

  String get originSymbol =>
      providerSymbol.trim().isNotEmpty ? providerSymbol.trim() : '$base/$quote';

  factory Market.fromJson(Map<String, dynamic> json) {
    final base = json['base_asset'] as Map<String, dynamic>? ?? const {};
    final quote = json['quote_asset'] as Map<String, dynamic>? ?? const {};
    final marketId = json['market_id'] ?? json['id'];
    return Market(
        id: marketId.toString(),
        symbol: '${json['canonical_symbol'] ?? ''}',
        base: '${base['symbol'] ?? json['asset_symbol'] ?? ''}',
        quote: '${quote['symbol'] ?? ''}',
        name: '${base['name'] ?? json['asset_name'] ?? ''}',
        provider: '${json['provider'] ?? ''}',
        providerName: '${json['provider_name'] ?? ''}',
        providerSymbol: '${json['provider_symbol'] ?? ''}',
        sourceStatus: '${json['source_status'] ?? ''}',
        price: json['price']?.toString(),
        change24hPercent: json['change_24h_percent']?.toString(),
        volume24h: json['volume_24h']?.toString(),
        timestamp: DateTime.tryParse('${json['timestamp']}'),
        stale: json['stale'] as bool?);
  }
}

String sourceLabelFor(Market market, [Map<String, dynamic>? quote]) {
  final providerName = '${quote?['provider_name'] ?? ''}'.trim();
  if (providerName.isNotEmpty) return providerName;
  final provider = '${quote?['provider'] ?? ''}'.trim();
  if (provider.isNotEmpty) return provider;
  return market.sourceLabel;
}

String originSymbolFor(Market market, [Map<String, dynamic>? quote]) {
  final providerSymbol = '${quote?['provider_symbol'] ?? ''}'.trim();
  return providerSymbol.isNotEmpty ? providerSymbol : market.originSymbol;
}
