import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';

/// Shared helpers for the Manage screens (reservations, customer service,
/// suppliers, user accounts, payroll, hiring).

// --- Value parsing -----------------------------------------------------------
// The API sends DECIMAL columns as strings ("38.50") and timestamps as naive
// UTC ("2026-11-08 03:54:17"), so everything is parsed defensively.

double numOf(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

int intOf(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? numOf(v).toInt();

String strOf(dynamic v, [String fallback = '']) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

String money(dynamic v) => '\$${numOf(v).toStringAsFixed(2)}';

/// Parses a server timestamp (naive UTC) and returns it in local time.
DateTime? serverTime(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim().replaceFirst(' ', 'T');
  if (s.isEmpty) return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toLocal();
}

String formatDateTime(DateTime? d, [String fallback = '—']) =>
    d == null ? fallback : DateFormat('MMM d, h:mm a').format(d);

String formatDay(DateTime d) => DateFormat('EEE, MMM d, yyyy').format(d);

/// YYYY-MM-DD, the format the API expects for dates.
String isoDay(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// "18:30" -> "6:30 PM". Returns the input unchanged if it is not HH:MM.
String formatClock(dynamic hhmm) {
  final parts = strOf(hhmm).split(':');
  if (parts.length < 2) return strOf(hhmm);
  final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  if (h == null || m == null) return strOf(hhmm);
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
}

String apiMessage(Object e) => e is ApiException ? e.message : 'Something went wrong. ($e)';

/// Runs an API call and returns null on success or the message to show.
Future<String?> guard(Future<dynamic> Function() call) async {
  try {
    await call();
    return null;
  } catch (e) {
    return apiMessage(e);
  }
}

bool get currentIsAdmin => AppState.instance.currentEmployee?.isAdmin == true;
bool get currentIsManager => AppState.instance.currentEmployee?.isManager == true;

// --- Messages and confirmation -------------------------------------------------

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: error ? AppTheme.statusRed : AppTheme.statusGreen,
      duration: Duration(seconds: error ? 5 : 3),
      content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    ));
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Text(message, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.35)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: danger ? AppTheme.statusRed : AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result == true;
}

/// A dialog holding a form. [onSubmit] returns null on success (the dialog
/// closes and this returns true) or an error message, which is shown inside
/// the dialog so the user can correct the form.
Future<bool> showFormDialog(
  BuildContext context, {
  required String title,
  required List<Widget> Function(StateSetter setState) fields,
  required Future<String?> Function() onSubmit,
  String submitLabel = 'Save',
  String? subtitle,
}) async {
  String? error;
  bool busy = false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...fields(setState),
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.statusRed.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.statusRed.withOpacity(0.6)),
                  ),
                  child: Text(error!, style: TextStyle(fontSize: 12, color: AppTheme.statusRed, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    final message = await onSubmit();
                    if (!ctx.mounted) return;
                    if (message == null) {
                      Navigator.pop(ctx, true);
                    } else {
                      setState(() {
                        busy = false;
                        error = message;
                      });
                    }
                  },
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(submitLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

// --- Form fields ---------------------------------------------------------------

class FormLabel extends StatelessWidget {
  final String text;
  const FormLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
      );
}

class FormTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final bool obscure;
  final bool digitsOnly;

  const FormTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.obscure = false,
    this.digitsOnly = false,
  });

  /// A numeric field that accepts decimals (hours, rates, quantities).
  const FormTextField.decimal({super.key, required this.label, required this.controller, this.hint})
      : keyboardType = const TextInputType.numberWithOptions(decimal: true),
        maxLines = 1,
        maxLength = null,
        obscure = false,
        digitsOnly = false;

  /// A four-digit PIN field. The value is hidden while typing.
  const FormTextField.pin({super.key, required this.label, required this.controller})
      : hint = 'Four digits',
        keyboardType = TextInputType.number,
        maxLines = 1,
        maxLength = 4,
        obscure = true,
        digitsOnly = true;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormLabel(label),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            maxLength: maxLength,
            obscureText: obscure,
            inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(hintText: hint, isDense: true, counterText: ''),
          ),
        ],
      );
}

class FormDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const FormDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormLabel(label),
          DropdownButtonFormField<T>(
            value: options.contains(value) ? value : null,
            isExpanded: true,
            isDense: true,
            dropdownColor: AppTheme.surfaceElevated,
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final o in options) DropdownMenuItem<T>(value: o, child: Text(labelOf(o), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onChanged,
          ),
        ],
      );
}

// --- Layout pieces -------------------------------------------------------------

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: 0.8),
        ),
        child: Text(label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
      );
}

class ManageCard extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  const ManageCard({super.key, required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor ?? AppTheme.border),
        ),
        child: child,
      );
}

/// A small outlined action button used in card footers.
class CardAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  const CardAction(this.label, this.icon, this.onPressed, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryLight;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withOpacity(0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      onPressed: onPressed,
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String text;
  const SectionHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppTheme.textSecondary),
        ),
      );
}

/// A row of filter chips where exactly one value is selected.
class FilterChips extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final Map<String, int>? counts;
  const FilterChips({super.key, required this.options, required this.selected, required this.onSelected, this.counts});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(counts == null ? o : '$o (${counts![o] ?? 0})'),
                  selected: o == selected,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppTheme.surfaceElevated,
                  selectedColor: AppTheme.primary.withOpacity(0.25),
                  side: BorderSide(color: o == selected ? AppTheme.primary : AppTheme.border),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: o == selected ? AppTheme.primaryLight : AppTheme.textSecondary,
                  ),
                  onSelected: (_) => onSelected(o),
                ),
              ),
          ],
        ),
      );
}

/// Page frame used by every Manage screen: a titled app bar, a refresh button
/// and a body that shows loading, a load error with Retry, or the content.
class ManageScaffold extends StatelessWidget {
  final String eyebrow;
  final String title;
  final IconData icon;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final Widget Function() builder;
  final Widget? floatingActionButton;

  const ManageScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.builder,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 44, color: AppTheme.textMuted),
              const SizedBox(height: 10),
              Text(error!, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
                onPressed: onRefresh,
              ),
            ],
          ),
        ),
      );
    } else {
      body = RefreshIndicator(color: AppTheme.primary, onRefresh: onRefresh, child: builder());
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.primaryLight, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppTheme.primary),
                  ),
                  Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: loading ? null : onRefresh),
        ],
      ),
      body: body,
      floatingActionButton: (loading || error != null) ? null : floatingActionButton,
    );
  }
}

/// Shown inside a scrollable list when there is nothing to list, so pull-to-refresh still works.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState(this.icon, this.message, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 44, color: AppTheme.textMuted),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );
}

/// Loading / error state shared by the Manage screens.
///
/// A screen implements [fetch] to read its data from the API and store it in
/// its own fields; [reload] runs it and tracks [loading] and [loadError].
mixin ManageLoader<T extends StatefulWidget> on State<T> {
  bool loading = true;
  String? loadError;

  Future<void> fetch();

  @override
  void initState() {
    super.initState();
    reload(showSpinner: false); // `loading` already starts as true
  }

  Future<void> reload({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => loading = true);
    String? message;
    try {
      await fetch();
    } catch (e) {
      message = apiMessage(e);
    }
    if (!mounted) return;
    setState(() {
      loading = false;
      loadError = message;
    });
  }

  /// Runs a change, shows the result, and refreshes the list.
  Future<void> act(Future<dynamic> Function() call, {String? success}) async {
    final message = await guard(call);
    if (!mounted) return;
    if (message != null) {
      showMessage(context, message, error: true);
    } else if (success != null) {
      showMessage(context, success);
    }
    await reload(showSpinner: false);
  }
}
