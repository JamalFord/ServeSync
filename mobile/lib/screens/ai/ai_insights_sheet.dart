import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';

class AIInsightsSheet extends StatefulWidget {
  const AIInsightsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AIInsightsSheet(),
    );
  }

  @override
  State<AIInsightsSheet> createState() => _AIInsightsSheetState();
}

class _AIInsightsSheetState extends State<AIInsightsSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _promptController = TextEditingController();
  final List<Map<String, String>> _chatHistory = [
    {
      'role': 'assistant',
      'content': 'Hello! I am ServeSync AI, your real-time restaurant operations copilot. I analyze live POS sales, kitchen ticket velocity, inventory stock, and labor costs. How can I help your shift today?'
    }
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _sendQuery(String prompt) {
    if (prompt.trim().isEmpty) return;
    final userQuery = prompt.trim();
    _promptController.clear();

    setState(() {
      _chatHistory.add({'role': 'user', 'content': userQuery});
    });

    // Generate intelligent restaurant copilot response based on query
    Future.delayed(const Duration(milliseconds: 500), () {
      final lower = userQuery.toLowerCase();
      String response = '';

      if (lower.contains('profit') || lower.contains('margin')) {
        response = '📊 **High-Margin Menu Breakdown:**\n'
            '1. **ServeSync Smash Burger** (Price: \$18.00 | Cost: \$4.35 | **Margin: 75.8%**)\n'
            '2. **Smoked Hibiscus Spritz** (Price: \$9.50 | Cost: \$1.20 | **Margin: 87.4%**)\n'
            '3. **Warm Molten Lava Cake** (Price: \$11.00 | Cost: \$2.10 | **Margin: 80.9%**)\n\n'
            '💡 *Recommendation: Have servers feature the Hibiscus Spritz and Lava Cake pairing to maximize average table ticket size.*';
      } else if (lower.contains('waste') || lower.contains('spoilage')) {
        response = '📉 **Waste & Spoilage Analysis:**\n'
            '• Recent waste record: 4.0 lbs of Vine-Ripened Tomatoes (\$7.20 loss).\n'
            '• Root Cause: Soft spots during morning prep from delivery batch 3 days ago.\n\n'
            '💡 *Action Plan: Shift tomato stock rotation to strict FIFO. Adjust Tuesday delivery parcel from 30 lbs to 20 lbs to reduce overripe spoilage by ~35%.*';
      } else if (lower.contains('restock') || lower.contains('order') || lower.contains('supplier')) {
        response = '📦 **Predictive Restock Alert (FR-10):**\n'
            '• **Vine-Ripened Tomatoes:** On-hand 8.5 lbs (Reorder threshold: 12.0 lbs) — **LOW STOCK**\n'
            '• **Ground Angus Beef:** 38.5 lbs on-hand. Projected weekend burn: 55 lbs.\n\n'
            '💡 *Recommendation: A purchase order for 25 lbs tomatoes to Metro Farm Produce is currently pending delivery in 4 hours. Recommend submitting PO for 20 lbs Angus Beef to Buckhead Prime Meats today.*';
      } else if (lower.contains('labor') || lower.contains('payroll') || lower.contains('shift')) {
        response = '⏱️ **Labor & Floor Efficiency:**\n'
            '• Active Staff Clocked In: 2 employees (Kristian Napier - Manager, Salem Marye - Admin).\n'
            '• Labor Cost Today: \$284.50 (Est. 18.2% of gross food sales).\n'
            '• Target labor ratio is under 25%, meaning your floor is currently running with high labor productivity!';
      } else {
        response = '⚡ **ServeSync AI Operations Summary:**\n'
            '• KDS Active Queue: Average ticket time is 8.5 minutes (Target < 12m).\n'
            '• Dining Tables: 8 tables active, 2 orders pending in kitchen.\n'
            '• Inventory: 1 low-stock alert (Vine-Ripened Tomatoes) covered by pending supplier PO.\n'
            'Feel free to ask about menu profitability, inventory projections, or labor optimization!';
      }

      if (mounted) {
        setState(() {
          _chatHistory.add({'role': 'assistant', 'content': response});
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.border),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Handle Bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Sheet Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primaryLight.withOpacity(0.4)),
                        ),
                        child: Icon(Icons.auto_awesome, color: AppTheme.primaryLight, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'SERVESYNC AI COPILOT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.statusGreen.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'LIVE CLOUD',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.statusGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'Restaurant Intelligence & Forecasting',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab Navigation
            TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primary,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              tabs: const [
                Tab(icon: Icon(Icons.chat_bubble_outline, size: 16), text: 'AI Copilot'),
                Tab(icon: Icon(Icons.trending_up, size: 16), text: 'Demand (FR-10)'),
                Tab(icon: Icon(Icons.star_outline, size: 16), text: 'Reviews (FR-08)'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCopilotTab(),
                  _buildDemandForecastingTab(appState),
                  _buildReviewSynthesisTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopilotTab() {
    return Column(
      children: [
        // Quick Prompts Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _buildPromptChip('💰 High-Margin Dishes', 'Which dishes have the highest profit margin?'),
              _buildPromptChip('📦 Restock Forecast', 'What ingredients should we reorder right now?'),
              _buildPromptChip('📉 Cut Food Waste', 'How can we cut food waste this weekend?'),
              _buildPromptChip('⏱️ Labor & Speed', 'Summarize today\'s labor and kitchen speed'),
            ],
          ),
        ),

        // Chat Message Log
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _chatHistory.length,
            itemBuilder: (context, index) {
              final msg = _chatHistory[index];
              final isAssistant = msg['role'] == 'assistant';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: isAssistant
                          ? AppTheme.primary.withOpacity(0.15)
                          : AppTheme.surfaceElevated,
                      child: Icon(
                        isAssistant ? Icons.auto_awesome : Icons.person,
                        size: 14,
                        color: isAssistant ? AppTheme.primaryLight : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isAssistant ? AppTheme.surface : AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isAssistant
                                ? AppTheme.primaryLight.withOpacity(0.2)
                                : AppTheme.border,
                          ),
                        ),
                        child: Text(
                          msg['content'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Prompt Input Field
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  decoration: InputDecoration(
                    hintText: 'Ask ServeSync AI anything...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: AppTheme.border),
                    ),
                  ),
                  onSubmitted: _sendQuery,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                onPressed: () => _sendQuery(_promptController.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptChip(String label, String query) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        backgroundColor: AppTheme.surfaceElevated,
        side: BorderSide(color: AppTheme.border),
        label: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
        ),
        onPressed: () => _sendQuery(query),
      ),
    );
  }

  Widget _buildDemandForecastingTab(AppState appState) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // AI Forecast Summary Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.12),
                AppTheme.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_rounded, color: AppTheme.primaryLight, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'FR-10: Predictive Demand Intelligence',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'AI projection estimates 128 covers tonight (+14% above seasonal average). Predicted peak rush: 7:15 PM – 8:45 PM.',
                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'STOCKOUT RISK PREDICTOR (86 PREVENTER)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),

        // Forecast Card 1
        _buildForecastCard(
          ingredient: 'Vine-Ripened Tomatoes',
          currentStock: '8.5 lbs on hand',
          projectedBurn: '18.0 lbs tonight',
          riskLevel: 'CRITICAL',
          riskColor: AppTheme.statusRed,
          actionText: 'Incoming PO-2026-081 delivers 25.0 lbs at 2:00 PM (Covers demand).',
        ),
        const SizedBox(height: 10),

        // Forecast Card 2
        _buildForecastCard(
          ingredient: 'Ground Angus Beef',
          currentStock: '38.5 lbs on hand',
          projectedBurn: '42.0 lbs tonight',
          riskLevel: 'ELEVATED RISK',
          riskColor: AppTheme.statusYellow,
          actionText: 'Recommend reordering 20 lbs from Buckhead Prime Meats by 3 PM.',
        ),
        const SizedBox(height: 10),

        // Forecast Card 3
        _buildForecastCard(
          ingredient: 'Atlantic Salmon Fillets',
          currentStock: '18.0 lbs on hand',
          projectedBurn: '12.0 lbs tonight',
          riskLevel: 'HEALTHY BUFFER',
          riskColor: AppTheme.statusGreen,
          actionText: 'Sufficient buffer through Saturday dinner service.',
        ),
      ],
    );
  }

  Widget _buildForecastCard({
    required String ingredient,
    required String currentStock,
    required String projectedBurn,
    required String riskLevel,
    required Color riskColor,
    required String actionText,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(ingredient, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: riskColor, width: 0.8),
                ),
                child: Text(
                  riskLevel,
                  style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(currentStock, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(width: 10),
              Text('•', style: TextStyle(color: AppTheme.textMuted)),
              const SizedBox(width: 10),
              Text(projectedBurn, style: TextStyle(fontSize: 12, color: AppTheme.primaryLight, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: AppTheme.primaryLight),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    actionText,
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewSynthesisTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall Sentiment Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GUEST SATISFACTION (FR-08)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('4.8', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      Row(
                        children: List.generate(
                          5,
                          (i) => const Icon(Icons.star, size: 16, color: Color(0xFFFBBF24)),
                        ),
                      ),
                    ],
                  ),
                  Text('94% Positive Sentiment (48 Reviews Analyzed)', style: TextStyle(fontSize: 12, color: AppTheme.statusGreen)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.statusGreen.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.sentiment_very_satisfied, size: 32, color: AppTheme.statusGreen),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'AI SENTIMENT SYNTHESIS SUMMARY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),

        _buildSentimentBullet(
          icon: Icons.thumb_up_alt_rounded,
          color: AppTheme.statusGreen,
          title: 'Top Praised Dish: ServeSync Smash Burger',
          body: 'Mentioned favorably in 34 reviews. Guests frequently highlight the artisan brioche bun and seasoning crust.',
        ),
        const SizedBox(height: 10),

        _buildSentimentBullet(
          icon: Icons.local_bar_rounded,
          color: AppTheme.primary,
          title: 'Beverage Winner: Smoked Hibiscus Spritz',
          body: '18 reviews praised beverage aroma and table presentation. High cocktail attachment rate observed.',
        ),
        const SizedBox(height: 10),

        _buildSentimentBullet(
          icon: Icons.warning_amber_rounded,
          color: AppTheme.statusYellow,
          title: 'Kitchen Timing Alert: Calamari Prep Delay',
          body: '2 diners noted 20+ min wait during peak Friday rush. Recommend prep advance on calamari dredge station.',
        ),
      ],
    );
  }

  Widget _buildSentimentBullet({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
