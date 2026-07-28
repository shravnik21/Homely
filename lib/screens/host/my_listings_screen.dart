import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/services/listing_service.dart';
import 'package:homely_app/screens/host/listing_wizard_screen.dart';
import 'package:homely_app/screens/host/listing_manage_screen.dart';

/// The listing switcher - every property this host manages, any
/// status (draft/published/paused), with a status chip on each. Tap
/// a listing to manage it (edit/pause/delete); tap "+" to start a
/// new one via the wizard.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  final ListingService _listingService = ListingService();
  List<Place> _listings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final listings = await _listingService.getMyListings();
      if (mounted) setState(() => _listings = listings);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addListing() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ListingWizardScreen()),
    );
    if (result == true) _load();
  }

  Future<void> _manageListing(Place place) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListingManageScreen(place: place)),
    );
    if (result == true) _load();
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
          'Your Listings',
          style: TextStyle(
              color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.primary),
            onPressed: _addListing,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _listings.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _listings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _listingCard(_listings[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_work_outlined, size: 56, color: AppColors.grey),
            const SizedBox(height: 16),
            const Text(
              "You haven't added any listings yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _addListing,
              child: const Text('Add a Listing'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listingCard(Place place) {
    return GestureDetector(
      onTap: () => _manageListing(place),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: place.photoUrls.isEmpty
                    ? Container(
                        color: AppColors.white,
                        child: const Icon(Icons.home_outlined, color: AppColors.grey),
                      )
                    : CachedNetworkImage(
                        imageUrl: place.coverImage, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.dark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    place.cityName.isEmpty ? 'No city set' : place.cityName,
                    style: const TextStyle(fontSize: 12, color: AppColors.grey),
                  ),
                  const SizedBox(height: 6),
                  _statusChip(place.status),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grey),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    late Color color;
    late String label;
    switch (status) {
      case 'published':
        color = Colors.green;
        label = 'Published';
        break;
      case 'paused':
        color = Colors.orange;
        label = 'Paused';
        break;
      default:
        color = AppColors.grey;
        label = 'Draft';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
