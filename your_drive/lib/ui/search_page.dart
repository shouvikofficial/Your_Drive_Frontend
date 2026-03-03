import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

import '../theme/app_colors.dart';
import '../config/env.dart';
import '../services/search_service.dart';
import '../services/file_service.dart';
import '../services/download_service.dart';
import '../services/vault_service.dart';
import '../services/thumbnail_cache_service.dart';
import 'file_viewer_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  List<String> _suggestions = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _showSuggestions = true;
  bool _isGridView = false;

  SearchFilters _filters = const SearchFilters();

  // Animation for the filter panel
  late AnimationController _filterAnimController;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _filterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadRecentSearches();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _filterAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final recent = await SearchService.getRecentSearches();
    if (mounted) setState(() => _recentSearches = recent);
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = true;
        _hasSearched = false;
        _results = [];
      });
      return;
    }

    setState(() => _showSuggestions = true);

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      // Fetch suggestions
      final suggestions = await SearchService.suggestions(query);
      if (mounted) setState(() => _suggestions = suggestions);
    });
  }

  Future<void> _executeSearch(String query) async {
    if (query.trim().isEmpty && !_filters.hasActiveFilters) return;

    _focusNode.unfocus();
    setState(() {
      _isSearching = true;
      _showSuggestions = false;
      _hasSearched = true;
    });

    if (query.trim().isNotEmpty) {
      await SearchService.addRecentSearch(query.trim());
      _loadRecentSearches();
    }

    try {
      final results = await SearchService.search(
        query: query,
        filters: _filters,
      );
      if (mounted) setState(() => _results = results);
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _pickSuggestion(String suggestion) {
    _controller.text = suggestion;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
    _executeSearch(suggestion);
  }

  void _toggleFilters() {
    setState(() => _showFilters = !_showFilters);
    if (_showFilters) {
      _filterAnimController.forward();
    } else {
      _filterAnimController.reverse();
    }
  }

  void _toggleTypeFilter(String type) {
    final current = Set<String>.from(_filters.types);
    if (current.contains(type)) {
      current.remove(type);
    } else {
      current.add(type);
    }
    setState(() => _filters = _filters.copyWith(types: current));
    _executeSearch(_controller.text);
  }

  void _setSortBy(String field, bool ascending) {
    setState(() => _filters = _filters.copyWith(sortBy: field, ascending: ascending));
    _executeSearch(_controller.text);
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filters.dateFrom ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.blue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _filters = _filters.copyWith(dateFrom: picked));
      _executeSearch(_controller.text);
    }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filters.dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.blue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _filters = _filters.copyWith(dateTo: picked));
      _executeSearch(_controller.text);
    }
  }

  void _clearAllFilters() {
    setState(() => _filters = const SearchFilters());
    _executeSearch(_controller.text);
  }

  // ─── Thumbnail helpers (same as files_page) ───────────────────
  Future<Uint8List?> _getCachedThumbnail(Map<String, dynamic> file) {
    return ThumbnailCacheService.instance.get(
      file['id'],
      () => _getThumbnail(file),
    );
  }

  Future<Uint8List?> _getThumbnail(Map<String, dynamic> file) async {
    try {
      if (file['thumbnail_id'] == null) return null;

      final String? thumbIvBase64 = file['thumbnail_iv'] as String? ??
          await _fetchThumbnailIv(file['message_id']);

      if (thumbIvBase64 == null) return null;

      final url = "${Env.backendBaseUrl}/api/thumbnail/${file['thumbnail_id']}";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final encryptedBytes = response.bodyBytes;
      final secretKey = await VaultService().getSecretKey();
      final algorithm = AesGcm.with256bits();
      final nonce = base64Decode(thumbIvBase64);

      final macBytes = encryptedBytes.sublist(encryptedBytes.length - 16);
      final cipherText = encryptedBytes.sublist(0, encryptedBytes.length - 16);

      final decrypted = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );

      return Uint8List.fromList(decrypted);
    } catch (e) {
      debugPrint("Thumbnail error: $e");
      return null;
    }
  }

  Future<String?> _fetchThumbnailIv(dynamic messageId) async {
    final meta = await Supabase.instance.client
        .from('files')
        .select('thumbnail_iv')
        .eq('message_id', messageId)
        .maybeSingle();
    return meta?['thumbnail_iv'] as String?;
  }

  // ──────────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            if (_showFilters) _buildFilterPanel(),
            if (_filters.hasActiveFilters) _buildActiveFilterChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ─── Search header bar ────────────────────────────────────────
  Widget _buildSearchHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onQueryChanged,
              onSubmitted: _executeSearch,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search in Drive',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
                _focusNode.requestFocus();
              },
            ),
          // Filter toggle button
          AnimatedBuilder(
            animation: _filterAnimController,
            builder: (context, child) => IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    color: _showFilters || _filters.hasActiveFilters
                        ? AppColors.blue
                        : Colors.grey[600],
                  ),
                  if (_filters.hasActiveFilters)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: _toggleFilters,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ─── Filter panel ─────────────────────────────────────────────
  Widget _buildFilterPanel() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Type filters ──
            Text('Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip('image', Icons.image_rounded, 'Photos', AppColors.blue),
                _buildTypeChip('video', Icons.videocam_rounded, 'Videos', AppColors.purple),
                _buildTypeChip('music', Icons.music_note_rounded, 'Music', AppColors.green),
                _buildTypeChip('document', Icons.description_rounded, 'Documents', Colors.teal),
              ],
            ),

            const SizedBox(height: 16),

            // ── Date range ──
            Text('Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildDateButton('From', _filters.dateFrom, _pickDateFrom, () {
                  setState(() => _filters = _filters.copyWith(clearDateFrom: true));
                  _executeSearch(_controller.text);
                })),
                const SizedBox(width: 12),
                Expanded(child: _buildDateButton('To', _filters.dateTo, _pickDateTo, () {
                  setState(() => _filters = _filters.copyWith(clearDateTo: true));
                  _executeSearch(_controller.text);
                })),
              ],
            ),

            const SizedBox(height: 16),

            // ── Size presets ──
            Text('Size', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSizeChip('< 1 MB', null, 1024 * 1024),
                _buildSizeChip('1-10 MB', 1024 * 1024, 10 * 1024 * 1024),
                _buildSizeChip('10-100 MB', 10 * 1024 * 1024, 100 * 1024 * 1024),
                _buildSizeChip('> 100 MB', 100 * 1024 * 1024, null),
              ],
            ),

            const SizedBox(height: 16),

            // ── Sort ──
            Text('Sort by', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSortChip('Date', 'created_at'),
                _buildSortChip('Name', 'name'),
                _buildSortChip('Size', 'size'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, IconData icon, String label, Color color) {
    final selected = _filters.types.contains(type);
    return FilterChip(
      avatar: Icon(icon, size: 16, color: selected ? Colors.white : color),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      selected: selected,
      selectedColor: color,
      backgroundColor: color.withOpacity(0.08),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? color : color.withOpacity(0.2)),
      ),
      onSelected: (_) => _toggleTypeFilter(type),
    );
  }

  Widget _buildDateButton(String label, DateTime? date, VoidCallback onTap, VoidCallback onClear) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: date != null ? AppColors.blue.withOpacity(0.08) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: date != null ? AppColors.blue.withOpacity(0.3) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 14,
                color: date != null ? AppColors.blue : Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date != null ? _formatShortDate(date) : label,
                style: TextStyle(
                  fontSize: 13,
                  color: date != null ? AppColors.blue : Colors.grey[500],
                  fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: AppColors.blue.withOpacity(0.6)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeChip(String label, int? min, int? max) {
    final selected = _filters.minSizeBytes == min && _filters.maxSizeBytes == max;
    return ChoiceChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: selected ? Colors.white : Colors.grey[700],
      )),
      selected: selected,
      selectedColor: AppColors.blue,
      backgroundColor: Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.blue : Colors.grey[300]!),
      ),
      onSelected: (_) {
        if (selected) {
          setState(() => _filters = _filters.copyWith(
            clearMinSize: true,
            clearMaxSize: true,
          ));
        } else {
          setState(() => _filters = _filters.copyWith(
            minSizeBytes: min,
            maxSizeBytes: max,
            clearMinSize: min == null,
            clearMaxSize: max == null,
          ));
        }
        _executeSearch(_controller.text);
      },
    );
  }

  Widget _buildSortChip(String label, String field) {
    final isActive = _filters.sortBy == field;
    return GestureDetector(
      onTap: () {
        if (isActive) {
          _setSortBy(field, !_filters.ascending);
        } else {
          _setSortBy(field, field == 'name');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.blue : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.blue : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : Colors.grey[700],
            )),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                _filters.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Active filter chips strip ────────────────────────────────
  Widget _buildActiveFilterChips() {
    if (!_filters.hasActiveFilters) return const SizedBox.shrink();

    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (_filters.types.isNotEmpty)
            for (final type in _filters.types)
              _activeChip(
                label: _typeLabel(type),
                onRemove: () => _toggleTypeFilter(type),
              ),
          if (_filters.dateFrom != null)
            _activeChip(
              label: 'From: ${_formatShortDate(_filters.dateFrom!)}',
              onRemove: () {
                setState(() => _filters = _filters.copyWith(clearDateFrom: true));
                _executeSearch(_controller.text);
              },
            ),
          if (_filters.dateTo != null)
            _activeChip(
              label: 'To: ${_formatShortDate(_filters.dateTo!)}',
              onRemove: () {
                setState(() => _filters = _filters.copyWith(clearDateTo: true));
                _executeSearch(_controller.text);
              },
            ),
          if (_filters.minSizeBytes != null || _filters.maxSizeBytes != null)
            _activeChip(
              label: _sizeLabel(),
              onRemove: () {
                setState(() => _filters = _filters.copyWith(clearMinSize: true, clearMaxSize: true));
                _executeSearch(_controller.text);
              },
            ),
          // Clear all
          GestureDetector(
            onTap: _clearAllFilters,
            child: Container(
              margin: const EdgeInsets.only(left: 4, right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.clear_all, size: 14, color: Colors.red),
                  SizedBox(width: 4),
                  Text('Clear all', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeChip({required String label, required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.blue, fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: AppColors.blue.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }

  // ─── Body content ─────────────────────────────────────────────
  Widget _buildBody() {
    // Show loading
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: AppColors.blue));
    }

    // No query yet → show recent searches & quick type buttons
    if (!_hasSearched && _controller.text.trim().isEmpty) {
      return _buildInitialView();
    }

    // Show suggestions overlay when typing
    if (_showSuggestions && _suggestions.isNotEmpty && !_hasSearched) {
      return _buildSuggestionsView();
    }

    // Search executed but no results
    if (_hasSearched && _results.isEmpty) {
      return _buildNoResults();
    }

    // Show results
    return _buildResultsView();
  }

  // ─── Initial view (recent searches + quick actions) ───────────
  Widget _buildInitialView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent searches', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600],
              )),
              TextButton(
                onPressed: () async {
                  await SearchService.clearRecentSearches();
                  _loadRecentSearches();
                },
                child: const Text('Clear all', style: TextStyle(fontSize: 12, color: AppColors.blue)),
              ),
            ],
          ),
          ..._recentSearches.map((query) => ListTile(
            dense: true,
            leading: Icon(Icons.history, color: Colors.grey[400], size: 20),
            title: Text(query, style: const TextStyle(fontSize: 14)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Insert into search bar
                IconButton(
                  icon: Icon(Icons.north_west, size: 16, color: Colors.grey[400]),
                  onPressed: () {
                    _controller.text = query;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: query.length),
                    );
                    _onQueryChanged(query);
                  },
                ),
                // Remove from recent
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                  onPressed: () async {
                    await SearchService.removeRecentSearch(query);
                    _loadRecentSearches();
                  },
                ),
              ],
            ),
            onTap: () => _pickSuggestion(query),
          )),
        ],

        const SizedBox(height: 24),

        // Quick type shortcuts
        Text('Browse by type', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600],
        )),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _quickTypeButton(Icons.image_rounded, 'Photos', AppColors.blue, 'image'),
            _quickTypeButton(Icons.videocam_rounded, 'Videos', AppColors.purple, 'video'),
            _quickTypeButton(Icons.music_note_rounded, 'Music', AppColors.green, 'music'),
            _quickTypeButton(Icons.description_rounded, 'Docs', Colors.teal, 'document'),
          ],
        ),

        const SizedBox(height: 24),

        // Quick time shortcuts
        Text('Modified', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600],
        )),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _quickDateChip('Today', DateTime.now(), DateTime.now()),
            _quickDateChip('This week', DateTime.now().subtract(const Duration(days: 7)), DateTime.now()),
            _quickDateChip('This month', DateTime.now().subtract(const Duration(days: 30)), DateTime.now()),
            _quickDateChip('This year', DateTime(DateTime.now().year), DateTime.now()),
          ],
        ),
      ],
    );
  }

  Widget _quickTypeButton(IconData icon, String label, Color color, String type) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _filters = _filters.copyWith(types: {type});
        });
        _executeSearch('');
      },
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _quickDateChip(String label, DateTime from, DateTime to) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      onPressed: () {
        setState(() {
          _filters = _filters.copyWith(dateFrom: from, dateTo: to);
        });
        _executeSearch('');
      },
    );
  }

  // ─── Suggestions view ─────────────────────────────────────────
  Widget _buildSuggestionsView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        final query = _controller.text.toLowerCase();
        final matchStart = suggestion.toLowerCase().indexOf(query);

        return ListTile(
          dense: true,
          leading: const Icon(Icons.search, color: Colors.grey, size: 20),
          title: matchStart >= 0
              ? _highlightMatch(suggestion, matchStart, query.length)
              : Text(suggestion, style: const TextStyle(fontSize: 14)),
          trailing: IconButton(
            icon: Icon(Icons.north_west, size: 16, color: Colors.grey[400]),
            onPressed: () {
              _controller.text = suggestion;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: suggestion.length),
              );
              _onQueryChanged(suggestion);
            },
          ),
          onTap: () => _pickSuggestion(suggestion),
        );
      },
    );
  }

  Widget _highlightMatch(String text, int start, int length) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, start + length),
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.blue),
          ),
          if (start + length < text.length)
            TextSpan(text: text.substring(start + length)),
        ],
      ),
    );
  }

  // ─── No results ───────────────────────────────────────────────
  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            _controller.text.isNotEmpty
                ? 'Try different keywords or adjust filters'
                : 'No files match the selected filters',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
          if (_filters.hasActiveFilters) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Clear filters'),
              style: TextButton.styleFrom(foregroundColor: AppColors.blue),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Results view ─────────────────────────────────────────────
  Widget _buildResultsView() {
    return Column(
      children: [
        // Result count + toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              Text(
                '${_results.length} result${_results.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _isGridView ? Icons.list_rounded : Icons.grid_view_rounded,
                  color: Colors.grey[600],
                  size: 20,
                ),
                onPressed: () => setState(() => _isGridView = !_isGridView),
              ),
            ],
          ),
        ),

        // Results
        Expanded(
          child: _isGridView ? _buildResultGrid() : _buildResultList(),
        ),
      ],
    );
  }

  Widget _buildResultGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final file = _results[index];
        return _SearchResultCard(
          file: file,
          query: _controller.text,
          onTap: () => _openViewer(file),
          onMore: () => _showOptions(file),
          getThumbnail: _getCachedThumbnail,
        );
      },
    );
  }

  Widget _buildResultList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final file = _results[index];
        return _SearchResultListItem(
          file: file,
          query: _controller.text,
          onTap: () => _openViewer(file),
          onMore: () => _showOptions(file),
          getThumbnail: _getCachedThumbnail,
        );
      },
    );
  }

  // ─── Actions ──────────────────────────────────────────────────
  void _openViewer(Map<String, dynamic> file) {
    final index = _results.indexOf(file);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileViewerPage(
          files: _results,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    ).then((result) {
      if (result == true) _executeSearch(_controller.text);
    });
  }

  void _showOptions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _FileIcon(type: file['type'] ?? '', size: 28, fileName: file['name']),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (file['size'] != null)
                        Text(_formatSize(file['size']),
                            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text("Open"),
            onTap: () { Navigator.pop(context); _openViewer(file); },
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text("Download"),
            onTap: () {
              Navigator.pop(context);
              _downloadFile(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text("Delete", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _deleteFile(file);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(child: Text("Downloading ${file['name']}...")),
        ]),
        duration: const Duration(days: 1),
      ),
    );
    try {
      final savePath = await DownloadService.downloadFile(
        file['message_id'].toString(), file['name'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final isGallery = savePath.startsWith("Gallery/");
      final displayName = savePath.split('/').last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Icon(isGallery ? Icons.photo_library_rounded : Icons.download_done_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(isGallery ? "Saved to Gallery: $displayName" : "Saved to Downloads: $displayName")),
          ]),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Download failed: ${e.toString().replaceAll('Exception: ', '')}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete file?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ThumbnailCacheService.instance.evict(file['id']);
      await FileService().deleteFile(
        messageId: file['message_id'],
        supabaseId: file['id'],
        onSuccess: (_) => _executeSearch(_controller.text),
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e), backgroundColor: Colors.red),
            );
          }
        },
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────
  String _formatShortDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'image': return 'Photos';
      case 'video': return 'Videos';
      case 'music': return 'Music';
      case 'document': return 'Docs';
      default: return type;
    }
  }

  String _sizeLabel() {
    if (_filters.minSizeBytes == null) return '< ${_formatSize(_filters.maxSizeBytes)}';
    if (_filters.maxSizeBytes == null) return '> ${_formatSize(_filters.minSizeBytes)}';
    return '${_formatSize(_filters.minSizeBytes)} - ${_formatSize(_filters.maxSizeBytes)}';
  }

  static String _formatSize(dynamic bytes) {
    if (bytes == null) return '';
    final int b = bytes is int ? bytes : int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ─── Search Result Card (grid view) ─────────────────────────────

class _SearchResultCard extends StatefulWidget {
  final Map<String, dynamic> file;
  final String query;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final Future<Uint8List?> Function(Map<String, dynamic>) getThumbnail;

  const _SearchResultCard({
    required this.file,
    required this.query,
    required this.onTap,
    required this.onMore,
    required this.getThumbnail,
  });

  @override
  State<_SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<_SearchResultCard> {
  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = widget.getThumbnail(widget.file);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<Uint8List?>(
                future: _thumbnailFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: Image.memory(snapshot.data!, fit: BoxFit.cover, width: double.infinity),
                    );
                  }
                  return Center(child: _FileIcon(type: widget.file['type'] ?? '', size: 42, fileName: widget.file['name']));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 2, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _highlightName(widget.file['name'] ?? '', widget.query),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                    onPressed: widget.onMore,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlightName(String name, String query) {
    if (query.isEmpty) {
      return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13));
    }

    final lower = name.toLowerCase();
    final qLower = query.toLowerCase();
    final idx = lower.indexOf(qLower);

    if (idx < 0) {
      return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13));
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
        children: [
          if (idx > 0) TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + query.length),
            style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w800),
          ),
          if (idx + query.length < name.length)
            TextSpan(text: name.substring(idx + query.length)),
        ],
      ),
    );
  }
}

// ─── Search Result List Item ────────────────────────────────────

class _SearchResultListItem extends StatefulWidget {
  final Map<String, dynamic> file;
  final String query;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final Future<Uint8List?> Function(Map<String, dynamic>) getThumbnail;

  const _SearchResultListItem({
    required this.file,
    required this.query,
    required this.onTap,
    required this.onMore,
    required this.getThumbnail,
  });

  @override
  State<_SearchResultListItem> createState() => _SearchResultListItemState();
}

class _SearchResultListItemState extends State<_SearchResultListItem> {
  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = widget.getThumbnail(widget.file);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: widget.onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 50,
            height: 50,
            child: FutureBuilder<Uint8List?>(
              future: _thumbnailFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    color: Colors.grey[100],
                    child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover, width: 50, height: 50);
                }
                return Container(
                  color: Colors.grey[100],
                  child: Center(child: _FileIcon(type: file['type'] ?? '', size: 24, fileName: file['name'])),
                );
              },
            ),
          ),
        ),
        title: _highlightName(file['name'] ?? '', widget.query),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _typeColor(file['type'] ?? '').withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  (file['type'] ?? '').toString().toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _typeColor(file['type'] ?? '')),
                ),
              ),
              if (file['size'] != null) ...[
                const SizedBox(width: 8),
                Text(_SearchPageState._formatSize(file['size']),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
              const SizedBox(width: 8),
              if (file['created_at'] != null)
                Text(_formatDate(file['created_at']),
                    style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
          onPressed: widget.onMore,
        ),
      ),
    );
  }

  Widget _highlightName(String name, String query) {
    if (query.isEmpty) {
      return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14));
    }

    final lower = name.toLowerCase();
    final qLower = query.toLowerCase();
    final idx = lower.indexOf(qLower);

    if (idx < 0) {
      return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14));
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
        children: [
          if (idx > 0) TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + query.length),
            style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w800),
          ),
          if (idx + query.length < name.length)
            TextSpan(text: name.substring(idx + query.length)),
        ],
      ),
    );
  }

  static String _formatDate(dynamic isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate.toString()).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return '';
    }
  }

  static Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'image': return AppColors.blue;
      case 'video': return Colors.purple;
      case 'music': return Colors.orange;
      case 'document': return Colors.teal;
      default: return Colors.grey;
    }
  }
}

// ─── Shared FileIcon widget ─────────────────────────────────────

class _FileIcon extends StatelessWidget {
  final String type;
  final double size;
  final String? fileName;

  const _FileIcon({required this.type, required this.size, this.fileName});

  @override
  Widget build(BuildContext context) {
    switch (type.toLowerCase()) {
      case 'image':
        return Icon(Icons.image_rounded, size: size, color: AppColors.blue);
      case 'video':
        return Icon(Icons.play_circle_filled_rounded, size: size, color: Colors.purple);
      case 'music':
        return Icon(Icons.music_note_rounded, size: size, color: Colors.orange);
      case 'document':
        return _buildDocIcon();
      default:
        return Icon(Icons.insert_drive_file_rounded, size: size, color: Colors.grey[600]);
    }
  }

  Widget _buildDocIcon() {
    final ext = _extFromName(fileName);
    final info = _docInfo(ext);

    if (info.label != null) {
      final badgeSize = size * 1.1;
      final fontSize = (size * 0.28).clamp(8.0, 16.0);
      final radius = size * 0.18;

      return SizedBox(
        width: badgeSize,
        height: badgeSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.insert_drive_file, size: size, color: Colors.grey[300]),
            Positioned(
              bottom: size * 0.05,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size * 0.1,
                  vertical: size * 0.04,
                ),
                decoration: BoxDecoration(
                  color: info.color,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Text(
                  info.label!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Icon(info.icon, size: size, color: info.color);
  }

  static String _extFromName(String? name) {
    if (name == null || !name.contains('.')) return '';
    return name.split('.').last.toLowerCase();
  }

  static _DocInfo _docInfo(String ext) {
    switch (ext) {
      case 'pdf':
        return _DocInfo(label: 'PDF', color: const Color(0xFFE53935), icon: Icons.picture_as_pdf_rounded);
      case 'doc':
      case 'docx':
        return _DocInfo(label: 'DOC', color: const Color(0xFF2B579A), icon: Icons.description_rounded);
      case 'xls':
      case 'xlsx':
        return _DocInfo(label: 'XLS', color: const Color(0xFF217346), icon: Icons.table_chart_rounded);
      case 'csv':
        return _DocInfo(label: 'CSV', color: const Color(0xFF217346), icon: Icons.table_chart_rounded);
      case 'ppt':
      case 'pptx':
        return _DocInfo(label: 'PPT', color: const Color(0xFFD24726), icon: Icons.slideshow_rounded);
      case 'txt':
        return _DocInfo(label: 'TXT', color: Colors.blueGrey, icon: Icons.article_rounded);
      case 'log':
        return _DocInfo(label: 'LOG', color: Colors.blueGrey, icon: Icons.article_rounded);
      case 'zip':
        return _DocInfo(label: 'ZIP', color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case 'rar':
        return _DocInfo(label: 'RAR', color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case '7z':
        return _DocInfo(label: '7Z', color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case 'tar':
      case 'gz':
        return _DocInfo(label: ext.toUpperCase(), color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case 'html':
      case 'htm':
        return _DocInfo(label: 'HTML', color: const Color(0xFFE44D26), icon: Icons.code_rounded);
      case 'css':
        return _DocInfo(label: 'CSS', color: const Color(0xFF264DE4), icon: Icons.code_rounded);
      case 'js':
        return _DocInfo(label: 'JS', color: const Color(0xFFF7DF1E), icon: Icons.code_rounded);
      case 'json':
        return _DocInfo(label: 'JSON', color: Colors.indigo, icon: Icons.code_rounded);
      case 'xml':
        return _DocInfo(label: 'XML', color: Colors.indigo, icon: Icons.code_rounded);
      case 'apk':
        return _DocInfo(label: 'APK', color: const Color(0xFF3DDC84), icon: Icons.android_rounded);
      case 'exe':
        return _DocInfo(label: 'EXE', color: Colors.blueGrey, icon: Icons.desktop_windows_rounded);
      case 'msi':
        return _DocInfo(label: 'MSI', color: Colors.blueGrey, icon: Icons.desktop_windows_rounded);
      default:
        return _DocInfo(label: null, color: Colors.teal, icon: Icons.description_rounded);
    }
  }
}

class _DocInfo {
  final String? label;
  final Color color;
  final IconData icon;
  const _DocInfo({required this.label, required this.color, required this.icon});
}
