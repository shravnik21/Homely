import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/place.dart';
import '../services/auth_service.dart';
import '../services/places_service.dart';
import '../widgets/place_card.dart';
import 'auth/login_screen.dart';
import 'place_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final PlacesService _placesService = PlacesService();

  // Holds the network call itself - a Future. We store it in state
  // (not call getPlaces() directly in build()) so it only fires ONCE
  // when the screen loads, not on every rebuild.
  late Future<List<Place>> _placesFuture;

  // The full list once loaded, kept separately so the search bar can
  // filter it locally without hitting the database again per keystroke.
  List<Place> _allPlaces = [];
  List<Place> _filteredPlaces = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // initState runs once when the widget is first inserted into the
    // tree - this is the correct place to kick off a one-time fetch.
    _placesFuture = _placesService.getPlaces();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredPlaces = query.isEmpty
          ? _allPlaces
          : _allPlaces.where((p) {
              return p.title.toLowerCase().contains(query) ||
                  p.cityName.toLowerCase().contains(query) ||
                  p.address.toLowerCase().contains(query) ||
                  p.type.toLowerCase().contains(query);
            }).toList();
    });
  }

  String get _displayName {
    // full_name was stored as user metadata during signup
    // (see AuthService.signUp -> data: {'full_name': fullName}).
    // Reading it here avoids a second DB query just to greet the user.
    final meta = _authService.currentUser?.userMetadata;
    final name = meta?['full_name'] as String?;
    if (name == null || name.trim().isEmpty) return 'there';
    return name.trim().split(' ').first; // first name only
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(child: _buildPlacesList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome back 👋',
                style: TextStyle(color: Color.fromARGB(255, 240, 36, 36), fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                _displayName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: _logout,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.logout, color: Color.fromARGB(255, 240, 36, 36), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: TextField(
          controller: _searchController,
          decoration:const InputDecoration(
            hintText: 'Search by city, place or type...',
            hintStyle: TextStyle(color: AppColors.grey, fontSize: 14),
            prefixIcon:  Icon(Icons.search, color: AppColors.grey),
            border: InputBorder.none,
            filled: false,
            contentPadding:  EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildPlacesList() {
    return FutureBuilder<List<Place>>(
      future: _placesFuture,
      builder: (context, snapshot) {
        // 1. Still waiting on the network call
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // 2. Network call failed (no internet, RLS blocking, etc.)
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load places.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          );
        }

        // 3. Success - populate _allPlaces once (first successful build)
        final places = snapshot.data ?? [];
        if (_allPlaces.isEmpty && places.isNotEmpty) {
          _allPlaces = places;
          _filteredPlaces = places;
        }

        if (_filteredPlaces.isEmpty) {
          return const Center(
            child: Text('No places found.',
                style: TextStyle(color: AppColors.grey)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: _filteredPlaces.length,
          itemBuilder: (context, index) {
            final place = _filteredPlaces[index];
            return PlaceCard(
              place: place,
              onTap: () {
                // Passing the Place object directly - no second DB call
                // needed, since Home already fetched it with all images
                // and amenities in the initial getPlaces() request.
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaceDetailScreen(place: place),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
