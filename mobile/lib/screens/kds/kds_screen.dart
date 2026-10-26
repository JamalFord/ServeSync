import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/kds_ticket.dart';
import '../../services/app_state.dart';

class KDSScreen extends StatefulWidget {
  const KDSScreen({super.key});

  @override
  State<KDSScreen> createState() => _KDSScreenState();
}

class _KDSScreenState extends State<KDSScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final allTickets = appState.kdsTickets;
        final newTickets = allTickets.where((t) => t.status == TicketStatus.newOrder).toList();
        final prepTickets = allTickets.where((t) => t.status == TicketStatus.inPrep).toList();
        final readyTickets = allTickets.where((t) => t.status == TicketStatus.ready).toList();

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
                  child: const Icon(Icons.soup_kitchen_rounded, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KITCHEN DISPLAY (KDS)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppTheme.primary,
                      ),
                    ),
                    Text(
                      'Live Cooking Queue',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primary,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('New Orders'),
                      const SizedBox(width: 6),
                      _buildCountBadge(newTickets.length, AppTheme.primary),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('In Prep'),
                      const SizedBox(width: 6),
                      _buildCountBadge(prepTickets.length, AppTheme.statusYellow),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Ready'),
                      const SizedBox(width: 6),
                      _buildCountBadge(readyTickets.length, AppTheme.statusGreen),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTicketList(newTickets, 'No incoming orders right now', appState),
              _buildTicketList(prepTickets, 'No orders currently cooking', appState),
              _buildTicketList(readyTickets, 'No orders waiting for pickup', appState),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCountBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildTicketList(List<KDSTicket> tickets, String emptyMessage, AppState appState) {
    if (tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.done_all_rounded, size: 54, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tickets.length,
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        return _buildTicketCard(ticket, appState);
      },
    );
  }

  Widget _buildTicketCard(KDSTicket ticket, AppState appState) {
    // Urgency coloring
    Color timerColor = AppTheme.statusGreen;
    if (ticket.elapsedMinutes >= 15) {
      timerColor = AppTheme.statusRed;
    } else if (ticket.elapsedMinutes >= 8) {
      timerColor = AppTheme.statusYellow;
    }

    String actionLabel;
    IconData actionIcon;
    Color actionColor;

    switch (ticket.status) {
      case TicketStatus.newOrder:
        actionLabel = '🔥 Start Prep';
        actionIcon = Icons.soup_kitchen;
        actionColor = AppTheme.statusYellow;
        break;
      case TicketStatus.inPrep:
        actionLabel = '✅ Order Ready';
        actionIcon = Icons.check_circle_outline;
        actionColor = AppTheme.statusGreen;
        break;
      case TicketStatus.ready:
        actionLabel = '🛎️ Bump / Served';
        actionIcon = Icons.done_all;
        actionColor = AppTheme.primary;
        break;
      case TicketStatus.served:
        actionLabel = 'Archived';
        actionIcon = Icons.archive;
        actionColor = AppTheme.textMuted;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ticket.elapsedMinutes >= 15 ? AppTheme.statusRed : AppTheme.border,
          width: ticket.elapsedMinutes >= 15 ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Table # & Elapsed Timer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'TABLE ${ticket.tableNumber}',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Server: ${ticket.serverName}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),

                // Timer Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: timerColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: timerColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 12, color: timerColor),
                      const SizedBox(width: 4),
                      Text(
                        '${ticket.elapsedMinutes}m ago',
                        style: TextStyle(
                          color: timerColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(color: AppTheme.border, height: 20),

            // Order Items
            Column(
              children: ticket.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.quantity}x',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.modifications.isNotEmpty)
                              Text(
                                item.modifications,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.statusYellow,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Advance Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(actionIcon, size: 18),
                label: Text(
                  actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                onPressed: () {
                  appState.advanceKDSTicket(ticket.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(milliseconds: 600),
                      backgroundColor: AppTheme.surfaceElevated,
                      behavior: SnackBarBehavior.floating,
                      content: Text('Updated Ticket ${ticket.tableNumber}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
