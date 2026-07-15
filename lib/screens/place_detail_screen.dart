import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../models/place.dart';

class PlaceDetailScreen extends StatefulWidget {
  final Place place;

  const PlaceDetailScreen({super.key, required this.place});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;

    return Scaffold(
      backgroundColor: AppColors.white,
      // Using a plain scrollable body + a separate bottomNavigationBar
      // (instead of manually stacking/positioning everything) is the
      // standard, reliable Flutter pattern for "content that scrolls +
      // a bar that always stays pinned at the bottom".
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageCarousel(context, place),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTypeBadge(place),
                  const SizedBox(height: 10),
                  Text(
                    place.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 17, color: AppColors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${place.address}, ${place.cityName}',
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildStatsChips(place),
                  const Divider(height: 36, color: AppColors.lightGrey),
                  const Text(
                    'About this place',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    place.description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.grey,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Amenities',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildAmenitiesGrid(place),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBookingBar(context, place),
    );
  }

  Widget _buildImageCarousel(BuildContext context, Place place) {
    final imageCount = place.photoUrls.isEmpty ? 1 : place.photoUrls.length;
    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: imageCount,
            onPageChanged: (index) =>
                setState(() => _currentImageIndex = index),
            itemBuilder: (context, index) {
              final url = place.photoUrls.isEmpty
                  ? place.coverImage
                  : place.photoUrls[index];
              return CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => Container(
                  color: AppColors.lightGrey,
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.lightGrey,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: AppColors.grey, size: 40),
                ),
              );
            },
          ),

          if (place.photoUrls.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(place.photoUrls.length, (i) {
                  final active = i == _currentImageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.white
                          : AppColors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),

          Positioned(
            top: 8,
            left: 12,
            child: SafeArea(
              bottom: false,
              child: _CircleIconButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: _CircleIconButton(
                icon: Icons.favorite_border,
                onTap: () {
                  // TODO: wishlist/favourites (Tier 2)
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(Place place) {
    final label = place.type
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  // Pill-style chips (like "2 Beds", "1 Bath", "4 Guest" in the reference
  // design) instead of a plain icon+text row.
  Widget _buildStatsChips(Place place) {
    Widget chip(IconData icon, String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.dark),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        chip(Icons.bed_outlined, '${place.bedrooms} Beds'),
        const SizedBox(width: 10),
        chip(Icons.bathtub_outlined, '${place.bathrooms} Bath'),
        const SizedBox(width: 10),
        chip(Icons.people_outline, '${place.maxGuests} Guest'),
      ],
    );
  }

  Widget _buildAmenitiesGrid(Place place) {
    IconData iconFor(String amenity) {
      final a = amenity.toLowerCase();
      if (a.contains('wifi')) return Icons.wifi;
      if (a.contains('tv')) return Icons.tv;
      if (a.contains('ac') || a.contains('air')) return Icons.ac_unit;
      if (a.contains('kitchen')) return Icons.kitchen_outlined;
      if (a.contains('parking')) return Icons.local_parking_outlined;
      if (a.contains('pool')) return Icons.pool;
      if (a.contains('bonfire')) return Icons.local_fire_department_outlined;
      if (a.contains('lawn') || a.contains('garden')) return Icons.grass;
      if (a.contains('power')) return Icons.power_outlined;
      return Icons.check_circle_outline;
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: place.amenities.map((amenity) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconFor(amenity), size: 16, color: AppColors.dark),
              const SizedBox(width: 6),
              Text(
                amenity,
                style: const TextStyle(fontSize: 13, color: AppColors.dark),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBookingBar(BuildContext context, Place place) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '₹${place.pricePerNight.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark,
                    ),
                  ),
                  const TextSpan(
                    text: ' / night',
                    style: TextStyle(fontSize: 13, color: AppColors.grey),
                  ),
                ],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: navigate to BookingScreen (Phase 3)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Booking screen coming in Phase 3'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 52),
            ),
            child: const Text('Book Now'),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
