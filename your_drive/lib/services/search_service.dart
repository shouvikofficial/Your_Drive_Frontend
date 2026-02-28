import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Holds one set of search filter options.
class SearchFilters {
  final Set<String> types; // 'image', 'video', 'music', 'document'
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? minSizeBytes;
  final int? maxSizeBytes;
  final String sortBy; // 'name', 'created_at', 'size'
  final bool ascending;

  const SearchFilters({
    this.types = const {},
    this.dateFrom,
    this.dateTo,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.sortBy = 'created_at',
    this.ascending = false,
  });

  SearchFilters copyWith({
    Set<String>? types,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? minSizeBytes,
    int? maxSizeBytes,
    String? sortBy,
    bool? ascending,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearMinSize = false,
    bool clearMaxSize = false,
  }) {
    return SearchFilters(
      types: types ?? this.types,
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      minSizeBytes: clearMinSize ? null : (minSizeBytes ?? this.minSizeBytes),
      maxSizeBytes: clearMaxSize ? null : (maxSizeBytes ?? this.maxSizeBytes),
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
    );
  }

  bool get hasActiveFilters =>
      types.isNotEmpty ||
      dateFrom != null ||
      dateTo != null ||
      minSizeBytes != null ||
      maxSizeBytes != null;
}

/// Service that handles search queries against Supabase and manages recent searches.
class SearchService {
  static const _recentKey = 'recent_searches';
  static const int _maxRecent = 10;

  // ─── Recent searches (persisted) ───────────────────────────────

  static Future<List<String>> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? [];
  }

  static Future<void> addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? [];
    list.remove(query);
    list.insert(0, query);
    if (list.length > _maxRecent) list.removeLast();
    await prefs.setStringList(_recentKey, list);
  }

  static Future<void> removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? [];
    list.remove(query);
    await prefs.setStringList(_recentKey, list);
  }

  static Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
  }

  // ─── Search query ─────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> search({
    required String query,
    SearchFilters filters = const SearchFilters(),
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    var q = supabase
        .from('files')
        .select()
        .eq('user_id', user.id);

    // ── Full-text filter (case-insensitive ILIKE) ──
    if (query.trim().isNotEmpty) {
      q = q.ilike('name', '%${query.trim()}%');
    }

    // ── Type filter ──
    if (filters.types.isNotEmpty) {
      q = q.inFilter('type', filters.types.toList());
    }

    // ── Date range ──
    if (filters.dateFrom != null) {
      q = q.gte('created_at', filters.dateFrom!.toIso8601String());
    }
    if (filters.dateTo != null) {
      // Include the entire end-day
      final endOfDay = DateTime(
        filters.dateTo!.year,
        filters.dateTo!.month,
        filters.dateTo!.day,
        23, 59, 59,
      );
      q = q.lte('created_at', endOfDay.toIso8601String());
    }

    // ── Size range ──
    if (filters.minSizeBytes != null) {
      q = q.gte('size', filters.minSizeBytes!);
    }
    if (filters.maxSizeBytes != null) {
      q = q.lte('size', filters.maxSizeBytes!);
    }

    // ── Sort & Execute ──
    final response = await q.order(filters.sortBy, ascending: filters.ascending);
    return List<Map<String, dynamic>>.from(response);
  }

  // ─── Quick suggestions (top N name matches) ───────────────────

  static Future<List<String>> suggestions(String query) async {
    if (query.trim().isEmpty) return [];

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final response = await supabase
        .from('files')
        .select('name')
        .eq('user_id', user.id)
        .ilike('name', '%${query.trim()}%')
        .order('created_at', ascending: false)
        .limit(6);

    return List<Map<String, dynamic>>.from(response)
        .map((e) => e['name'] as String)
        .toSet()
        .toList();
  }
}
