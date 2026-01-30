class RankingFilters {
  const RankingFilters({
    required this.states,
    required this.cities,
    required this.citiesByState,
    this.updatedAt,
  });

  final List<String> states;
  final List<String> cities;
  final Map<String, List<String>> citiesByState;
  final DateTime? updatedAt;

  factory RankingFilters.fromMap(Map<String, dynamic> data) {
    final rawStates = (data['states'] as List?) ?? const [];
    final rawCities = (data['cities'] as List?) ?? const [];
    final rawCitiesByState = (data['citiesByState'] as Map?) ?? const {};

    final states = rawStates.map((e) => e.toString()).toList()..sort();
    final cities = rawCities.map((e) => e.toString()).toList()..sort();

    final Map<String, List<String>> citiesByState = {};
    for (final entry in rawCitiesByState.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is List) {
        final list = value.map((e) => e.toString()).toList()..sort();
        citiesByState[key] = list;
      }
    }

    DateTime? updatedAt;
    final updatedRaw = data['updatedAt'];
    if (updatedRaw is DateTime) {
      updatedAt = updatedRaw;
    } else if (updatedRaw != null) {
      try {
        updatedAt = (updatedRaw as dynamic).toDate() as DateTime?;
      } catch (_) {}
    }

    return RankingFilters(
      states: states,
      cities: cities,
      citiesByState: citiesByState,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'states': states,
      'cities': cities,
      'citiesByState': citiesByState,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }
}
