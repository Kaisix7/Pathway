import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  static const LatLng _kazakhstanCenter = LatLng(48.0196, 66.9237);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  bool _isSearching = false;
  List<_PlaceSearchResult> _results = const [];
  _PlaceSearchResult? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchTextChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_handleSearchTextChange);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchTextChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _searchPlaces(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _results = const [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': '$trimmedQuery, Kazakhstan',
          'format': 'jsonv2',
          'limit': '5',
          'countrycodes': 'kz',
          'addressdetails': '1',
        },
      );

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'pathway-flutter-app/1.0 (map search)',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Search failed with code ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as List<dynamic>;
      final places = decoded
          .map((item) => _PlaceSearchResult.fromJson(item as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _results = places;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _isSearching = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Place search is temporarily unavailable')),
      );
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _searchPlaces(value);
    });
  }

  void _selectPlace(_PlaceSearchResult place) {
    FocusScope.of(context).unfocus();

    setState(() {
      _selectedPlace = place;
      _searchController.text = place.title;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
      _results = const [];
    });

    _mapController.move(place.location, 13);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map View')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search places in Kazakhstan',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _debounce?.cancel();
                            _searchController.clear();
                            setState(() {
                              _results = const [];
                              _selectedPlace = null;
                            });
                            _mapController.move(_kazakhstanCenter, 4.8);
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _searchPlaces,
              ),
              const SizedBox(height: 12),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_results.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = _results[index];
                      return ListTile(
                        title: Text(
                          place.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          place.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPlace(place),
                      );
                    },
                  ),
                ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: _kazakhstanCenter,
                      initialZoom: 4.8,
                      minZoom: 3,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.my_app',
                      ),
                      MarkerLayer(
                        markers: [
                          if (_selectedPlace != null)
                            Marker(
                              point: _selectedPlace!.location,
                              width: 44,
                              height: 44,
                              child: const Icon(
                                Icons.location_on,
                                size: 44,
                                color: Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceSearchResult {
  const _PlaceSearchResult({
    required this.title,
    required this.subtitle,
    required this.location,
  });

  final String title;
  final String subtitle;
  final LatLng location;

  factory _PlaceSearchResult.fromJson(Map<String, dynamic> json) {
    final displayName = (json['display_name'] as String? ?? '').trim();
    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    final title = parts.isNotEmpty ? parts.first : 'Unknown place';
    final subtitle = parts.length > 1
        ? parts.skip(1).join(', ')
        : 'Kazakhstan';

    return _PlaceSearchResult(
      title: title,
      subtitle: subtitle,
      location: LatLng(
        double.parse(json['lat'] as String),
        double.parse(json['lon'] as String),
      ),
    );
  }
}
