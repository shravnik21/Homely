import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/services/availability_service.dart';

/// Shared Airbnb-style curved-bottom-sheet date range picker, used by
/// both the initial booking flow ([BookingScreen]) and rescheduling
/// an existing booking ([BookingDetailScreen]) - one place to keep
/// "grey out dates someone else already booked" behaviour consistent
/// between the two, instead of two near-identical calendars that
/// drift apart over time.
///
/// Fetches [placeId]'s already-booked dates via [AvailabilityService]
/// before rendering the calendar, disables tapping on them
/// (`enabledDayPredicate`), and gives them a grey look
/// (`disabledDecoration`/`disabledTextStyle`). Also rejects a range
/// that merely *spans over* a booked date in the middle, since
/// `enabledDayPredicate` alone only stops a booked date being picked
/// as the start/end point itself.
///
/// Returns the chosen range, or null if the sheet was dismissed
/// without saving.
Future<DateTimeRange?> showAvailabilityDatePicker({
  required BuildContext context,
  required String placeId,
  required String title,
  required String saveLabel,
  DateTime? initialStart,
  DateTime? initialEnd,
  String? excludeBookingId,
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => _AvailabilityDateSheet(
      placeId: placeId,
      title: title,
      saveLabel: saveLabel,
      initialStart: initialStart,
      initialEnd: initialEnd,
      excludeBookingId: excludeBookingId,
    ),
  );
}

class _AvailabilityDateSheet extends StatefulWidget {
  final String placeId;
  final String title;
  final String saveLabel;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String? excludeBookingId;

  const _AvailabilityDateSheet({
    required this.placeId,
    required this.title,
    required this.saveLabel,
    this.initialStart,
    this.initialEnd,
    this.excludeBookingId,
  });

  @override
  State<_AvailabilityDateSheet> createState() =>
      _AvailabilityDateSheetState();
}

class _AvailabilityDateSheetState extends State<_AvailabilityDateSheet> {
  late final Future<Set<DateTime>> _unavailableFuture;
  DateTime? _tempStart;
  DateTime? _tempEnd;

  @override
  void initState() {
    super.initState();
    _tempStart = widget.initialStart;
    _tempEnd = widget.initialEnd;
    _unavailableFuture = AvailabilityService().getUnavailableDates(
      widget.placeId,
      excludeBookingId: widget.excludeBookingId,
    );
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isUnavailable(DateTime day, Set<DateTime> blocked) =>
      blocked.contains(_dateOnly(day));

  /// A range is only valid if every night in it (check-in inclusive,
  /// check-out exclusive) is free - stops a guest picking, say, the
  /// 3rd and the 9th when someone else already has the 6th, even
  /// though the 3rd and the 9th are each individually open.
  bool _isRangeAvailable(DateTime start, DateTime end, Set<DateTime> blocked) {
    for (var d = _dateOnly(start);
        d.isBefore(_dateOnly(end));
        d = d.add(const Duration(days: 1))) {
      if (blocked.contains(d)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: FutureBuilder<Set<DateTime>>(
          future: _unavailableFuture,
          builder: (context, snapshot) {
            final loading =
                snapshot.connectionState == ConnectionState.waiting;
            final failed = snapshot.hasError;
            final blocked = snapshot.data ?? <DateTime>{};

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark,
                    ),
                  ),
                ),
                if (!loading && !failed && blocked.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Icon(Icons.circle,
                            size: 8, color: Color(0xFFBEBEBE)),
                        SizedBox(width: 6),
                        Text(
                          'Greyed-out dates are already booked',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (loading)
                  const SizedBox(
                    height: 320,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (failed)
                  const SizedBox(
                    height: 200,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Could not load availability for this place. '
                          'Please try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                  )
                else
                  TableCalendar(
                    firstDay: DateTime.now(),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _tempStart ?? DateTime.now(),
                    rangeStartDay: _tempStart,
                    rangeEndDay: _tempEnd,
                    rangeSelectionMode: RangeSelectionMode.toggledOn,
                    calendarFormat: CalendarFormat.month,
                    // This is what makes an already-booked date
                    // un-tappable as a start/end point.
                    enabledDayPredicate: (day) =>
                        !_isUnavailable(day, blocked),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    calendarStyle: const CalendarStyle(
                      rangeStartDecoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      rangeEndDecoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      withinRangeDecoration: BoxDecoration(
                        color: Color(0x22FF385C),
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: AppColors.lightGrey,
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(color: AppColors.dark),
                      // The "greyed-out and not selectable" look
                      // for already-booked dates.
                      disabledTextStyle:
                          TextStyle(color: Color(0xFFBEBEBE)),
                      disabledDecoration: BoxDecoration(
                        color: Color(0xFFF0F0F0),
                        shape: BoxShape.circle,
                      ),
                    ),
                    onRangeSelected: (start, end, focusedDay) {
                      if (start != null &&
                          end != null &&
                          !_isRangeAvailable(start, end, blocked)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Some nights in that range are already "
                              "booked - try a different range.",
                            ),
                          ),
                        );
                        return;
                      }
                      // setState on the sheet's own State (not a nested
                      // StatefulBuilder) so the "Save dates" button
                      // below - which lives outside this widget - is
                      // rebuilt too and reflects the new selection.
                      setState(() {
                        _tempStart = start;
                        _tempEnd = end;
                      });
                    },
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_tempStart != null && _tempEnd != null)
                        ? () => Navigator.of(context).pop(
                              DateTimeRange(
                                  start: _tempStart!, end: _tempEnd!),
                            )
                        : null,
                    child: Text(widget.saveLabel),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
