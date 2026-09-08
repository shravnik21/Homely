import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/screens/host/listing_constants.dart';
import 'package:homely_app/services/auth_service.dart';
import 'package:homely_app/services/places_service.dart';
import 'package:homely_app/services/wishlist_service.dart';
import 'package:homely_app/utils/auto_reload_on_reconnect.dart';
import 'package:homely_app/utils/network_retry.dart';
import 'package:homely_app/widgets/place_card.dart';
import 'package:homely_app/widgets/error_state_view.dart';
import 'place_detail_screen.dart';
import 'wishlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutoReloadOnReconnectMixin {
  final AuthService _authService = AuthService();
  final PlacesService _placesService = PlacesService();
  final WishlistService _wishlistService = WishlistService();

  // Which place ids are currently saved, so PlaceCard knows which
  // hearts to render filled. Loaded once alongside the places list;
  // toggling a heart updates this set locally (no full refetch).
  Set<String> _wishlistedIds = {};

  // Holds the network call itself - a Future. We store it in state
  // (not call getPlaces() directly in build()) so it only fires ONCE
  // when the screen loads, not on every rebuild.
  late Future<List<Place>> _placesFuture;

  // The full list once loaded, kept separately so the search bar can
  // filter it locally without hitting the database again per keystroke.
  List<Place> _allPlaces = [];
  List<Place> _filteredPlaces = [];
  final TextEditingController _searchController = TextEditingController();

  // Pills below the search bar filter by property type. Multiple pills
  // can be active at once - a listing matches if its type is in this
  // set (OR), or if the set is empty (nothing selected = show all).
  // Built from kPropertyTypes (the same list hosts pick from when
  // creating a listing) so every pill is guaranteed to match real
  // data - see listing_constants.dart for the canonical type list.
  final Set<String> _selectedTypes = {};

  @override
  void initState() {
    super.initState();
    // initState runs once when the widget is first inserted into the
    // tree - this is the correct place to kick off a one-time fetch.
    _loadPlaces();
    _searchController.addListener(_onSearchChanged);
    _loadWishlistedIds();
    // If this first load fails because the device was offline (or
    // just reconnected and its clock hasn't finished syncing yet -
    // see network_retry.dart), don't leave the user stuck on the
    // error screen - reload automatically the moment we're back on
    // a network.
    startAutoReloadOnReconnect();
  }

  /// Kicks off (or re-kicks-off, on reconnect) the places fetch.
  /// Wrapped in [withRetry] so a transient clock-skew failure right
  /// after reconnecting resolves itself instead of surfacing an
  /// error the user has to manually retry.
  void _loadPlaces() {
    setState(() {
      _placesFuture = withRetry(() => _placesService.getPlaces());
    });
  }

  @override
  void onReconnected() {
    _loadPlaces();
    _loadWishlistedIds();
  }

  Future<void> _loadWishlistedIds() async {
    try {
      final ids = await _wishlistService.getWishlistedPlaceIds();
      if (!mounted) return;
      setState(() => _wishlistedIds = ids);
    } catch (_) {
      // Non-critical - the places list still works even if this
      // fails, hearts just default to outlined/unsaved.
    }
  }

  Future<void> _toggleWishlist(Place place) async {
    final alreadySaved = _wishlistedIds.contains(place.id);

    // Optimistic UI update - flip the heart immediately, then sync
    // with the server. Feels instant; we roll back on failure.
    setState(() {
      if (alreadySaved) {
        _wishlistedIds.remove(place.id);
      } else {
        _wishlistedIds.add(place.id);
      }
    });

    try {
      if (alreadySaved) {
        await _wishlistService.removeFromWishlist(place.id);
      } else {
        await _wishlistService.addToWishlist(place.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (alreadySaved) {
          _wishlistedIds.add(place.id);
        } else {
          _wishlistedIds.remove(place.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your wishlist.')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    disposeAutoReloadOnReconnect();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _applyFilters());
  }

  void _onTypeSelected(String? type) {
    setState(() {
      if (type == null) {
        // "All" pill clears every other selection.
        _selectedTypes.clear();
      } else {
        // Tapping a pill selects it. Tapping it again while already
        // selected does nothing - it stays on; only "All" clears it.
        _selectedTypes.add(type);
      }
      _applyFilters();
    });
  }

  // Applies both the type pills and the search text together.
  // Within types it's OR (Villa or Farmhouse selected shows both);
  // between the type filter and the search box it's AND, so typing
  // "goa" while Villa is selected narrows to villas in Goa.
  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    _filteredPlaces = _allPlaces.where((p) {
      final matchesType = _selectedTypes.isEmpty ||
          _selectedTypes.contains(p.type.toLowerCase());
      final matchesQuery = query.isEmpty ||
          p.title.toLowerCase().contains(query) ||
          p.cityName.toLowerCase().contains(query) ||
          p.address.toLowerCase().contains(query) ||
          p.type.toLowerCase().contains(query);
      return matchesType && matchesQuery;
    }).toList();
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

  // Refreshes the saved-ids set on return, in case the user removed
  // something from inside the Wishlist screen itself.
  void _openWishlist() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WishlistScreen()))
        .then((_) => _loadWishlistedIds());
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
            _buildTypePills(),
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
                'Welcome back, guest!',
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
            onTap: _openWishlist,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.favorite_border,
                color: Color.fromARGB(255, 250, 36, 36),
                size: 24,
              ),
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

  Widget _buildTypePills() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        children: [
          _buildPill(
            label: 'All',
            type: null,
            isSelected: _selectedTypes.isEmpty,
          ),
          for (final type in kPropertyTypes)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildPill(
                // Capitalize each word: 'holiday home' -> 'Holiday Home'
                label: type
                    .split(' ')
                    .map((w) => w[0].toUpperCase() + w.substring(1))
                    .join(' '),
                type: type,
                isSelected: _selectedTypes.contains(type),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required String? type,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _onTypeSelected(type),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          // Frosted-glass effect - subtle blur of whatever sits behind
          // the pill, so it reads as translucent rather than flat white.
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.black.withOpacity(0.85)
                  : AppColors.white.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? Colors.black
                    : Colors.black.withOpacity(0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Colors.black.withOpacity(0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
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
          return ErrorStateView(
            error: snapshot.error!,
            fallbackMessage: 'Could not load places.',
            onRetry: _loadPlaces,
          );
        }

        // 3. Success - populate _allPlaces once (first successful build)
        final places = snapshot.data ?? [];
        if (_allPlaces.isEmpty && places.isNotEmpty) {
          _allPlaces = places;
          _applyFilters();
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
              isWishlisted: _wishlistedIds.contains(place.id),
              onWishlistToggle: () => _toggleWishlist(place),
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
