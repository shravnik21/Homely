import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/config/checkin_methods.dart';
import 'package:homely_app/services/listing_service.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';
import 'package:homely_app/utils/network_error_helper.dart';

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
/// pricing -> house rules -> review & publish.
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

  List<Map<String, dynamic>> _cities = [];
  String? _cityId;
  String? _cityName;
  // Address is collected as separate, Airbnb-style fields for a much
  // clearer entry experience, then joined into a single string right
  // before it's saved - the `address` column in the DB stays exactly
  // as it was, no schema change needed.
  final _flatController = TextEditingController(); // Flat/House no., Building/Society
  final _streetController = TextEditingController(); // Street / Area / Locality
  final _landmarkController = TextEditingController(); // optional
  final _pincodeController = TextEditingController(); // optional

  final _titleController = TextEditingController();
  int _bedrooms = 1;
  int _bathrooms = 1;
  int _maxGuests = 2;
  final _descriptionController = TextEditingController();

  final List<_WizardPhoto> _photos = [];

  final Set<String> _amenities = {};

  final _priceController = TextEditingController();

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
    _loadCities();
    if (widget.existingPlace != null) _prefillFrom(widget.existingPlace!);
  }

  void _prefillFrom(Place place) {
    _placeId = place.id;
    _type = place.type;
    _cityId = place.cityId;
    _cityName = place.cityName.isEmpty ? null : place.cityName;
    // The DB only ever stored one joined address string, so there are
    // no separate components to recover here - drop the saved value
    // into the Street / Area field as a sensible best-effort default
    // and let the host redistribute it across the new fields if they
    // want to; nothing is lost, it's just no longer pre-split.
    _streetController.text = place.address;
    _titleController.text =
        place.title == 'Untitled listing' ? '' : place.title;
    _bedrooms = place.bedrooms;
    _bathrooms = place.bathrooms;
    _maxGuests = place.maxGuests;
    _descriptionController.text = place.description;
    _amenities.addAll(place.amenities);
    _priceController.text =
        place.pricePerNight > 0 ? place.pricePerNight.toStringAsFixed(0) : '';
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

  Future<void> _loadCities() async {
    final cities = await _listingService.getCities();
    if (mounted) setState(() => _cities = cities);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _flatController.dispose();
    _streetController.dispose();
    _landmarkController.dispose();
    _pincodeController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
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

    if (_currentStep == 0) {
      // Step 0 has to block: it creates the place row that every
      // later step (photo uploads especially) needs a real id for.
      setState(() => _isBusy = true);
      try {
        await _persistStep(0);
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

  void _goBack() {
    if (_currentStep == 0) {
      Navigator.of(context).pop();
      return;
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
        if (_cityId == null) return 'Please select a city to continue';
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
        if (_houseRulesController.text.trim().isEmpty) {
          return 'Please enter your house rules to continue';
        }
        return null;
      case 7:
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
        await _listingService.updateListing(_placeId!, {
          'city_id': _cityId,
          'address': _buildAddress(),
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
        await _listingService.updateListing(
            _placeId!, {'house_rules': _houseRulesController.text.trim()});
        break;
      case 7:
        String? orNull(TextEditingController c) {
          final t = c.text.trim();
          return t.isEmpty ? null : t;
        }
        await _listingService.updateListing(_placeId!, {
          'checkin_method': _checkinMethod,
          'checkin_details': orNull(_checkinDetailsController),
          'highlight1_title': orNull(_highlight1TitleController),
          'highlight1_description': orNull(_highlight1DescController),
          'highlight2_title': orNull(_highlight2TitleController),
          'highlight2_description': orNull(_highlight2DescController),
        });
        break;
    }
  }

  Future<void> _saveAndExit() async {
    setState(() => _isBusy = true);
    try {
      // Only persist the current step if it has something worth
      // saving (step 0 requires a type; every other step is
      // optional-safe to persist as-is, even blank).
      if (_currentStep != 0 || _type != null) {
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
      description: _descriptionController.text.trim(),
      amenities: _amenities.toList(),
      photoUrls: _photos
          .where((p) => p.uploadedUrl != null)
          .map((p) => p.uploadedUrl!)
          .toList(),
      houseRules: _houseRulesController.text.trim(),
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
      await _persistStep(2);
      await _persistStep(4);
      await _persistStep(5);
      await _persistStep(6);
      await _persistStep(7);
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
      await _persistStep(2);
      await _persistStep(4);
      await _persistStep(5);
      await _persistStep(6);
      await _persistStep(7);
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
    return Scaffold(
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
            'For now, listings can be added in these 5 destinations. '
            'Dropping a pin on a map is coming in a future update.',
            style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('City',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _cities.map((c) {
              final selected = _cityId == c['id'];
              return ChoiceChip(
                label: Text(c['name'] as String),
                selected: selected,
                onSelected: (_) => setState(() {
                  _cityId = c['id'] as String;
                  _cityName = c['name'] as String;
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
        ],
      ),
    );
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

  // ---- Step 7: House Rules ----
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

  // ---- Step 8: Highlights ----
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

  // ---- Step 9: Review & Publish ----
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
          row('Beds / Baths', '$_bedrooms / $_bathrooms'),
          row('Max guests', '$_maxGuests'),
          row('Price', _priceController.text.trim().isEmpty
              ? '—'
              : '₹${_priceController.text.trim()} / night'),
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
