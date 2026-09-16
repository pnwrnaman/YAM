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
// Theme
// ---------------------------------------------------------------------------

class AppColors {
  static const bg = Color(0xFFF5F6F8);
  static const primaryDark = Color(0xFF163C2C);
  static const primary = Color(0xFF1F6D4C);
  static const primaryLight = Color(0xFFE7F3EC);
  static const amber = Color(0xFFFF9F45);
  static const border = Color(0xFFE4E7EC);
  static const textMuted = Color(0xFF667085);
  static const textDark = Color(0xFF101828);
  static const errorBg = Color(0xFFFEEEEE);
  static const errorBorder = Color(0xFFF5B5B5);
  static const errorText = Color(0xFFB42318);
}

BoxDecoration panelDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: AppColors.border),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.03),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ],
);

class YamApp extends StatelessWidget {
  const YamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YAM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: AppColors.textDark,
          displayColor: AppColors.textDark,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models (unchanged wire format — matches FastAPI backend exactly)
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
// Home shell — responsive: side-by-side on wide screens, stacked on phones
// ---------------------------------------------------------------------------

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  TripItinerary? _itinerary;
  String _origin = '';
  String _destination = '';
  String _difficulty = '';
  int _durationDays = 0;
  bool _isLoading = false;
  String? _error;

  Future<void> _handleGenerate(TripRequest request) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

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
        setState(() {
          _itinerary = itinerary;
          _origin = request.origin;
          _destination = request.destination;
          _difficulty = request.trekDifficulty;
          _durationDays = request.durationDays;
          _isLoading = false;
        });

        final isWide = MediaQuery.of(context).size.width >= 900;
        if (!isWide && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => ItineraryScreen(
                    itinerary: itinerary,
                    origin: _origin,
                    destination: _destination,
                    difficulty: _difficulty,
                    durationDays: _durationDays,
                  ),
            ),
          );
        }
      } else {
        throw Exception(
          'Server responded with ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to plan trip: $e';
      });
    }
  }

  void _reset() => setState(() => _itinerary = null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            final planner = Padding(
              padding: const EdgeInsets.all(24),
              child: TripPlannerPanel(
                isLoading: _isLoading,
                error: _error,
                onSubmit: _handleGenerate,
              ),
            );

            if (!isWide) {
              return SingleChildScrollView(child: planner);
            }

            final results = Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
              child:
                  _itinerary == null
                      ? const EmptyResultsPanel()
                      : ItineraryPanel(
                        itinerary: _itinerary!,
                        origin: _origin,
                        destination: _destination,
                        difficulty: _difficulty,
                        durationDays: _durationDays,
                        onPlanAnother: _reset,
                      ),
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: SingleChildScrollView(child: planner)),
                Expanded(flex: 6, child: SingleChildScrollView(child: results)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class BrandRow extends StatelessWidget {
  const BrandRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.terrain, color: AppColors.amber, size: 20),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YAM',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Your Auto Map',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
    ),
  );
}

class MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const MetaChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.errorText,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class EmptyResultsPanel extends StatelessWidget {
  const EmptyResultsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: panelDecoration(),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.map_outlined,
            size: 40,
            color: AppColors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your itinerary will appear here',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Fill out the trip brief and generate to see the plan.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trip planner panel (left / form screen)
// ---------------------------------------------------------------------------

class TripPlannerPanel extends StatefulWidget {
  final bool isLoading;
  final String? error;
  final ValueChanged<TripRequest> onSubmit;

  const TripPlannerPanel({
    super.key,
    required this.isLoading,
    required this.error,
    required this.onSubmit,
  });

  @override
  State<TripPlannerPanel> createState() => _TripPlannerPanelState();
}

class _TripPlannerPanelState extends State<TripPlannerPanel> {
  final _formKey = GlobalKey<FormState>();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _durationController = TextEditingController(text: '7');
  final _budgetController = TextEditingController();

  DateTime? _selectedDate;
  String _trekDifficulty = 'moderate';

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
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _submit() {
    if (widget.isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start date.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    widget.onSubmit(
      TripRequest(
        origin: _originController.text.trim(),
        destination: _destinationController.text.trim(),
        startDate: _formatDate(_selectedDate!),
        durationDays: int.parse(_durationController.text.trim()),
        budget: double.parse(_budgetController.text.trim()),
        trekDifficulty: _trekDifficulty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(24),
      decoration: panelDecoration(),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandRow(),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'AI-powered route planning',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Build your trip brief',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              "Tell YAM where you want to go. We'll shape a paced, trail-aware "
              "itinerary with travel logistics, altitude, costs, and essential gear.",
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            const FieldLabel('Origin'),
            TextFormField(
              controller: _originController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.trip_origin, size: 20),
                hintText: 'e.g. Delhi',
              ),
              validator:
                  (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const FieldLabel('Destination'),
            TextFormField(
              controller: _destinationController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.flag_outlined, size: 20),
                hintText: 'e.g. Kedarnath, Valley of Flowers',
              ),
              validator:
                  (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Start date'),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            _selectedDate == null
                                ? 'dd/mm/yyyy'
                                : _formatDate(_selectedDate!),
                            style: TextStyle(
                              color:
                                  _selectedDate == null
                                      ? AppColors.textMuted
                                      : AppColors.textDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Duration (days)'),
                      TextFormField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.repeat, size: 18),
                        ),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const FieldLabel('Budget (₹)'),
            TextFormField(
              controller: _budgetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.currency_rupee, size: 18),
                hintText: 'e.g. 15000',
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'Invalid';
                return null;
              },
            ),
            const SizedBox(height: 16),
            const FieldLabel('Trek difficulty'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  _difficulties.map((d) {
                    final selected = d == _trekDifficulty;
                    return ChoiceChip(
                      label: Text(d[0].toUpperCase() + d.substring(1)),
                      selected: selected,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _trekDifficulty = d),
                      selectedColor: AppColors.primaryDark,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.isLoading ? null : _submit,
                icon:
                    widget.isLoading
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  widget.isLoading ? 'Generating...' : 'Generate itinerary',
                ),
              ),
            ),
            if (widget.isLoading) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mapping your adventure',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Analyzing trails, weather, and gear recommendations.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.error != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(message: widget.error!),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Itinerary dashboard panel (right / results screen)
// ---------------------------------------------------------------------------

class ItineraryScreen extends StatelessWidget {
  final TripItinerary itinerary;
  final String origin;
  final String destination;
  final String difficulty;
  final int durationDays;

  const ItineraryScreen({
    super.key,
    required this.itinerary,
    required this.origin,
    required this.destination,
    required this.difficulty,
    required this.durationDays,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Itinerary'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ItineraryPanel(
            itinerary: itinerary,
            origin: origin,
            destination: destination,
            difficulty: difficulty,
            durationDays: durationDays,
            onPlanAnother: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class ItineraryPanel extends StatelessWidget {
  final TripItinerary itinerary;
  final String origin;
  final String destination;
  final String difficulty;
  final int durationDays;
  final VoidCallback onPlanAnother;

  const ItineraryPanel({
    super.key,
    required this.itinerary,
    required this.origin,
    required this.destination,
    required this.difficulty,
    required this.durationDays,
    required this.onPlanAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandRow(),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'Route ready',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            destination.isEmpty ? 'Your itinerary' : destination,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (origin.isNotEmpty)
            Text(
              'A day-by-day plan from $origin to $destination.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
              ),
            ),
          const SizedBox(height: 20),
          _TripEstimateCard(
            totalCost: itinerary.totalEstimatedCost,
            origin: origin,
            destination: destination,
            difficulty: difficulty,
            durationDays: durationDays,
            steps: itinerary.timeline.length,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text(
                'Itinerary timeline',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${itinerary.timeline.length} steps',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (itinerary.timeline.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No timeline steps were returned for this trip.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            for (int i = 0; i < itinerary.timeline.length; i++)
              _TimelineCard(
                step: itinerary.timeline[i],
                index: i + 1,
                isLast: i == itinerary.timeline.length - 1,
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onPlanAnother,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Plan another trip'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripEstimateCard extends StatelessWidget {
  final double totalCost;
  final String origin;
  final String destination;
  final String difficulty;
  final int durationDays;
  final int steps;

  const _TripEstimateCard({
    required this.totalCost,
    required this.origin,
    required this.destination,
    required this.difficulty,
    required this.durationDays,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOTAL PROJECTED COST',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '\₹${totalCost.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _MetaStat(label: 'Duration', value: '$durationDays days'),
              _MetaStat(label: 'Route', value: '$origin \u2192 $destination'),
              _MetaStat(
                label: 'Difficulty',
                value:
                    difficulty.isEmpty
                        ? '-'
                        : difficulty[0].toUpperCase() + difficulty.substring(1),
              ),
              _MetaStat(label: 'Steps', value: '$steps'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaStat extends StatelessWidget {
  final String label;
  final String value;
  const _MetaStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final TimelineStep step;
  final int index;
  final bool isLast;

  const _TimelineCard({
    required this.step,
    required this.index,
    required this.isLast,
  });

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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.2),
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DAY ${step.dayNumber} \u2022 ${step.time}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (step.cost != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '\₹${step.cost!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.description,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (step.altitudeGain != null ||
                        step.transportMode != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          if (step.altitudeGain != null)
                            MetaChip(
                              icon: Icons.terrain,
                              label: step.altitudeGain!,
                            ),
                          if (step.transportMode != null)
                            MetaChip(
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
        ],
      ),
    );
  }
}
