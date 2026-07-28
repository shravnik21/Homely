import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/services/listing_service.dart';
import 'package:homely_app/screens/host/listing_wizard_screen.dart';

/// Detail/management view for one listing a host already created:
/// edit (reopens the wizard prefilled), pause/unpause (hide it from
/// guest search without losing it), and delete (permanent, confirmed).
class ListingManageScreen extends StatefulWidget {
  final Place place;
  const ListingManageScreen({super.key, required this.place});

  @override
  State<ListingManageScreen> createState() => _ListingManageScreenState();
}

class _ListingManageScreenState extends State<ListingManageScreen> {
  final ListingService _listingService = ListingService();
  late Place _place;
  bool _isBusy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _place = widget.place;
  }

  Future<void> _refresh() async {
    final updated = await _listingService.getListingById(_place.id);
    if (updated != null && mounted) setState(() => _place = updated);
  }

  Future<void> _edit() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ListingWizardScreen(existingPlace: _place)),
    );
    if (result == true) {
      _changed = true;
      await _refresh();
    }
  }

  Future<void> _togglePause() async {
    setState(() => _isBusy = true);
    try {
      if (_place.status == 'paused') {
        await _listingService.unpauseListing(_place.id);
      } else {
        await _listingService.pauseListing(_place.id);
      }
      _changed = true;
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update listing: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: const Text(
            'This permanently removes the listing and its photos. This '
            "can't be undone. If you just want to hide it temporarily, "
            'use Pause instead.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      final storagePaths = _place.photoUrls
          .map(_pathFromPublicUrl)
          .whereType<String>()
          .toList();
      await _listingService.deleteListing(_place.id, storagePaths);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete listing: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String? _pathFromPublicUrl(String url) {
    const marker = '/listing-images/';
    final index = url.indexOf(marker);
    if (index == -1) return null;
    return url.substring(index + marker.length);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_changed);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Manage Listing',
            style: TextStyle(
                color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 18),
          ),
          iconTheme: const IconThemeData(color: AppColors.dark),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.dark),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: _place.photoUrls.isEmpty
                      ? Container(
                          color: AppColors.lightGrey,
                          child: const Icon(Icons.image_not_supported_outlined,
                              color: AppColors.grey, size: 40),
                        )
                      : CachedNetworkImage(
                          imageUrl: _place.coverImage, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _place.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
                    ),
                  ),
                  _statusChip(_place.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _place.cityName.isEmpty ? 'No city set' : _place.cityName,
                style: const TextStyle(color: AppColors.grey, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                _place.pricePerNight > 0
                    ? '₹${_place.pricePerNight.toStringAsFixed(0)} / night'
                    : 'Price not set',
                style: const TextStyle(
                    color: AppColors.dark, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 28),
              _actionTile(
                icon: Icons.edit_outlined,
                label: 'Edit Listing',
                onTap: _edit,
              ),
              const SizedBox(height: 10),
              _actionTile(
                icon: _place.status == 'paused'
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
                label: _place.status == 'paused'
                    ? 'Unpause Listing'
                    : 'Pause Listing',
                subtitle: _place.status == 'draft'
                    ? null
                    : (_place.status == 'paused'
                        ? 'Hidden from guest search. Unpause to make it visible again.'
                        : 'Temporarily hide from guest search without losing your listing.'),
                onTap: _place.status == 'draft' ? null : _togglePause,
                isBusy: _isBusy,
              ),
              const SizedBox(height: 10),
              _actionTile(
                icon: Icons.delete_outline,
                label: 'Delete Listing',
                iconColor: AppColors.error,
                labelColor: AppColors.error,
                onTap: _delete,
                isBusy: _isBusy,
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
    Color iconColor = AppColors.dark,
    Color labelColor = AppColors.dark,
    bool isBusy = false,
  }) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment:
              subtitle == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: subtitle == null ? 0 : 2),
              child: Icon(icon, color: onTap == null ? AppColors.grey : iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: onTap == null ? AppColors.grey : labelColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (isBusy)
              const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.chevron_right, color: AppColors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
