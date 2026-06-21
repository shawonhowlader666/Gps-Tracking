import 'package:flutter/material.dart';

class CarKnowledgeScreen extends StatefulWidget {
  const CarKnowledgeScreen({super.key});

  @override
  State<CarKnowledgeScreen> createState() => _CarKnowledgeScreenState();
}

class _CarKnowledgeScreenState extends State<CarKnowledgeScreen> {
  final Map<String, bool> _dailyChecks = {
    'Engine Oil Level': false,
    'Coolant Level': false,
    'Brake Fluid Level': false,
    'Tire Pressure & Condition': false,
    'Headlights & Signals Check': false,
  };

  final Map<String, bool> _weeklyChecks = {
    'Windshield Washer Fluid': false,
    'Battery Terminals Condition': false,
    'Air Filter Cleanliness': false,
    'Engine Belts Inspection': false,
    'Clean Mirrors & Windows': false,
  };

  // Oil Change Calculator State
  final _lastChangeController = TextEditingController(text: '80000');
  final _intervalController = TextEditingController(text: '5000');
  final _currentController = TextEditingController(text: '82400');

  int? _remainingKm;
  double _lifePercentage = 1.0;

  @override
  void initState() {
    super.initState();
    _calculateOilLife();
  }

  void _calculateOilLife() {
    final last = int.tryParse(_lastChangeController.text) ?? 0;
    final interval = int.tryParse(_intervalController.text) ?? 5000;
    final current = int.tryParse(_currentController.text) ?? 0;

    final nextChange = last + interval;
    final remaining = nextChange - current;

    setState(() {
      _remainingKm = remaining;
      final driven = current - last;
      if (interval > 0) {
        _lifePercentage = (1.0 - (driven / interval)).clamp(0.0, 1.0);
      } else {
        _lifePercentage = 0.0;
      }
    });
  }

  double _getChecklistProgress() {
    final total = _dailyChecks.length + _weeklyChecks.length;
    final checked = _dailyChecks.values.where((v) => v).length +
        _weeklyChecks.values.where((v) => v).length;
    return total > 0 ? checked / total : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _getChecklistProgress();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Car Knowledge & Care',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFE53935),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Progress Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE53935), Color(0xFFB22222)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE53935).withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Checklist Progress',
                    style: TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Completed: ${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 2: Oil Change Calculator
            const Text(
              'Engine Oil Life Tracker',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey[200]!, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Remaining Distance',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _remainingKm != null
                                  ? (_remainingKm! <= 0 ? 'Change Oil Now!' : '${_remainingKm} KM')
                                  : '-',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _remainingKm != null && _remainingKm! <= 500
                                      ? Colors.red
                                      : const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        // Circular percentage indicator
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                value: _lifePercentage,
                                strokeWidth: 5,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    _lifePercentage <= 0.1 ? Colors.red : Colors.green),
                              ),
                            ),
                            Text(
                              '${(_lifePercentage * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lastChangeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Last Change (KM)',
                              labelStyle: TextStyle(fontSize: 11),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onChanged: (_) => _calculateOilLife(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _intervalController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Interval (KM)',
                              labelStyle: TextStyle(fontSize: 11),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onChanged: (_) => _calculateOilLife(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _currentController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Current KM',
                              labelStyle: TextStyle(fontSize: 11),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onChanged: (_) => _calculateOilLife(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section 3: Interactive Checklist Tabs
            const Text(
              'Maintenance Checklist',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            _buildChecklistGroup('Daily Pre-Drive Checks', _dailyChecks),
            const SizedBox(height: 12),
            _buildChecklistGroup('Weekly Safety Checks', _weeklyChecks),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistGroup(String title, Map<String, bool> items) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[200]!, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE53935)),
              ),
            ),
            ...items.keys.map((key) {
              return CheckboxListTile(
                title: Text(key, style: const TextStyle(fontSize: 13)),
                value: items[key],
                activeColor: const Color(0xFFE53935),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (bool? val) {
                  setState(() {
                    items[key] = val ?? false;
                  });
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
