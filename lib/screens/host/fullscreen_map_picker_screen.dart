import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/location_service.dart';

/// Full-screen version of the wizard's small "Pin the exact location"
/// map box - opened by tapping the expand button there. Has its own
/// copy of the search box, "use my location," and tap-to-drop-pin,
/// since it's a genuinely separate screen/route rather than the same
/// map widget just resized.
///
/// Returns the final [LatLng] via `Navigator.pop` when closed (either
/// the X button or the system back gesture/button) - `null` if
/// nothing was ever set. The caller (the wizard) only needs to act on
/// a non-null result.
class FullScreenMapPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;

  const FullScreenMapPickerScreen({super.key, this.initialLocation});

  @override
  State<FullScreenMapPickerScreen> createState() =>
      _FullScreenMapPickerScreenState();
}

class _FullScreenMapPickerScreenState
    extends State<FullScreenMapPickerScreen> {
  static const _locationService = LocationService();

  late LatLng? _pinLocation = widget.initialLocation;
  final MapController _mapController = MapController();

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<PlaceSearchResult> _searchResults = [];
  bool _searching = false;
  bool _locatingCurrent = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_pinLocation);

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    setState(() {}); // updates the clear (x) button's visibility
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _searching = true);
      final results = await _locationService.searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchResults = results;
      });
    });
  }

  void _selectSearchResult(PlaceSearchResult result) {
    _searchFocus.unfocus();
    setState(() {
      _pinLocation = result.location;
      _searchResults = [];
      _searchController.text = result.displayName;
    });
    _mapController.move(result.location, 15);
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchResults = [];
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locatingCurrent = true);
    final result = await _locationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _locatingCurrent = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't get your current location - check location "
            "permissions, or drop the pin manually."),
      ));
      return;
    }
    setState(() => _pinLocation = result);
    _mapController.move(result, 16);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Matches the wizard's own back-button handling - the system
      // back gesture/button should behave exactly like the X button
      // (hand the current pin back), not just discard everything.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _pinLocation ?? const LatLng(20.5937, 78.9629),
                  initialZoom: _pinLocation != null ? 15 : 4.4,
                  onTap: (tapPosition, point) {
                    _searchFocus.unfocus();
                    setState(() {
                      _pinLocation = point;
                      _searchResults = [];
                    });
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.homely.homely_app',
                  ),
                  if (_pinLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _pinLocation!,
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_pin,
                            color: AppColors.error,
                            size: 44,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // ---- Top bar: close button + search box ----
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Material(
                            color: AppColors.white,
                            shape: const CircleBorder(),
                            elevation: 3,
                            child: IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.dark),
                              onPressed: _close,
                              tooltip: 'Close',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Material(
                              borderRadius: BorderRadius.circular(12),
                              elevation: 3,
                              shadowColor: Colors.black26,
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocus,
                                onChanged: _onSearchChanged,
                                style: const TextStyle(fontSize: 13.5),
                                decoration: InputDecoration(
                                  hintText: 'Search for any location...',
                                  hintStyle: const TextStyle(fontSize: 13),
                                  filled: true,
                                  fillColor: AppColors.white,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  prefixIcon: _searching
                                      ? const Padding(
                                          padding: EdgeInsets.all(14),
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : const Icon(Icons.search_rounded,
                                          size: 20),
                                  suffixIcon: _searchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.close_rounded,
                                              size: 18),
                                          onPressed: _clearSearch,
                                        ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6, left: 54),
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: Material(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(12),
                            elevation: 4,
                            shadowColor: Colors.black26,
                            clipBehavior: Clip.antiAlias,
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _searchResults.length,
                              separatorBuilder: (_, __) => const Divider(
                                  height: 1, color: AppColors.lightGrey),
                              itemBuilder: (context, index) {
                                final result = _searchResults[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.place_outlined,
                                      size: 18, color: AppColors.grey),
                                  title: Text(
                                    result.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  onTap: () => _selectSearchResult(result),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // ---- Bottom bar: "use my location" + confirm ----
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_pinLocation != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_pinLocation!.latitude.toStringAsFixed(5)}, '
                            '${_pinLocation!.longitude.toStringAsFixed(5)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.grey),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed:
                                  _locatingCurrent ? null : _useCurrentLocation,
                              icon: _locatingCurrent
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child:
                                          CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.my_location_rounded,
                                      size: 16),
                              label: const Text('Use my location',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _pinLocation == null ? null : _close,
                              child: const Text('Confirm location',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
