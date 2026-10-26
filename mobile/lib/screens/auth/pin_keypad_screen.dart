import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';
import '../shell/main_shell_screen.dart';

class PinKeypadScreen extends StatefulWidget {
  const PinKeypadScreen({super.key});

  @override
  State<PinKeypadScreen> createState() => _PinKeypadScreenState();
}

class _PinKeypadScreenState extends State<PinKeypadScreen> {
  String _pin = '';
  String? _errorMessage;

  void _handleNumberPress(String digit) {
    if (_pin.length < 4) {
      setState(() {
        _pin += digit;
        _errorMessage = null;
      });

      if (_pin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _handleBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _errorMessage = null;
      });
    }
  }

  void _verifyPin() {
    final appState = AppState.instance;
    final success = appState.authenticateWithPin(_pin);

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
      );
    } else {
      setState(() {
        _errorMessage = 'Invalid Access PIN. Try 1234, 2345, or 3456';
        _pin = '';
      });
    }
  }

  void _quickSelectEmployee(String pin) {
    setState(() {
      _pin = pin;
    });
    _verifyPin();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  // App Brand Header
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: AppTheme.primaryGlow,
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.restaurant_rounded,
                      size: 38,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ServeSync',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Restaurant Operating System',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // PIN Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isFilled = index < _pin.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled ? AppTheme.primary : AppTheme.surfaceHighlight,
                          border: Border.all(
                            color: isFilled ? AppTheme.primaryLight : AppTheme.border,
                            width: 2,
                          ),
                          boxShadow: isFilled
                              ? [
                                  const BoxShadow(
                                    color: AppTheme.primaryGlow,
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),

                  // Error Message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppTheme.statusRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else
                    const SizedBox(height: 28),

                  // 3x4 Numeric Keypad
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        _buildKeypadRow(['1', '2', '3']),
                        const SizedBox(height: 14),
                        _buildKeypadRow(['4', '5', '6']),
                        const SizedBox(height: 14),
                        _buildKeypadRow(['7', '8', '9']),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Clear Key
                            _buildKeypadButton(
                              icon: Icons.clear_rounded,
                              onTap: () => setState(() => _pin = ''),
                            ),
                            // Digit 0
                            _buildKeypadButton(
                              label: '0',
                              onTap: () => _handleNumberPress('0'),
                            ),
                            // Backspace Key
                            _buildKeypadButton(
                              icon: Icons.backspace_outlined,
                              onTap: _handleBackspace,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Quick Demo Switchers (Crucial for live CS Demo Day!)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚡ QUICK DEMO PROFILES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: appState.employees.map((emp) {
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: InkWell(
                                  onTap: () => _quickSelectEmployee(emp.pin),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceElevated,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.border),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          emp.name.split(' ').first,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          emp.role == 'Administrator'
                                              ? 'Admin'
                                              : emp.role == 'Manager'
                                                  ? 'Manager'
                                                  : 'Staff',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: emp.isAdmin
                                                ? AppTheme.primary
                                                : emp.isManager
                                                    ? AppTheme.statusYellow
                                                    : AppTheme.statusGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildKeypadRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits
          .map((digit) => _buildKeypadButton(
                label: digit,
                onTap: () => _handleNumberPress(digit),
              ))
          .toList(),
    );
  }

  Widget _buildKeypadButton({
    String? label,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border.withOpacity(0.8), width: 1),
        ),
        child: Center(
          child: label != null
              ? Text(
                  label,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                )
              : Icon(
                  icon,
                  size: 24,
                  color: AppTheme.textSecondary,
                ),
        ),
      ),
    );
  }
}
