import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http' as http;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AdvancedNavigationMap(),
  ));
}

class PlaceMarker {
  final LatLng position;
  final String name;
  final String category;

  PlaceMarker({
    required this.position,
    required this.name,
    required this.category,
  });
}

class AdvancedNavigationMap extends StatefulWidget {
  const AdvancedNavigationMap({super.key});

  @override
  State<AdvancedNavigationMap> createState() => _AdvancedNavigationMapState();
}

class _AdvancedNavigationMapState extends State<AdvancedNavigationMap> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(6.9271, 79.8612);
  
  double _currentSpeedKmH = 0.0;
  double _currentZoom = 16.5;
  bool _isLoading = true;
  bool _isSearchingPlaces = false;
  bool _showRailways = false;
  
  List<PlaceMarker> _nearbyPlaces = [];
  String _selectedCategory = '';
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStartTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionsAndStartTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    _updateLocationAndSpeed(position);

    setState(() {
      _isLoading = false;
    });

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position newPosition) {
      _updateLocationAndSpeed(newPosition);
    });
  }

  void _updateLocationAndSpeed(Position position) {
    double speedKmH = (position.speed >= 0 ? position.speed : 0) * 3.6;

    double targetZoom = 16.5;
    if (speedKmH < 20.0) {
      targetZoom = 18.0;
    } else if (speedKmH > 50.0) {
      targetZoom = 15.0;
    }

    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _currentSpeedKmH = speedKmH;
      _currentZoom = targetZoom;
    });

    _mapController.move(_currentPosition, targetZoom);
  }

  Future<void> _fetchNearbyData(String queryKey, String queryVal, String categoryName) async {
    setState(() {
      _isSearchingPlaces = true;
      _selectedCategory = categoryName;
      _nearbyPlaces.clear();
    });

    final double lat = _currentPosition.latitude;
    final double lon = _currentPosition.longitude;

    final String query = '''
      [out:json];
      (
        node["$queryKey"="$queryVal"](around:2500, $lat, $lon);
        way["$queryKey"="$queryVal"](around:2500, $lat, $lon);
      );
      out center 40;
    ''';

    final url = Uri.parse('https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List elements = data['elements'];

        List<PlaceMarker> places = [];
        for (var element in elements) {
          double? pLat = element['lat'] ?? element['center']?['lat'];
          double? pLon = element['lon'] ?? element['center']?['lon'];
          String name = element['tags']?['name'] ?? categoryName;

          if (pLat != null && pLon != null) {
            places.add(PlaceMarker(
              position: LatLng(pLat, pLon),
              name: name,
              category: categoryName,
            ));
          }
        }

        setState(() {
          _nearbyPlaces = places;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${places.length} ක් $categoryName හමු විය!'),
            backgroundColor: Colors.green[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ස්ථාන සොයා ගැනීමට අපොහොසත් විය.')),
      );
    } finally {
      setState(() {
        _isSearchingPlaces = false;
      });
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'තෙල් සෙඩ්': return Icons.local_gas_station;
      case 'රෝහල්': return Icons.local_hospital;
      case 'සුපර්මාකට්': return Icons.shopping_cart;
      case 'බැංකු/ATM': return Icons.account_balance;
      case 'බස් නැවතුම්': return Icons.directions_bus;
      case 'කලර් ලයිට්': return Icons.traffic;
      default: return Icons.location_on;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'තෙල් සෙඩ්': return Colors.orange;
      case 'රෝහල්': return Colors.red;
      case 'සුපර්මාකට්': return Colors.purple;
      case 'බැංකු/ATM': return Colors.blue;
      case 'බස් නැවතුම්': return Colors.teal;
      case 'කලර් ලයිට්': return Colors.deepOrange;
      default: return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro Navigation & Speedometer'),
        backgroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: Icon(
              Icons.train,
              color: _showRailways ? Colors.yellow : Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showRailways = !_showRailways;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              _mapController.move(_currentPosition, _currentZoom);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text("GPS Location සම්බන්ධ වෙමින් පවතී..."),
                ],
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition,
                    initialZoom: _currentZoom,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    if (_showRailways)
                      TileLayer(
                        urlTemplate: 'https://a.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.app',
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition,
                          width: 50,
                          height: 50,
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.blueAccent,
                            size: 45,
                          ),
                        ),
                        ..._nearbyPlaces.map((place) => Marker(
                              point: place.position,
                              width: 45,
                              height: 45,
                              child: GestureDetector(
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (ctx) => Container(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        place.name,
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  );
                                },
                                child: Icon(
                                  _getCategoryIcon(place.category),
                                  color: _getCategoryColor(place.category),
                                  size: 36,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterBtn('කලර් ලයිට්', 'highway', 'traffic_signals', Icons.traffic, Colors.deepOrange),
                        _buildFilterBtn('බස් නැවතුම්', 'highway', 'bus_stop', Icons.directions_bus, Colors.teal),
                        _buildFilterBtn('තෙල් සෙඩ්', 'amenity', 'fuel', Icons.local_gas_station, Colors.orange),
                        _buildFilterBtn('බැංකු/ATM', 'amenity', 'bank', Icons.account_balance, Colors.blue),
                        _buildFilterBtn('රෝහල්', 'amenity', 'hospital', Icons.local_hospital, Colors.red),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 15,
                  right: 15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.speed, color: Colors.greenAccent, size: 38),
                            const SizedBox(width: 12),
                            Text(
                              '${_currentSpeedKmH.toStringAsFixed(0)} km/h',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          'Zoom: ${_currentZoom.toStringAsFixed(1)}x',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBtn(String label, String key, String val, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        onPressed: () => _fetchNearbyData(key, val, label),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
