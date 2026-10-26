import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';

class ShiftsScreen extends StatelessWidget {
  final VoidCallback? onSwitchUser;

  const ShiftsScreen({super.key, this.onSwitchUser});

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final currentEmp = appState.currentEmployee;
        final isClockedIn = currentEmp?.isClockedIn ?? false;
        final clockInTime = currentEmp?.clockInTime;

        String shiftDurationText = '0h 0m';
        double grossEarned = 0.0;
        if (isClockedIn && clockInTime != null) {
          final diff = DateTime.now().difference(clockInTime);
          final hours = diff.inHours;
          final mins = diff.inMinutes % 60;
          shiftDurationText = '${hours}h ${mins}m';
          grossEarned = (diff.inMinutes / 60.0) * (currentEmp?.hourlyRate ?? 16.50);
        }

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
                  child: const Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                const Column(
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
                      'Shift Clock-In (UC-01)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                // Active User Card
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
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary),
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
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
                                  const Text('Shift Elapsed', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
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
                                  const Text('Gross Earned', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\$${grossEarned.toStringAsFixed(2)}',
                                    style: const TextStyle(
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
                const Text(
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
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
