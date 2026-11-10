import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-7 / UC-03: reservation management. All signed-in staff can use it.
class ReservationsScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const ReservationsScreen({super.key, this.api});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> with ManageLoader {
  late final ApiClient _api = widget.api ?? AppState.instance.api;
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _tables = [];

  @override
  Future<void> fetch() async {
    final results = await Future.wait([
      _api.reservations(date: isoDay(_day)),
      if (_tables.isEmpty) _api.diningTables(),
    ]);
    _rows = results[0]..sort((a, b) => strOf(a['reservation_time']).compareTo(strOf(b['reservation_time'])));
    if (results.length > 1) _tables = results[1];
  }

  void _setDay(DateTime day) {
    _day = DateUtils.dateOnly(day);
    reload();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) _setDay(picked);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Confirmed':
        return AppTheme.statusBlue;
      case 'Seated':
        return AppTheme.statusGreen;
      case 'No-Show':
        return AppTheme.statusRed;
      default:
        return AppTheme.textMuted; // Cancelled
    }
  }

  Future<void> _setStatus(Map<String, dynamic> r, String status) async {
    final id = intOf(r['reservation_id']);
    final guest = strOf(r['guest_name'], 'this guest');
    if (status != 'Seated') {
      final ok = await confirmAction(
        context,
        title: status == 'Cancelled' ? 'Cancel reservation?' : 'Mark as no-show?',
        message: status == 'Cancelled'
            ? 'The reservation for $guest at ${formatClock(r['reservation_time'])} will be cancelled and the table freed. This cannot be undone.'
            : '$guest did not arrive for the ${formatClock(r['reservation_time'])} reservation. The table will be freed. This cannot be undone.',
        confirmLabel: status == 'Cancelled' ? 'Cancel reservation' : 'Mark no-show',
        danger: true,
      );
      if (!ok) return;
    }
    await act(() => _api.setReservationStatus(id, status), success: '$guest: $status');
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    if (_tables.isEmpty) {
      showMessage(context, 'No dining tables are set up, so a reservation cannot be made.', error: true);
      return;
    }
    final guest = TextEditingController(text: strOf(existing?['guest_name']));
    final phone = TextEditingController(text: strOf(existing?['phone_number']));
    final party = TextEditingController(text: existing == null ? '2' : '${intOf(existing['party_size'])}');
    final notes = TextEditingController(text: strOf(existing?['notes']));
    DateTime day = existing == null ? _day : (DateTime.tryParse(strOf(existing['reservation_date'])) ?? _day);
    TimeOfDay time = const TimeOfDay(hour: 18, minute: 0);
    if (existing != null) {
      final parts = strOf(existing['reservation_time']).split(':');
      if (parts.length >= 2) {
        time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 18, minute: int.tryParse(parts[1]) ?? 0);
      }
    }
    int? table = existing == null ? null : intOf(existing['table_number']);
    String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final saved = await showFormDialog(
      context,
      title: existing == null ? 'New reservation' : 'Edit reservation',
      subtitle: 'The table is held for 90 minutes from the reservation time.',
      submitLabel: existing == null ? 'Book table' : 'Save changes',
      fields: (setDialog) => [
        FormTextField(label: 'Guest name', controller: guest, maxLength: 100),
        FormTextField(label: 'Phone number', controller: phone, keyboardType: TextInputType.phone, hint: '404-555-0100', maxLength: 20),
        FormTextField(label: 'Party size', controller: party, keyboardType: TextInputType.number, digitsOnly: true, maxLength: 2),
        const FormLabel('Date and time'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_rounded, size: 14),
                label: Text(isoDay(day), style: const TextStyle(fontSize: 13)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setDialog(() => day = picked);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 14),
                label: Text('${hhmm(time)}  (${formatClock(hhmm(time))})', style: const TextStyle(fontSize: 13)),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: time);
                  if (picked != null) setDialog(() => time = picked);
                },
              ),
            ),
          ],
        ),
        FormDropdown<int>(
          label: 'Table',
          value: table,
          options: [for (final t in _tables) intOf(t['table_number'])],
          labelOf: (n) {
            final t = _tables.firstWhere((t) => intOf(t['table_number']) == n);
            return 'Table $n (seats ${intOf(t['capacity'])})';
          },
          onChanged: (v) => setDialog(() => table = v),
        ),
        FormTextField(label: 'Notes (optional)', controller: notes, hint: 'Birthday, high chair, allergy', maxLength: 255),
      ],
      onSubmit: () async {
        final size = int.tryParse(party.text.trim());
        if (guest.text.trim().isEmpty) return 'Guest name is required.';
        if (phone.text.trim().isEmpty) return 'Phone number is required.';
        if (size == null || size < 1) return 'Party size must be a whole number of at least 1.';
        if (table == null) return 'Choose a table.';
        final body = <String, dynamic>{
          'guest_name': guest.text.trim(),
          'phone_number': phone.text.trim(),
          'party_size': size,
          'reservation_date': isoDay(day),
          'reservation_time': hhmm(time),
          'table_number': table,
          'notes': notes.text.trim(),
        };
        return guard(() => existing == null
            ? _api.createReservation(body)
            : _api.updateReservation(intOf(existing['reservation_id']), body));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, existing == null ? 'Reservation booked for ${guest.text.trim()}.' : 'Reservation updated.');
    if (!DateUtils.isSameDay(day, _day)) {
      _setDay(day); // show the day the reservation is on
    } else {
      await reload(showSpinner: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _rows.where((r) => r['status'] == 'Confirmed' || r['status'] == 'Seated').toList();
    final guests = active.fold<int>(0, (sum, r) => sum + intOf(r['party_size']));
    final isToday = DateUtils.isSameDay(_day, DateTime.now());

    return ManageScaffold(
      eyebrow: 'FR-7 · UC-03',
      title: 'Reservations',
      icon: Icons.event_seat_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New reservation', style: TextStyle(fontWeight: FontWeight.w800)),
        onPressed: () => _openForm(),
      ),
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          // Day selector
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Previous day',
                  onPressed: () => _setDay(_day.subtract(const Duration(days: 1))),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _pickDay,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Text(
                            isToday ? 'Today' : formatDay(_day),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${isToday ? '${formatDay(_day)} · ' : ''}${active.length} active · $guests guests',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!isToday)
                  TextButton(onPressed: () => _setDay(DateTime.now()), child: const Text('Today', style: TextStyle(fontSize: 12))),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Next day',
                  onPressed: () => _setDay(_day.add(const Duration(days: 1))),
                ),
              ],
            ),
          ),
          if (_rows.isEmpty)
            const EmptyState(Icons.event_available_rounded, 'No reservations for this day.\nUse "New reservation" to book a table.'),
          for (final r in _rows) _reservationCard(r),
        ],
      ),
    );
  }

  Widget _reservationCard(Map<String, dynamic> r) {
    final status = strOf(r['status'], 'Confirmed');
    final color = _statusColor(status);
    final confirmed = status == 'Confirmed';
    final notes = strOf(r['notes']);
    return ManageCard(
      borderColor: confirmed ? color.withOpacity(0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatClock(r['reservation_time'])} – ${formatClock(r['end_time'])}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryLight),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(status, color),
            ],
          ),
          const SizedBox(height: 6),
          Text(strOf(r['guest_name'], 'Guest'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            'Party of ${intOf(r['party_size'])} · Table ${intOf(r['table_number'])} · ${strOf(r['phone_number'], 'no phone')}',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Notes: $notes', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
          ],
          if (confirmed) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                CardAction('Seat', Icons.chair_rounded, () => _setStatus(r, 'Seated'), color: AppTheme.statusGreen),
                CardAction('Edit', Icons.edit_outlined, () => _openForm(r)),
                CardAction('No-show', Icons.person_off_outlined, () => _setStatus(r, 'No-Show'), color: AppTheme.statusYellow),
                CardAction('Cancel', Icons.close_rounded, () => _setStatus(r, 'Cancelled'), color: AppTheme.statusRed),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
