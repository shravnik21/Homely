import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/services/wishlist_service.dart';
import 'package:homely_app/widgets/place_card.dart';
import 'package:homely_app/widgets/error_state_view.dart';
import 'place_detail_screen.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final WishlistService _wishlistService = WishlistService();
  late Future<List<Place>> _wishlistFuture;

  // Kept separately from the Future's data so removing a card updates
  // the list immediately without waiting on / re-triggering a fetch.
  List<Place> _places = [];

  @override
  void initState() {
    super.initState();
    _wishlistFuture = _loadWishlist();
  }

  void _refresh() {
    setState(() => _wishlistFuture = _loadWishlist());
  }

  Future<List<Place>> _loadWishlist() async {
    final places = await _wishlistService.getWishlist();
    _places = places;
    return places;
  }

  Future<void> _removeFromWishlist(Place place) async {
    // Optimistic removal - the card disappears right away; if the
    // server call fails we put it back and let the user know.
    final removedIndex = _places.indexOf(place);
    setState(() => _places.remove(place));

    try {
      await _wishlistService.removeFromWishlist(place.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _places.insert(removedIndex.clamp(0, _places.length), place);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove from wishlist.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Wishlist',
          style: TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Place>>(
          future: _wishlistFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ErrorStateView(
                error: snapshot.error!,
                fallbackMessage: 'Could not load your wishlist.',
                onRetry: _refresh,
              );
            }

            if (_places.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.lightGrey,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.favorite_border,
                          color: AppColors.grey,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your wishlist is empty',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap the heart on any place to save it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: _places.length,
              itemBuilder: (context, index) {
                final place = _places[index];
                return PlaceCard(
                  place: place,
                  isWishlisted: true,
                  onWishlistToggle: () => _removeFromWishlist(place),
                  onTap: () {
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
        ),
      ),
    );
  }
}
