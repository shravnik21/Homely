import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/config/checkin_methods.dart';
import 'package:homely_app/services/cancellation_policy.dart';
import 'package:homely_app/services/listing_service.dart';
import 'package:homely_app/services/location_service.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';
import 'package:homely_app/utils/network_error_helper.dart';
import 'fullscreen_map_picker_screen.dart';

const List<String> kPropertyTypes = [
  'villa',
  'apartment',
  'cottage',
  'cabin',
  'bungalow',
  'holiday home',
  'beach house',
  'farmhouse',
  'penthouse',
  'homestay',
];

const List<String> kAmenityOptions = [
  'WiFi',
  'TV',
  'AC',
  'Kitchen',
  'Parking',
  'Pool',
  'Bonfire',
  'Lawn',
  'Power Backup',
  'Pet-Friendly',
  'BBQ',
  'Fireplace',
  'Bathtub',
  'Outdoor Seating Area',
  'Dining Area',
];

const int kMinPhotosToPublish = Place.kMinPhotosToPublish;

/// One photo in the wizard's in-memory list. Either a freshly-picked
/// local file already uploaded to Storage (uploadedUrl set as soon as
/// the upload finishes) or - when editing an existing listing - a
/// photo that was already saved on a previous visit (localFile null,
/// uploadedUrl pre-filled from the DB).
class _WizardPhoto {
  File? localFile;
  String? uploadedUrl;
  bool isUploading;
  _WizardPhoto({this.localFile, this.uploadedUrl, this.isUploading = false});
}

/// Airbnb-style step-through listing creation/edit flow:
/// property type -> location -> basics -> photos -> amenities ->
/// pricing -> cancellation policy -> house rules -> highlights ->
/// review & publish.
///
/// The DB row is created immediately after step 1 (see
/// ListingService.createDraftListing) so every later step - including
/// photo uploads, which need a real place id - has something to
/// attach to, and "Save Draft" never has extra work: the row already
/// exists, this just updates it with whatever has been filled in.
class ListingWizardScreen extends StatefulWidget {
  final Place? existingPlace;
  const ListingWizardScreen({super.key, this.existingPlace});

  @override
  State<ListingWizardScreen> createState() => _ListingWizardScreenState();
}

class _ListingWizardScreenState extends State<ListingWizardScreen> {
  final ListingService _listingService = ListingService();
  final PageController _pageController = PageController();
  final ImagePicker _picker = ImagePicker();

  static const _stepTitles = [
    'Property Type',
    'Location',
    'Basics',
    'Photos',
    'Amenities',
    'Pricing',
    'Cancellation Policy',
    'House Rules',
    'Highlights',
    'Review & Publish',
  ];

  int _currentStep = 0;
  String? _placeId;
  bool _isBusy = false; // covers per-step "Next" saves and final publish
  String? _stepError;

  // ---- form state, one field per collected value ----
  String? _type;

  // City used to be picked from a fixed 5-city chip list; a host can
  // now type any city in India instead, so this is a free-text field
  // - _cityId/_cityName are resolved from it at save time via
  // ListingService.getOrCreateCity (see _persistStep case 1).
  final _cityController = TextEditingController();
  String? _cityId;
  String? _cityName;
  // Address is collected as separate, Airbnb-style fields for a much
  // clearer entry experience. Each field is now also saved to its
  // own column (flat_house_no/street/landmark/pincode - see
  // schema_address_components.sql) so re-opening a listing to edit
  // it can prefill them separately; they're additionally joined into
  // a single string for the existing `address` column, which every
  // other part of the app (guest listing pages, directions, etc.)
  // still reads unchanged.
  final _flatController = TextEditingController(); // Flat/House no., Building/Society
  final _streetController = TextEditingController(); // Street / Area / Locality
  final _landmarkController = TextEditingController(); // optional
  final _pincodeController = TextEditingController(); // optional

  // ---- Map pin (optional) - the exact lat/lng a host drops on the
  // map, saved to places.latitude/longitude (see
  // schema_host_listings.sql). Entirely optional: a listing with no
  // pin still works exactly as it always has, guests just fall back
  // to address-based directions instead of pin-based ones (see
  // MapsLauncher.openDirectionsToAddress on the guest side). ----
  static const _locationService = LocationService();
  LatLng? _pinLocation;
  // flutter_map's controller is ready to use as soon as it's
  // constructed - unlike GoogleMapController, there's no async
  // "onMapCreated" handoff to wait for.
  final MapController _mapController = MapController();
  bool _locatingCity = false;
  bool _locatingCurrent = false;

  // ---- Map search box - lets the host type any place name and jump
  // the map there, rather than only being able to drop a pin by
  // tapping or fall back on the typed street/city address. ----
  final _mapSearchController = TextEditingController();
  final _mapSearchFocus = FocusNode();
  Timer? _mapSearchDebounce;
  List<PlaceSearchResult> _mapSearchResults = [];
  bool _mapSearching = false;

  final _titleController = TextEditingController();
  int _bedrooms = 1;
  int _bathrooms = 1;
  int _maxGuests = 2;
  final _descriptionController = TextEditingController();

  final List<_WizardPhoto> _photos = [];

  final Set<String> _amenities = {};

  final _priceController = TextEditingController();

  // ---- Cancellation Policy: one of the three CancellationPolicyType
  // values; Flexible additionally needs the host's own cutoff/fee -
  // see CancellationPolicy for what these actually control. Defaults
  // to 'moderate' to match the DB column's own default, so a host who
  // never touches this step still ends up with the exact same
  // behaviour every listing already had before this feature. ----
  String _cancellationPolicyType = 'moderate';
  final _flexibleFreeDaysController = TextEditingController();
  final _flexibleFeePercentController = TextEditingController();

  final _houseRulesController = TextEditingController();

  // ---- Highlights: a check-in method (picked from a fixed set of
  // cards, plus free-text details) and two fully custom slots, shown
  // on PlaceDetailScreen as short icon+title+description rows (see
  // schema_place_highlights.sql / schema_place_checkin_method.sql).
  // All optional - a host can publish with none of these filled in.
  String? _checkinMethod;
  final _checkinDetailsController = TextEditingController();
  final _highlight1TitleController = TextEditingController();
  final _highlight1DescController = TextEditingController();
  final _highlight2TitleController = TextEditingController();
  final _highlight2DescController = TextEditingController();

  bool get _isEditing => widget.existingPlace != null;

  @override
  void initState() {
    super.initState();
    if (widget.existingPlace != null) _prefillFrom(widget.existingPlace!);
  }

  void _prefillFrom(Place place) {
    _placeId = place.id;
    _type = place.type;
    _cityId = place.cityId;
    _cityName = place.cityName.isEmpty ? null : place.cityName;
    _cityController.text = _cityName ?? '';
    // Newer listings have their address components saved separately
    // (see schema_address_components.sql) - prefill each field
    // exactly as the host left it. Older listings created before
    // that migration have these as null, so fall back to dropping
    // the old joined address string into the Street field as a
    // sensible best-effort default, same as before - nothing is
    // lost, it's just no longer pre-split for those.
    if (place.flatHouseNo != null ||
        place.street != null ||
        place.landmark != null ||
        place.pincode != null) {
      _flatController.text = place.flatHouseNo ?? '';
      _streetController.text = place.street ?? '';
      _landmarkController.text = place.landmark ?? '';
      _pincodeController.text = place.pincode ?? '';
    } else {
      _streetController.text = place.address;
    }
    if (place.latitude != null && place.longitude != null) {
      _pinLocation = LatLng(place.latitude!, place.longitude!);
    }
    _titleController.text =
        place.title == 'Untitled listing' ? '' : place.title;
    _bedrooms = place.bedrooms;
    _bathrooms = place.bathrooms;
    _maxGuests = place.maxGuests;
    _descriptionController.text = place.description;
    _amenities.addAll(place.amenities);
    _priceController.text =
        place.pricePerNight > 0 ? place.pricePerNight.toStringAsFixed(0) : '';
    _cancellationPolicyType = place.cancellationPolicyType;
    if (place.cancellationFlexibleFreeDays != null) {
      _flexibleFreeDaysController.text =
          place.cancellationFlexibleFreeDays.toString();
    }
    if (place.cancellationFlexibleFeePercent != null) {
      _flexibleFeePercentController.text =
          place.cancellationFlexibleFeePercent!.toStringAsFixed(0);
    }
    _houseRulesController.text = place.houseRules ?? '';
    _checkinMethod = place.checkinMethod;
    _checkinDetailsController.text = place.checkinDetails ?? '';
    _highlight1TitleController.text = place.highlight1Title ?? '';
    _highlight1DescController.text = place.highlight1Description ?? '';
    _highlight2TitleController.text = place.highlight2Title ?? '';
    _highlight2DescController.text = place.highlight2Description ?? '';
    for (final url in place.photoUrls) {
      _photos.add(_WizardPhoto(uploadedUrl: url));
    }
  }

  /// Joins the separate address fields into the single string that
  /// actually gets saved to the `address` column - e.g. "Flat 302,
  /// Sunrise Apartments, MG Road, Calangute, near Baga Beach, 403516".
  /// Empty optional fields are simply skipped rather than leaving
  /// stray commas.
  String _buildAddress() {
    final landmark = _landmarkController.text.trim();
    final parts = [
      _flatController.text.trim(),
      _streetController.text.trim(),
      if (landmark.isNotEmpty) 'near $landmark',
      _pincodeController.text.trim(),
    ].where((s) => s.isNotEmpty);
    return parts.join(', ');
  }

  @override
  void dispose() {
    _pageController.dispose();
    _mapSearchController.dispose();
    _mapSearchFocus.dispose();
    _mapSearchDebounce?.cancel();
    _cityController.dispose();
    _flatController.dispose();
    _streetController.dispose();
    _landmarkController.dispose();
    _pincodeController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _flexibleFreeDaysController.dispose();
    _flexibleFeePercentController.dispose();
    _houseRulesController.dispose();
    _checkinDetailsController.dispose();
    _highlight1TitleController.dispose();
    _highlight1DescController.dispose();
    _highlight2TitleController.dispose();
    _highlight2DescController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Navigation / persistence
  // ---------------------------------------------------------------

  Future<void> _goNext() async {
    final error = _validateStep(_currentStep);
    if (error != null) {
      setState(() => _stepError = error);
      return;
    }
    setState(() => _stepError = null);

    if (_currentStep == 0 || _currentStep == 1) {
      // Step 0 has to block: it creates the place row that every
      // later step (photo uploads especially) needs a real id for.
      // Step 1 (Location) now also has to block: the city field takes
      // free text, so saving it means an async lookup/insert against
      // `cities` (see ListingService.getOrCreateCity), and later
      // steps read the resolved _cityId/_cityName back from local
      // state rather than re-fetching - that resolution has to finish
      // before the host moves on, same reasoning as step 0.
      setState(() => _isBusy = true);
      try {
        await _persistStep(_currentStep);
      } catch (e) {
        if (mounted) setState(() => _stepError = friendlyError(e, fallback: 'Could not save this step.'));
        return;
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
    } else {
      // The row already exists by now, so there's nothing this step's
      // save is blocking on. Save it in the background and advance
      // immediately instead of making the host stare at a spinner on
      // every "Next" tap for a round trip that doesn't need to be
      // in the critical path. If it fails, surface it as a snackbar
      // rather than trapping them on the current page.
      _persistStep(_currentStep).catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, fallback: 'Could not save this step.'))),
          );
        }
      });
    }

    if (!mounted) return;
    if (_currentStep == _stepTitles.length - 1) return; // handled by Publish
    setState(() => _currentStep++);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// Unlike _goNext, backward navigation was never actually saving
  /// the step being left - a host who edited Location (or any step)
  /// and then tapped the app-bar back arrow instead of "Next" would
  /// have their edits silently discarded from the database, even
  /// though the fields still looked filled-in on screen (that's just
  /// local widget state, not what's saved). Persisting here too,
  /// fire-and-forget/backgrounded exactly like _goNext's non-blocking
  /// branch, closes that gap without slowing down back navigation.
  void _goBack() {
    if (_currentStep == 0) {
      Navigator.of(context).pop();
      return;
    }
    if (_currentStep != 0 || _type != null) {
      _persistStep(_currentStep).catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(friendlyError(e, fallback: 'Could not save this step.'))),
          );
        }
      });
    }
    setState(() {
      _stepError = null;
      _currentStep--;
    });
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// Every step must have its required field(s) filled in before the
  /// host can tap "Next" - this only gates forward navigation via
  /// _goNext. "Save & Exit" still works from any step, empty or not,
  /// so the host can always save-and-exit a draft mid-way.
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_type == null) return 'Please select a property type to continue';
        return null;
      case 1:
        if (_cityController.text.trim().isEmpty) {
          return 'Please enter a city to continue';
        }
        if (_streetController.text.trim().isEmpty) {
          return 'Please enter a street / area to continue';
        }
        return null;
      case 2:
        if (_titleController.text.trim().isEmpty) {
          return 'Please enter a listing title to continue';
        }
        if (_descriptionController.text.trim().isEmpty) {
          return 'Please enter a description to continue';
        }
        return null;
      case 3:
        if (_photos.isEmpty) {
          return 'Please add at least one photo to continue';
        }
        return null;
      case 4:
        if (_amenities.isEmpty) {
          return 'Please select at least one amenity to continue';
        }
        return null;
      case 5:
        final price = num.tryParse(_priceController.text.trim());
        if (price == null || price <= 0) {
          return 'Please enter a valid nightly price to continue';
        }
        return null;
      case 6:
        if (_cancellationPolicyType == 'flexible') {
          final freeDays =
              int.tryParse(_flexibleFreeDaysController.text.trim());
          if (freeDays == null || freeDays < 0) {
            return 'Please enter a valid number of free-cancellation days';
          }
          final feePercent =
              num.tryParse(_flexibleFeePercentController.text.trim());
          if (feePercent == null || feePercent < 0 || feePercent > 100) {
            return 'Please enter a valid cancellation fee percentage (0–100)';
          }
        }
        return null;
      case 7:
        if (_houseRulesController.text.trim().isEmpty) {
          return 'Please enter your house rules to continue';
        }
        return null;
      case 8:
        // The two custom highlights below stay entirely optional,
        // but a check-in method is not - a guest arriving with no
        // idea how to actually get into the place is exactly the
        // kind of gap this step exists to close. "Other" additionally
        // needs the host's own description, since "Other" by itself
        // tells a guest nothing about what to actually do.
        if (_checkinMethod == null) {
          return 'Please select a check-in method to continue';
        }
        if (_checkinMethod == 'other' &&
            _checkinDetailsController.text.trim().isEmpty) {
          return 'Please describe your check-in method to continue';
        }
        return null;
      default:
        return null;
    }
  }

  /// Trims a controller's text, returning null instead of an empty
  /// string - shared by [_persistStep]'s case 7 and [_publish]'s
  /// readiness snapshot so both agree on what counts as "filled in".
  String? _orNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _persistStep(int step) async {
    switch (step) {
      case 0:
        if (_placeId == null) {
          _placeId = await _listingService.createDraftListing(type: _type!);
        } else {
          await _listingService.updateListing(_placeId!, {'type': _type});
        }
        break;
      case 1:
        // Resolve the typed city name to an id, creating a new
        // `cities` row if this is somewhere not seen before (see
        // ListingService.getOrCreateCity) - _cityId/_cityName are
        // then kept in sync so the Review step and the publish
        // readiness snapshot reflect whatever was actually saved.
        final city =
            await _listingService.getOrCreateCity(_cityController.text);
        _cityId = city['id'] as String;
        _cityName = city['name'] as String;
        await _listingService.updateListing(_placeId!, {
          'city_id': _cityId,
          'address': _buildAddress(),
          // Saved alongside the joined `address` string purely so
          // re-opening this listing to edit it can prefill each field
          // separately instead of dumping the whole address into one
          // box - see schema_address_components.sql.
          'flat_house_no': _orNull(_flatController),
          'street': _orNull(_streetController),
          'landmark': _orNull(_landmarkController),
          'pincode': _orNull(_pincodeController),
          'latitude': _pinLocation?.latitude,
          'longitude': _pinLocation?.longitude,
        });
        break;
      case 2:
        await _listingService.updateListing(_placeId!, {
          'title': _titleController.text.trim().isEmpty
              ? 'Untitled listing'
              : _titleController.text.trim(),
          'bedrooms': _bedrooms,
          'bathrooms': _bathrooms,
          'max_guests': _maxGuests,
          'description': _descriptionController.text.trim(),
        });
        break;
      case 3:
        await _listingService.savePhotoOrder(
          _placeId!,
          _photos
              .where((p) => p.uploadedUrl != null)
              .map((p) => p.uploadedUrl!)
              .toList(),
        );
        break;
      case 4:
        await _listingService.updateListing(
            _placeId!, {'amenities': _amenities.toList()});
        break;
      case 5:
        await _listingService.updateListing(_placeId!, {
          'price_per_night': num.tryParse(_priceController.text.trim()) ?? 0,
        });
        break;
      case 6:
        final isFlexible = _cancellationPolicyType == 'flexible';
        await _listingService.updateListing(_placeId!, {
          'cancellation_policy_type': _cancellationPolicyType,
          'cancellation_flexible_free_days': isFlexible
              ? int.tryParse(_flexibleFreeDaysController.text.trim())
              : null,
          'cancellation_flexible_fee_percent': isFlexible
              ? num.tryParse(_flexibleFeePercentController.text.trim())
              : null,
        });
        break;
      case 7:
        await _listingService.updateListing(
            _placeId!, {'house_rules': _houseRulesController.text.trim()});
        break;
      case 8:
        await _listingService.updateListing(_placeId!, {
          'checkin_method': _checkinMethod,
          'checkin_details': _orNull(_checkinDetailsController),
          'highlight1_title': _orNull(_highlight1TitleController),
          'highlight1_description': _orNull(_highlight1DescController),
          'highlight2_title': _orNull(_highlight2TitleController),
          'highlight2_description': _orNull(_highlight2DescController),
        });
        break;
    }
  }

  Future<void> _saveAndExit() async {
    setState(() => _isBusy = true);
    try {
      final reviewStepIndex = _stepTitles.length - 1;
      if (_currentStep == reviewStepIndex) {
        // The review step has no fields of its own to persist - it's
        // a read-only summary of everything already collected - so
        // save the same set _saveDraftFromReview/_publish do instead
        // of a step index the switch in _persistStep has no case for
        // (which silently did nothing here before). Step 1 is
        // included here too - _goBack now saves it on the way back,
        // but this re-save stays as a belt-and-suspenders backstop.
        await _persistStep(1);
        await _persistStep(2);
        await _persistStep(4);
        await _persistStep(5);
        await _persistStep(6);
        await _persistStep(7);
        await _persistStep(8);
      } else if (_currentStep != 0 || _type != null) {
        // Only persist the current step if it has something worth
        // saving (step 0 requires a type; every other step is
        // safe to persist as-is, even blank).
        await _persistStep(_currentStep);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, fallback: 'Could not save draft.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _publish() async {
    // Build a snapshot of the live form state and run it through the
    // exact same completeness check ListingManageScreen's shortcut
    // Publish button uses (Place.missingRequirementsForPublish) -
    // one shared definition of "ready to publish" so a listing can
    // never be published from either screen with a step left
    // unfinished.
    final draftSnapshot = Place(
      id: _placeId ?? '',
      cityId: _cityId,
      cityName: _cityName ?? '',
      title: _titleController.text.trim(),
      type: _type ?? '',
      pricePerNight: num.tryParse(_priceController.text.trim()) ?? 0,
      maxGuests: _maxGuests,
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      address: _buildAddress(),
      flatHouseNo: _orNull(_flatController),
      street: _orNull(_streetController),
      landmark: _orNull(_landmarkController),
      pincode: _orNull(_pincodeController),
      latitude: _pinLocation?.latitude,
      longitude: _pinLocation?.longitude,
      description: _descriptionController.text.trim(),
      amenities: _amenities.toList(),
      photoUrls: _photos
          .where((p) => p.uploadedUrl != null)
          .map((p) => p.uploadedUrl!)
          .toList(),
      houseRules: _houseRulesController.text.trim(),
      // These three were missing before, which made the readiness
      // check always see check-in as "not set" - even mid-edit, on a
      // listing that already had one - since it silently fell back to
      // Place's defaults (null) instead of the live form state.
      checkinMethod: _checkinMethod,
      checkinDetails: _orNull(_checkinDetailsController),
      highlight1Title: _orNull(_highlight1TitleController),
      highlight1Description: _orNull(_highlight1DescController),
      highlight2Title: _orNull(_highlight2TitleController),
      highlight2Description: _orNull(_highlight2DescController),
      cancellationPolicyType: _cancellationPolicyType,
      cancellationFlexibleFreeDays: _cancellationPolicyType == 'flexible'
          ? int.tryParse(_flexibleFreeDaysController.text.trim())
          : null,
      cancellationFlexibleFeePercent: _cancellationPolicyType == 'flexible'
          ? num.tryParse(_flexibleFeePercentController.text.trim())
          : null,
    );
    final missing = Place.missingRequirementsForPublish(draftSnapshot);

    if (missing.isNotEmpty) {
      setState(() =>
          _stepError = 'Before publishing, please add: ${missing.join(', ')}.');
      return;
    }

    setState(() {
      _isBusy = true;
      _stepError = null;
    });
    try {
      // Persist whatever the review step itself doesn't already cover
      // (belt-and-suspenders in case an earlier step's Next was
      // skipped via direct navigation) then flip status.
      await _persistStep(1);
      await _persistStep(2);
      await _persistStep(4);
      await _persistStep(5);
      await _persistStep(6);
      await _persistStep(7);
      await _persistStep(8);
      await _listingService.publishListing(_placeId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing published!')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _stepError = friendlyError(e, fallback: 'Could not publish this listing.'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _saveDraftFromReview() async {
    setState(() => _isBusy = true);
    try {
      await _persistStep(1);
      await _persistStep(2);
      await _persistStep(4);
      await _persistStep(5);
      await _persistStep(6);
      await _persistStep(7);
      await _persistStep(8);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, fallback: 'Could not save.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ---------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------

  Future<void> _pickPhoto(ImageSource source) async {
    if (_photos.length >= ListingService.maxPhotos) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final photo = _WizardPhoto(localFile: File(picked.path), isUploading: true);
    setState(() => _photos.add(photo));

    try {
      final url =
          await _listingService.uploadListingPhoto(_placeId!, photo.localFile!);
      if (!mounted) return;
      setState(() {
        photo.uploadedUrl = url;
        photo.isUploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _photos.remove(photo));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: 'Upload failed.'))),
      );
    }
  }

  Future<void> _removePhoto(int index) async {
    final photo = _photos[index];
    setState(() => _photos.removeAt(index));
    if (photo.uploadedUrl != null) {
      await _listingService.deleteStorageFile(photo.uploadedUrl!);
    }
  }

  /// Handles drag-to-reorder from SliverReorderableList. This works
  /// reliably because the reorderable list lives as a sliver directly
  /// inside _stepPhotos's own CustomScrollView - a single scrollable,
  /// not nested inside another one - so there's no competing drag
  /// gesture to lose the arena to after the first reorder.
  void _reorderPhotos(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, item);
    });
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The in-app back arrow already routes through _goBack(), which
      // steps back one wizard page and only actually exits on step 0.
      // Without this, the OS-level back gesture (Android back button,
      // iOS edge-swipe) bypassed that entirely and popped the whole
      // route straight away - discarding the edit session mid-way
      // instead of stepping back a page, however deep in the wizard
      // the host was.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.dark),
            onPressed: _isBusy ? null : _goBack,
          ),
          title: Text(
            _stepTitles[_currentStep],
            style: const TextStyle(
                color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 17),
          ),
          actions: [
            TextButton(
              onPressed: _isBusy ? null : _saveAndExit,
              child: const Text('Save & Exit',
                  style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildStepIndicator(),
              if (_stepError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_stepError!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _stepPropertyType(),
                    _stepLocation(),
                    _stepBasics(),
                    _stepPhotos(),
                    _stepAmenities(),
                    _stepPricing(),
                    _stepCancellationPolicy(),
                    _stepHouseRules(),
                    _stepHighlights(),
                    _stepReview(),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: List.generate(_stepTitles.length, (i) {
          final active = i <= _currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == _stepTitles.length - 1 ? 0 : 4),
              height: 4,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.lightGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isLastStep = _currentStep == _stepTitles.length - 1;
    if (isLastStep) return const SizedBox.shrink(); // review step has its own buttons

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: PrimaryButton(
        text: 'Next',
        isLoading: _isBusy,
        onPressed: _goNext,
      ),
    );
  }

  Widget _sectionWrap({required Widget child}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }

  // ---- Step 1: Property Type ----
  Widget _stepPropertyType() {
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What kind of place is it?',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick the option that best describes your property.',
            style: TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kPropertyTypes.map((t) {
              final selected = _type == t;
              final label = t
                  .split(' ')
                  .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                  .join(' ');
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => setState(() => _type = t),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.dark,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.lightGrey),
                backgroundColor: AppColors.lightGrey,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---- Step 2: Location ----
  Widget _stepLocation() {
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where is it located?',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Listings can now be added in any city in India.',
            style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _cityController,
            label: 'City',
            hint: 'e.g. Jaipur',
          ),
          const SizedBox(height: 20),
          const Text('Address',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          const Text(
            'Only the street/area is required - the rest help guests find '
            'the place but can be added later.',
            style: TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: _flatController,
            label: 'Flat / House no., Building',
            hint: 'e.g. Flat 302, Sunrise Apartments',
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _streetController,
            label: 'Street / Area / Locality',
            hint: 'e.g. MG Road, Calangute',
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _landmarkController,
            label: 'Landmark (optional)',
            hint: 'e.g. Near Baga Beach',
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _pincodeController,
            label: 'Pincode (optional)',
            hint: 'e.g. 403516',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          _buildMapPinSection(),
        ],
      ),
    );
  }

  /// Optional "drop a pin" map - lets a host mark the property's exact
  /// coordinates rather than relying on the typed address alone. Not
  /// required to publish: a listing with no pin still works exactly
  /// as it always has, guests just get address-based directions
  /// instead of pin-based ones (see MapsLauncher on the guest side).
  Widget _buildMapPinSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pin the exact location',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 4),
        const Text(
          'Optional, but this is what lets guests get accurate turn-by-turn '
          'directions once they book. Tap anywhere on the map to drop or '
          'move the pin.',
          style: TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locatingCity ? null : _locateTypedCity,
                icon: _locatingCity
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search_rounded, size: 16),
                label:
                    const Text('Find on map', style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locatingCurrent ? null : _useCurrentLocation,
                icon: _locatingCurrent
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('Use my location',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 220,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _pinLocation ?? const LatLng(20.5937, 78.9629),
                    initialZoom: _pinLocation != null ? 15 : 4.4,
                    onTap: (tapPosition, point) {
                      // A manual tap always wins - it clears any open
                      // search dropdown and drops the pin exactly
                      // where the host tapped, for fine-tuning after
                      // a search has gotten them close.
                      _mapSearchFocus.unfocus();
                      setState(() {
                        _pinLocation = point;
                        _mapSearchResults = [];
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      // OpenStreetMap's own free tile server - no API
                      // key or billing account needed.
                      // userAgentPackageName is required by their
                      // usage policy so requests can be
                      // identified/rate-limited per app, not per
                      // random client.
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.homely.homely_app',
                    ),
                    if (_pinLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pinLocation!,
                            width: 40,
                            height: 40,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_pin,
                              color: AppColors.error,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            // ---- Expand button - opens the same map full-screen,
            // since the small preview box is too cramped to search
            // and place a pin precisely. ----
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: AppColors.white,
                shape: const CircleBorder(),
                elevation: 3,
                shadowColor: Colors.black26,
                child: IconButton(
                  icon: const Icon(Icons.open_in_full_rounded,
                      size: 18, color: AppColors.dark),
                  onPressed: _openFullScreenMap,
                  tooltip: 'Expand map',
                ),
              ),
            ),
            // ---- Search box, floating on top of the map itself, and
            // its results dropdown right below it. ----
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    borderRadius: BorderRadius.circular(12),
                    elevation: 3,
                    shadowColor: Colors.black26,
                    child: TextField(
                      controller: _mapSearchController,
                      focusNode: _mapSearchFocus,
                      onChanged: _onMapSearchChanged,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search for any location...',
                        hintStyle: const TextStyle(fontSize: 13),
                        filled: true,
                        fillColor: AppColors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        prefixIcon: _mapSearching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _mapSearchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: _clearMapSearch,
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (_mapSearchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Material(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 4,
                        shadowColor: Colors.black26,
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _mapSearchResults.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppColors.lightGrey),
                          itemBuilder: (context, index) {
                            final result = _mapSearchResults[index];
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
                              onTap: () => _selectMapSearchResult(result),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_pinLocation != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_pinLocation!.latitude.toStringAsFixed(5)}, '
                  '${_pinLocation!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _pinLocation = null),
                child: const Text('Clear pin', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// "Find on map" - geocodes whatever street/city text the host has
  /// typed so far via the device's own geocoder (see
  /// LocationService.geocodeCity), then recenters the map there. A
  /// starting point, not a replacement for dragging the pin onto the
  /// actual doorstep.
  Future<void> _locateTypedCity() async {
    final city = _cityController.text.trim();
    if (city.isEmpty) {
      setState(
          () => _stepError = 'Type a city first, then tap "Find on map".');
      return;
    }
    setState(() {
      _locatingCity = true;
      _stepError = null;
    });
    final query = [_streetController.text.trim(), city]
        .where((s) => s.isNotEmpty)
        .join(', ');
    final result = await _locationService.geocodeCity(query);
    if (!mounted) return;
    setState(() => _locatingCity = false);
    if (result == null) {
      setState(() => _stepError =
          "Couldn't find that on the map - try dropping the pin manually.");
      return;
    }
    setState(() => _pinLocation = result);
    _mapController.move(result, 15);
  }

  /// "Use my location" - centers the pin on wherever the host's own
  /// device currently is, useful when they're filling out the wizard
  /// while standing at the property itself.
  Future<void> _useCurrentLocation() async {
    setState(() => _locatingCurrent = true);
    final result = await _locationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _locatingCurrent = false);
    if (result == null) {
      setState(() => _stepError = "Couldn't get your current location - "
          "check location permissions, or drop the pin manually.");
      return;
    }
    setState(() => _pinLocation = result);
    _mapController.move(result, 15);
  }

  /// Debounces the map search box so a request only fires ~450ms
  /// after the host stops typing, rather than on every keystroke -
  /// both kinder to Nominatim's free API and avoids a flickering
  /// results list.
  void _onMapSearchChanged(String query) {
    _mapSearchDebounce?.cancel();
    setState(() {}); // updates the clear (x) button's visibility
    if (query.trim().isEmpty) {
      setState(() => _mapSearchResults = []);
      return;
    }
    _mapSearchDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _mapSearching = true);
      final results = await _locationService.searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _mapSearching = false;
        _mapSearchResults = results;
      });
    });
  }

  /// A host tapped one of the search results - jump the map there,
  /// drop the pin, and close the dropdown/keyboard.
  void _selectMapSearchResult(PlaceSearchResult result) {
    _mapSearchFocus.unfocus();
    setState(() {
      _pinLocation = result.location;
      _mapSearchResults = [];
      _mapSearchController.text = result.displayName;
    });
    _mapController.move(result.location, 15);
  }

  void _clearMapSearch() {
    setState(() {
      _mapSearchController.clear();
      _mapSearchResults = [];
    });
  }

  /// The small map box is too cramped to search or place a pin
  /// precisely - this opens the same picker full-screen instead.
  /// Whatever pin ends up set there (via search, "use my location,"
  /// or a direct tap) is handed back and applied to the small map too.
  Future<void> _openFullScreenMap() async {
    final result = await Navigator.of(context).push<LatLng?>(
      MaterialPageRoute(
        builder: (_) => FullScreenMapPickerScreen(initialLocation: _pinLocation),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _pinLocation = result);
    _mapController.move(result, 15);
  }

  // ---- Step 3: Basics ----
  Widget _stepBasics() {
    Widget counter(String label, int value, ValueChanged<int> onChanged,
        {int min = 1}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 14, color: AppColors.dark)),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.primary,
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            Text('$value',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dark)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.primary,
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      );
    }

    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell guests about the basics',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _titleController,
            label: 'Listing title',
            hint: 'e.g. Cozy Villa in Goa',
          ),
          const SizedBox(height: 16),
          counter('Bedrooms', _bedrooms, (v) => setState(() => _bedrooms = v)),
          counter('Bathrooms', _bathrooms, (v) => setState(() => _bathrooms = v)),
          counter('Max guests', _maxGuests, (v) => setState(() => _maxGuests = v),
              min: 1),
          const SizedBox(height: 12),
          const Text('Description',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descriptionController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'What makes your place special?',
            ),
          ),
        ],
      ),
    );
  }

  // ---- Step 4: Photos ----
  Widget _stepPhotos() {
    return CustomScrollView(
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add photos',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
                ),
                SizedBox(height: 6),
                Text(
                  'Add up to ${ListingService.maxPhotos} photos. The first photo is '
                  'your cover photo - drag to reorder. Minimum $kMinPhotosToPublish '
                  'required to publish.',
                  style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 16),
              ],
            ),
          ),
        ),
        if (_photos.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverReorderableList(
              itemCount: _photos.length,
              onReorder: _reorderPhotos,
              itemBuilder: (context, index) {
                final photo = _photos[index];
                return Padding(
                  key: ValueKey(photo.uploadedUrl ?? photo.localFile!.path),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.lightGrey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle, color: AppColors.grey),
                        ),
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: photo.isUploading
                                ? const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : photo.localFile != null
                                    ? Image.file(photo.localFile!, fit: BoxFit.cover)
                                    : CachedNetworkImage(
                                        imageUrl: photo.uploadedUrl!,
                                        fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            index == 0 ? 'Cover photo' : 'Photo ${index + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w500,
                              color: index == 0 ? AppColors.primary : AppColors.dark,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: AppColors.grey),
                          onPressed: () => _removePhoto(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          sliver: SliverToBoxAdapter(
            child: _photos.length < ListingService.maxPhotos
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  // ---- Step 5: Amenities ----
  Widget _stepAmenities() {
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What does your place offer?',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select everything that applies.',
            style: TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kAmenityOptions.map((a) {
              final selected = _amenities.contains(a);
              return FilterChip(
                label: Text(a),
                selected: selected,
                onSelected: (v) => setState(() {
                  if (v) {
                    _amenities.add(a);
                  } else {
                    _amenities.remove(a);
                  }
                }),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.dark,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.lightGrey),
                backgroundColor: AppColors.lightGrey,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---- Step 6: Pricing ----
  Widget _stepPricing() {
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Set your nightly price',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _priceController,
            label: 'Price per night (₹)',
            hint: 'e.g. 6000',
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  // ---- Step 7: Cancellation Policy ----
  Widget _stepCancellationPolicy() {
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a cancellation policy',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          const Text(
            "This is shown to guests before they book, and decides what "
            "they're refunded if they cancel.",
            style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          ...CancellationPolicyType.values.map((type) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _cancellationPolicyCard(type),
              )),
          if (_cancellationPolicyType == 'flexible') ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CustomTextField(
                    controller: _flexibleFreeDaysController,
                    label: 'Free up to (days before check-in)',
                    hint: 'e.g. 3',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomTextField(
                    controller: _flexibleFeePercentController,
                    label: 'Fee after that (%)',
                    hint: 'e.g. 100',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'e.g. free up to 3 days before check-in, 100% fee (no refund) '
              'after that, right up to check-in.',
              style: TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  /// One selectable cancellation-policy card - same radio-card pattern
  /// as _checkinMethodCard below, showing the policy's name and a
  /// live one-line summary of what it means (via
  /// CancellationPolicy.summaryFor, using whatever the host has typed
  /// into the Flexible fields so far).
  Widget _cancellationPolicyCard(CancellationPolicyType type) {
    final selected = _cancellationPolicyType == type.dbValue;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        _cancellationPolicyType = type.dbValue;
        if (type == CancellationPolicyType.flexible &&
            _flexibleFreeDaysController.text.trim().isEmpty) {
          _flexibleFreeDaysController.text =
              CancellationPolicy.flexibleDefaultFreeDays.toString();
          _flexibleFeePercentController.text =
              CancellationPolicy.flexibleDefaultFeePercent.toStringAsFixed(0);
        }
      }),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.lightGrey,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    CancellationPolicy.summaryFor(
                      type,
                      flexibleFreeDays:
                          int.tryParse(_flexibleFreeDaysController.text.trim()),
                      flexibleFeePercent: num.tryParse(
                          _flexibleFeePercentController.text.trim()),
                    ),
                    style: const TextStyle(
                        color: AppColors.grey, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.grey,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Step 8: House Rules ----
  Widget _stepHouseRules() {
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'House rules',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Check-in/check-out times, smoking/pet policy, quiet hours, etc.',
            style: TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _houseRulesController,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'e.g. Check-in after 2 PM, check-out by 11 AM. '
                  'No smoking indoors. Quiet hours after 10 PM.',
            ),
          ),
        ],
      ),
    );
  }

  // ---- Step 9: Highlights ----
  Widget _stepHighlights() {
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "What makes this place special?",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          const Text(
            "These show up right on your listing page - all optional, but "
            "a couple of standout points help guests decide faster.",
            style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('How do guests check in?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          const Text(
            "Select whichever matches, or choose \"Other\" and describe "
            "your own check-in method.",
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...kCheckinMethods.map((option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _checkinMethodCard(option),
              )),
          if (_checkinMethod != null) ...[
            const SizedBox(height: 4),
            TextFormField(
              controller: _checkinDetailsController,
              maxLength: 120,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: _checkinMethod == 'other'
                    ? 'Check-in details'
                    : 'Check-in details (optional)',
                hintText: _checkinMethod == 'other'
                    ? 'Describe how guests should check in at your place.'
                    : 'e.g. Code is 1234, keypad is by the front door.',
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 24),
          _highlightEditor(
            index: 1,
            titleController: _highlight1TitleController,
            descController: _highlight1DescController,
            hintTitle: 'e.g. Dive right in',
            hintDesc:
                'e.g. This is one of the few places in the area with a pool.',
          ),
          const SizedBox(height: 16),
          _highlightEditor(
            index: 2,
            titleController: _highlight2TitleController,
            descController: _highlight2DescController,
            hintTitle: 'e.g. Extra spacious',
            hintDesc: "e.g. Guests love this home's space for a comfortable "
                'stay.',
          ),
        ],
      ),
    );
  }

  /// One selectable check-in method card - tapping it selects that
  /// method, or deselects (back to "not set") if it's already the
  /// selected one, since a host may decide not to specify a method
  /// at all.
  Widget _checkinMethodCard(CheckinMethodOption option) {
    final selected = _checkinMethod == option.value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        _checkinMethod = selected ? null : option.value;
      }),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.lightGrey,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : AppColors.lightGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(option.icon,
                  size: 19,
                  color: selected ? AppColors.primary : AppColors.dark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(option.subtitle,
                      style: const TextStyle(
                          color: AppColors.grey, fontSize: 12, height: 1.3)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.grey,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  /// One editable highlight "card" - a headline field and a
  /// description field, same two-field shape Airbnb itself uses when
  /// a host edits one of their listing highlights. Deliberately no
  /// icon-picker here (unlike Airbnb) to keep this step quick to fill
  /// in - each custom highlight just uses a fixed sparkle icon on
  /// display (see PlaceDetailScreen).
  Widget _highlightEditor({
    required int index,
    required TextEditingController titleController,
    required TextEditingController descController,
    required String hintTitle,
    required String hintDesc,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.lightGrey),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 17, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Highlight $index',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: titleController,
            maxLength: 30,
            decoration: InputDecoration(
              labelText: 'Headline',
              hintText: hintTitle,
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: descController,
            maxLength: 90,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: hintDesc,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  // ---- Step 10: Review & Publish ----
  Widget _stepReview() {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: Text(label,
                    style: const TextStyle(color: AppColors.grey, fontSize: 13)),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        color: AppColors.dark, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review your listing',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 16),
          if (_photos.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final p = _photos[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: p.localFile != null
                          ? Image.file(p.localFile!, fit: BoxFit.cover)
                          : CachedNetworkImage(
                              imageUrl: p.uploadedUrl!, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          row('Type', _type ?? '—'),
          row('Title', _titleController.text.trim().isEmpty
              ? '—'
              : _titleController.text.trim()),
          row('City', _cityName ?? '—'),
          row('Address', _buildAddress().isEmpty ? '—' : _buildAddress()),
          row('Map pin', _pinLocation != null ? 'Dropped' : 'Not set (optional)'),
          row('Beds / Baths', '$_bedrooms / $_bathrooms'),
          row('Max guests', '$_maxGuests'),
          row('Price', _priceController.text.trim().isEmpty
              ? '—'
              : '₹${_priceController.text.trim()} / night'),
          row(
            'Cancellation',
            CancellationPolicyTypeX.fromDb(_cancellationPolicyType).label,
          ),
          row('Amenities', _amenities.isEmpty ? '—' : _amenities.join(', ')),
          row('Photos', '${_photos.where((p) => p.uploadedUrl != null).length}'),
          row('Check-in method',
              _checkinMethod == null
                  ? 'Not set'
                  : checkinMethodFor(_checkinMethod!).label),
          if (_highlight1TitleController.text.trim().isNotEmpty)
            row('Highlight 1', _highlight1TitleController.text.trim()),
          if (_highlight2TitleController.text.trim().isNotEmpty)
            row('Highlight 2', _highlight2TitleController.text.trim()),
          const SizedBox(height: 24),
          PrimaryButton(
            text: _isEditing ? 'Update & Publish' : 'Publish Listing',
            isLoading: _isBusy,
            onPressed: _publish,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _isBusy ? null : _saveDraftFromReview,
            child: const Text('Save as Draft'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
