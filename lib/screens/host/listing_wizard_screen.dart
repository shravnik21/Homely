import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/place.dart';
import 'package:homely_app/services/listing_service.dart';
import 'package:homely_app/widgets/custom_textfield.dart';
import 'package:homely_app/widgets/primary_button.dart';

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

const int kMinPhotosToPublish = 3;

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
  final _addressController = TextEditingController();

  final _titleController = TextEditingController();
  int _bedrooms = 1;
  int _bathrooms = 1;
  int _maxGuests = 2;
  final _descriptionController = TextEditingController();

  final List<_WizardPhoto> _photos = [];

  final Set<String> _amenities = {};

  final _priceController = TextEditingController();

  final _houseRulesController = TextEditingController();

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
    _addressController.text = place.address;
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
    for (final url in place.photoUrls) {
      _photos.add(_WizardPhoto(uploadedUrl: url));
    }
  }

  Future<void> _loadCities() async {
    final cities = await _listingService.getCities();
    if (mounted) setState(() => _cities = cities);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _addressController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _houseRulesController.dispose();
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
    setState(() {
      _stepError = null;
      _isBusy = true;
    });
    try {
      await _persistStep(_currentStep);
      if (!mounted) return;
      if (_currentStep == _stepTitles.length - 1) return; // handled by Publish
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } catch (e) {
      if (mounted) setState(() => _stepError = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
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
        if (_addressController.text.trim().isEmpty) {
          return 'Please enter an address to continue';
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
          'address': _addressController.text.trim(),
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
          SnackBar(content: Text('Could not save draft: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _publish() async {
    final missing = <String>[];
    if (_titleController.text.trim().isEmpty) missing.add('a title');
    if (_cityId == null) missing.add('a city');
    if (_addressController.text.trim().isEmpty) missing.add('an address');
    if (_descriptionController.text.trim().isEmpty) missing.add('a description');
    if ((num.tryParse(_priceController.text.trim()) ?? 0) <= 0) {
      missing.add('a nightly price');
    }
    final photoCount = _photos.where((p) => p.uploadedUrl != null).length;
    if (photoCount < kMinPhotosToPublish) {
      missing.add('at least $kMinPhotosToPublish photos');
    }

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
      await _listingService.publishListing(_placeId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing published!')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _stepError = 'Could not publish: $e');
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
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
        SnackBar(content: Text('Upload failed: $e')),
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
                  color: AppColors.error.withOpacity(0.08),
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
                selectedColor: AppColors.primary.withOpacity(0.15),
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
                selectedColor: AppColors.primary.withOpacity(0.15),
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
          CustomTextField(
            controller: _addressController,
            label: 'Address / area',
            hint: 'e.g. Calangute, near the beach road',
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
    return _sectionWrap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add photos',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          Text(
            'Add up to ${ListingService.maxPhotos} photos. The first photo is '
            'your cover photo - drag to reorder. Minimum $kMinPhotosToPublish '
            'required to publish.',
            style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_photos.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
                        const Icon(Icons.drag_handle, color: AppColors.grey),
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
          if (_photos.length < ListingService.maxPhotos)
            Row(
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
            ),
        ],
      ),
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
                selectedColor: AppColors.primary.withOpacity(0.15),
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

  // ---- Step 8: Review & Publish ----
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
          row('Address', _addressController.text.trim().isEmpty
              ? '—'
              : _addressController.text.trim()),
          row('Beds / Baths', '$_bedrooms / $_bathrooms'),
          row('Max guests', '$_maxGuests'),
          row('Price', _priceController.text.trim().isEmpty
              ? '—'
              : '₹${_priceController.text.trim()} / night'),
          row('Amenities', _amenities.isEmpty ? '—' : _amenities.join(', ')),
          row('Photos', '${_photos.where((p) => p.uploadedUrl != null).length}'),
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
