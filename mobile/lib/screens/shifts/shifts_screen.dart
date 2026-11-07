import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';

class ShiftsScreen extends StatefulWidget {
  final VoidCallback? onSwitchUser;

  const ShiftsScreen({super.key, this.onSwitchUser});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  int _selectedView = 0; // 0 = My Shift Clock, 1 = Manager Payroll

  void _showEditRateDialog(BuildContext context, AppState appState, String empId, String name, double currentRate) {
    final controller = TextEditingController(text: currentRate.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          title: Text(
            'Adjust Hourly Rate for $name',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the updated base wage per hour for payroll auditing:',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  labelText: 'Hourly Wage Rate',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () {
                final newRate = double.tryParse(controller.text.trim());
                if (newRate != null && newRate > 0) {
                  appState.updateEmployeeHourlyRate(empId, newRate);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Updated $name wage rate to \$${newRate.toStringAsFixed(2)}/hr'),
                      backgroundColor: AppTheme.statusGreen,
                    ),
                  );
                }
              },
              child: const Text('Save Rate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final currentEmp = appState.currentEmployee;
        final isClockedIn = currentEmp?.isClockedIn ?? false;
        final clockInTime = currentEmp?.clockInTime;
        final isManagerOrAdmin = currentEmp?.isManager == true || currentEmp?.isAdmin == true;

        String shiftDurationText = '0h 0m';
        double grossEarned = 0.0;
        if (isClockedIn && clockInTime != null) {
          final diff = DateTime.now().difference(clockInTime);
          final hours = diff.inHours;
          final mins = diff.inMinutes % 60;
          shiftDurationText = '${hours}h ${mins}m';
          grossEarned = (diff.inMinutes / 60.0) * (currentEmp?.hourlyRate ?? 16.50);
        }

        // Calculate Team Labor Metrics
        final clockedInCount = appState.employees.where((e) => e.isClockedIn).length;
        final totalActiveLaborToday = appState.employees.fold(0.0, (sum, e) {
          if (!e.isClockedIn || e.clockInTime == null) return sum;
          final diff = DateTime.now().difference(e.clockInTime!);
          return sum + ((diff.inMinutes / 60.0) * e.hourlyRate);
        });
        final totalWeeklyEst = appState.employees.fold(0.0, (sum, e) => sum + (e.hourlyRate * 38.0));

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAYROLL & TIME TRACKING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppTheme.primary,
                      ),
                    ),
                    Text(
                      _selectedView == 0 ? 'Shift Clock-In (UC-01)' : 'Team Payroll (FR-04)',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top View Switcher (My Shift vs Manager Payroll)
                if (isManagerOrAdmin) ...[
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedView = 0),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: _selectedView == 0 ? AppTheme.surfaceElevated : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_pin_circle_rounded,
                                    size: 16,
                                    color: _selectedView == 0 ? AppTheme.primary : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'My Shift Clock',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _selectedView == 0 ? FontWeight.w800 : FontWeight.w600,
                                      color: _selectedView == 0 ? AppTheme.textPrimary : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedView = 1),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: _selectedView == 1 ? AppTheme.surfaceElevated : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.payments_rounded,
                                    size: 16,
                                    color: _selectedView == 1 ? AppTheme.primary : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Manager Payroll',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _selectedView == 1 ? FontWeight.w800 : FontWeight.w600,
                                      color: _selectedView == 1 ? AppTheme.textPrimary : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_selectedView == 0) ...[
                  // ==========================================
                  // VIEW 0: MY SHIFT CLOCK
                  // ==========================================
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isClockedIn ? AppTheme.statusGreen.withOpacity(0.5) : AppTheme.border,
                        width: isClockedIn ? 1.5 : 1.0,
                      ),
                      boxShadow: isClockedIn
                          ? [
                              BoxShadow(
                                color: AppTheme.statusGreen.withOpacity(0.1),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppTheme.surfaceElevated,
                                  child: Text(
                                    currentEmp?.name.substring(0, 1) ?? 'U',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentEmp?.name ?? 'Unknown',
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                    ),
                                    Text(
                                      '${currentEmp?.role} • \$${currentEmp?.hourlyRate.toStringAsFixed(2)}/hr',
                                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isClockedIn
                                    ? AppTheme.statusGreen.withOpacity(0.15)
                                    : AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isClockedIn ? AppTheme.statusGreen : AppTheme.border,
                                ),
                              ),
                              child: Text(
                                isClockedIn ? 'ON SHIFT' : 'OFF SHIFT',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isClockedIn ? AppTheme.statusGreen : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // Metrics Row
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceElevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Shift Elapsed', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                    const SizedBox(height: 2),
                                    Text(
                                      shiftDurationText,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceElevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Gross Earned', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '\$${grossEarned.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.statusGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Big Clock In / Clock Out Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isClockedIn ? AppTheme.statusRed : AppTheme.statusGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: Icon(isClockedIn ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                            label: Text(
                              isClockedIn ? 'Clock Out of Shift' : 'Clock In to Shift',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            onPressed: () {
                              appState.toggleShift();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isClockedIn
                                        ? 'Clocked out. Shift record logged for payroll.'
                                        : 'Clocked in! Shift active.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Team Roster Header
                  Text(
                    'TEAM ROSTER & STATUS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Employee Cards
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: appState.employees.length,
                    itemBuilder: (context, index) {
                      final emp = appState.employees[index];
                      final isCurrent = emp.id == currentEmp?.id;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: AppTheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isCurrent ? AppTheme.primary.withOpacity(0.5) : AppTheme.border,
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.surfaceElevated,
                            child: Text(
                              emp.name.substring(0, 1),
                              style: TextStyle(
                                color: emp.isAdmin
                                    ? AppTheme.primary
                                    : emp.isManager
                                        ? AppTheme.statusYellow
                                        : AppTheme.statusGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            emp.name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          subtitle: Text(
                            '${emp.role} • PIN: ${emp.pin}',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: emp.isClockedIn
                                  ? AppTheme.statusGreen.withOpacity(0.12)
                                  : AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              emp.isClockedIn ? 'Active' : 'Off Shift',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: emp.isClockedIn ? AppTheme.statusGreen : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ] else ...[
                  // ==========================================
                  // VIEW 1: MANAGER PAYROLL PORTAL (FR-04)
                  // ==========================================
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Active Labor Today', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              const SizedBox(height: 4),
                              Text(
                                '\$${totalActiveLaborToday.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.statusGreen,
                                ),
                              ),
                              Text('$clockedInCount staff on clock', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Weekly Est. Payroll', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              const SizedBox(height: 4),
                              Text(
                                '\$${totalWeeklyEst.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              ),
                              Text('Target: < 25% of sales', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'STAFF PAYROLL ROSTER & WAGE AUDIT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.surfaceElevated,
                          foregroundColor: AppTheme.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: AppTheme.border),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: const Text('Export Audit Log', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.surfaceElevated,
                              content: const Text(
                                'Payroll audit record (FR-04) generated for Period #45.',
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Payroll Detail Cards
                  ...appState.employees.map((emp) {
                    final weeklyHours = emp.role == 'Administrator'
                        ? 38.5
                        : emp.role == 'Manager'
                            ? 42.0
                            : 28.5;
                    final grossPay = weeklyHours * emp.hourlyRate;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppTheme.surfaceElevated,
                                    child: Text(
                                      emp.name.substring(0, 1),
                                      style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        emp.name,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                      Text(
                                        emp.role,
                                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  side: BorderSide(color: AppTheme.primaryLight.withOpacity(0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 12),
                                label: const Text('Edit Rate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                onPressed: () => _showEditRateDialog(context, appState, emp.id, emp.name, emp.hourlyRate),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Hourly Wage', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                    Text(
                                      '\$${emp.hourlyRate.toStringAsFixed(2)}/hr',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Period Hours', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                    Text(
                                      '${weeklyHours.toStringAsFixed(1)} hrs',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Gross Wages', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                    Text(
                                      '\$${grossPay.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: AppTheme.statusGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
