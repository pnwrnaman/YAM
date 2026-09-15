import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// If you're testing on an Android emulator, "localhost" refers to the
// emulator itself, not your host machine. Use 10.0.2.2 instead in that case.
const String _apiBaseUrl = 'http://localhost:8000';

void main() {
  runApp(const YamApp());
}

// ---------------------------------------------------------------------------
// App shell & theme
// ---------------------------------------------------------------------------

class YamApp extends StatelessWidget {
  const YamApp({super.key});

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0E1116);
    const surfaceColor = Color(0xFF171B22);
    const accentColor = Color(0xFFFF9F45); // alpine sunrise amber
    const secondaryAccent = Color(0xFF4FD1C5); // glacier teal

    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
      primary: accentColor,
      secondary: secondaryAccent,
      surface: surfaceColor,
    );

    return MaterialApp(
      title: 'YAM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: colorScheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: backgroundColor,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: surfaceColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: backgroundColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: accentColor, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white.withOpacity(0.92),
          displayColor: Colors.white,
        ),
      ),
      home: const TripDashboard(),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class TripRequest {
  final String origin;
  final String destination;
  final String startDate;
  final int durationDays;
  final double budget;
  final String trekDifficulty;

  TripRequest({
    required this.origin,
    required this.destination,
    required this.startDate,
    required this.durationDays,
    required this.budget,
    required this.trekDifficulty,
  });

  Map<String, dynamic> toJson() => {
    'origin': origin,
    'destination': destination,
    'start_date': startDate,
    'duration_days': durationDays,
    'budget': budget,
    'trek_difficulty': trekDifficulty,
  };
}

class TimelineStep {
  final int dayNumber;
  final String time;
  final String title;
  final String description;
  final String? altitudeGain;
  final String? transportMode;
  final double? cost;

  TimelineStep({
    required this.dayNumber,
    required this.time,
    required this.title,
    required this.description,
    this.altitudeGain,
    this.transportMode,
    this.cost,
  });

  factory TimelineStep.fromJson(Map<String, dynamic> json) {
    return TimelineStep(
      dayNumber: (json['day_number'] as num?)?.toInt() ?? 0,
      time: (json['time'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      altitudeGain: _formatAltitude(json['altitude_gain']),
      transportMode: json['transport_mode']?.toString(),
      cost: _toDouble(json['cost']),
    );
  }

  static String? _formatAltitude(dynamic value) {
    if (value == null) return null;
    if (value is num) return '${value.toStringAsFixed(0)}m';
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class TripItinerary {
  final double totalEstimatedCost;
  final List<TimelineStep> timeline;

  TripItinerary({required this.totalEstimatedCost, required this.timeline});

  factory TripItinerary.fromJson(Map<String, dynamic> json) {
    final rawTimeline = (json['timeline'] as List<dynamic>?) ?? const [];
    return TripItinerary(
      totalEstimatedCost:
          (json['total_estimated_cost'] as num?)?.toDouble() ?? 0.0,
      timeline:
          rawTimeline
              .map((e) => TimelineStep.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Trip dashboard screen
// ---------------------------------------------------------------------------

class TripDashboard extends StatefulWidget {
  const TripDashboard({super.key});

  @override
  State<TripDashboard> createState() => _TripDashboardState();
}

class _TripDashboardState extends State<TripDashboard> {
  final _formKey = GlobalKey<FormState>();

  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _durationController = TextEditingController();
  final _budgetController = TextEditingController();

  DateTime? _selectedDate;
  String _trekDifficulty = 'moderate';
  bool _isLoading = false;

  static const List<String> _difficulties = [
    'easy',
    'moderate',
    'hard',
    'technical',
  ];

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _durationController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      builder:
          (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _planTrip() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start date.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final request = TripRequest(
      origin: _originController.text.trim(),
      destination: _destinationController.text.trim(),
      startDate: _formatDate(_selectedDate!),
      durationDays: int.parse(_durationController.text.trim()),
      budget: double.parse(_budgetController.text.trim()),
      trekDifficulty: _trekDifficulty,
    );

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/generate_itinerary'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final itinerary = TripItinerary.fromJson(decoded);
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ItineraryScreen(itinerary: itinerary),
          ),
        );
      } else {
        throw Exception(
          'Server responded with ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to plan trip: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: _PlanningLoadingView());
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.terrain, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('YAM', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan Your Ascent',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tell us where you\'re headed and we\'ll build the route.',
                  style: TextStyle(color: Colors.white.withOpacity(0.6)),
                ),
                const SizedBox(height: 28),
                _buildTextField(
                  controller: _originController,
                  label: 'Origin',
                  icon: Icons.trip_origin,
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _destinationController,
                  label: 'Destination',
                  icon: Icons.flag_outlined,
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                _buildDateField(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _durationController,
                        label: 'Duration (days)',
                        icon: Icons.event_repeat,
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) return 'Enter valid days';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _budgetController,
                        label: 'Budget (USD)',
                        icon: Icons.attach_money,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) return 'Enter valid budget';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDifficultyDropdown(),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _planTrip,
                    icon: const Icon(Icons.hiking),
                    label: const Text('Plan My Trip'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildDateField() {
    final display =
        _selectedDate == null
            ? 'Select start date'
            : _formatDate(_selectedDate!);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pickDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Start Date',
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(
          display,
          style: TextStyle(
            color:
                _selectedDate == null
                    ? Colors.white.withOpacity(0.5)
                    : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyDropdown() {
    return DropdownButtonFormField<String>(
      value: _trekDifficulty,
      decoration: const InputDecoration(
        labelText: 'Trek Difficulty',
        prefixIcon: Icon(Icons.landscape_outlined, size: 20),
      ),
      dropdownColor: const Color(0xFF171B22),
      style: const TextStyle(color: Colors.white, fontSize: 16),
      items:
          _difficulties
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text(d[0].toUpperCase() + d.substring(1)),
                ),
              )
              .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _trekDifficulty = value);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Animated loading view
// ---------------------------------------------------------------------------

class _PlanningLoadingView extends StatefulWidget {
  const _PlanningLoadingView();

  @override
  State<_PlanningLoadingView> createState() => _PlanningLoadingViewState();
}

class _PlanningLoadingViewState extends State<_PlanningLoadingView>
    with SingleTickerProviderStateMixin {
  static const List<String> _messages = [
    'Mapping transit...',
    'Calculating elevation profiles...',
    'Checking mountain weather...',
  ];

  late final AnimationController _pulseController;
  Timer? _messageTimer;
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _messageTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.88, end: 1.12).animate(
              CurvedAnimation(
                parent: _pulseController,
                curve: Curves.easeInOut,
              ),
            ),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.12),
                border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
              ),
              child: Icon(Icons.terrain, size: 44, color: accent),
            ),
          ),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder:
                (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
            child: Text(
              _messages[_messageIndex],
              key: ValueKey<int>(_messageIndex),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This can take up to a minute.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Itinerary result screen
// ---------------------------------------------------------------------------

class ItineraryScreen extends StatelessWidget {
  final TripItinerary itinerary;

  const ItineraryScreen({super.key, required this.itinerary});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Itinerary')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _TotalCostBanner(totalCost: itinerary.totalEstimatedCost),
            const SizedBox(height: 28),
            Text(
              'Day-by-Day Timeline',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (itinerary.timeline.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No timeline steps were returned.',
                  style: TextStyle(color: Colors.white.withOpacity(0.6)),
                ),
              )
            else
              for (int i = 0; i < itinerary.timeline.length; i++)
                _TimelineTile(
                  step: itinerary.timeline[i],
                  isLast: i == itinerary.timeline.length - 1,
                ),
          ],
        ),
      ),
    );
  }
}

class _TotalCostBanner extends StatelessWidget {
  final double totalCost;

  const _TotalCostBanner({required this.totalCost});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9F45), Color(0xFFFF6F3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -8,
            top: -8,
            child: Icon(
              Icons.account_balance_wallet,
              size: 72,
              color: Colors.black.withOpacity(0.12),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TOTAL ESTIMATED COST',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\$${totalCost.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 34,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final TimelineStep step;
  final bool isLast;

  const _TimelineTile({required this.step, required this.isLast});

  IconData _transportIcon(String? mode) {
    final m = (mode ?? '').toLowerCase();
    if (m.contains('flight') || m.contains('plane')) return Icons.flight;
    if (m.contains('jeep') || m.contains('car') || m.contains('vehicle')) {
      return Icons.directions_car;
    }
    if (m.contains('bus')) return Icons.directions_bus;
    if (m.contains('train')) return Icons.train;
    if (m.contains('boat') || m.contains('ferry')) return Icons.directions_boat;
    if (m.contains('foot') || m.contains('hik') || m.contains('walk')) {
      return Icons.directions_walk;
    }
    return Icons.commute;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail: day marker + connecting line
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.15),
                  border: Border.all(color: accent, width: 1.5),
                ),
                child: Text(
                  '${step.dayNumber}',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Card content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'DAY ${step.dayNumber} • ${step.time}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                          ),
                          if (step.cost != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '\$${step.cost!.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        step.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.description,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      if (step.altitudeGain != null ||
                          step.transportMode != null) ...[
                        const SizedBox(height: 14),
                        Divider(
                          color: Colors.white.withOpacity(0.08),
                          height: 1,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            if (step.altitudeGain != null)
                              _MetaChip(
                                icon: Icons.terrain,
                                label: step.altitudeGain!,
                              ),
                            if (step.transportMode != null)
                              _MetaChip(
                                icon: _transportIcon(step.transportMode),
                                label: step.transportMode!,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white.withOpacity(0.6)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13),
        ),
      ],
    );
  }
}
