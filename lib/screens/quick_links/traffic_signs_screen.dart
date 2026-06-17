import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TrafficSignsScreen extends StatefulWidget {
  const TrafficSignsScreen({super.key});

  @override
  State<TrafficSignsScreen> createState() => _TrafficSignsScreenState();
}

class _TrafficSignsScreenState extends State<TrafficSignsScreen> with SingleTickerProviderStateMixin {
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

  final List<Map<String, dynamic>> _mandatorySigns = [
    {
      'title': 'STOP (থামুন)',
      'desc': 'You must bring your vehicle to a complete stop before the stop line.',
      'fine': '৳৫,০০০ (Fine under Sec 92)',
      'isCircle': false,
      'isOctagon': true,
      'icon': Icons.block,
    },
    {
      'title': 'No Entry (প্রবেশ নিষেধ)',
      'desc': 'No vehicles are allowed to enter this road/zone.',
      'fine': '৳৩,০০০ (Fine under Sec 92)',
      'isCircle': true,
      'isOctagon': false,
      'icon': Icons.do_not_disturb_on,
    },
    {
      'title': 'Speed Limit 50 (গতিসীমা ৫০)',
      'desc': 'Maximum legal driving speed on this stretch of road is 50 km/h.',
      'fine': '৳৪,০০০ (Over speeding Sec 86)',
      'isCircle': true,
      'isOctagon': false,
      'number': '50',
    },
    {
      'title': 'No Horn (হর্ন বাজানো নিষেধ)',
      'desc': 'Sounding horns is strictly prohibited, usually near schools or hospitals.',
      'fine': '৳২,০০০ (Fine under Sec 89)',
      'isCircle': true,
      'isOctagon': false,
      'icon': Icons.volume_off,
    },
    {
      'title': 'No Overtaking',
      'desc': 'Overtaking other vehicles is prohibited due to poor line of sight.',
      'fine': '৳৫,০০০ (Dangerous driving Sec 90)',
      'isCircle': true,
      'isOctagon': false,
      'icon': Icons.swap_horizontal_circle,
    },
  ];

  final List<Map<String, dynamic>> _cautionarySigns = [
    {
      'title': 'School Crossing (বিদ্যালয়)',
      'desc': 'Slow down and prepare to stop for children crossing the road.',
      'icon': Icons.child_care,
    },
    {
      'title': 'Speed Breaker (গতি নিরোধক)',
      'desc': 'A bump or speed breaker lies ahead. Reduce speed immediately.',
      'icon': Icons.unfold_more,
    },
    {
      'title': 'Narrow Road Ahead',
      'desc': 'The road narrows ahead. Prepare to merge or yield to oncoming cars.',
      'icon': Icons.align_horizontal_center,
    },
    {
      'title': 'Pedestrian Crossing',
      'desc': 'Zebra crossing ahead. Yield to pedestrians crossing the roadway.',
      'icon': Icons.directions_walk,
    },
  ];

  final List<Map<String, dynamic>> _informationalSigns = [
    {
      'title': 'Parking Zone (পার্কিং)',
      'desc': 'Authorized parking space is available for vehicles.',
      'symbol': 'P',
    },
    {
      'title': 'Hospital (হাসপাতাল)',
      'desc': 'Medical facilities are located ahead. Maintain silence.',
      'icon': Icons.local_hospital,
    },
    {
      'title': 'Filling Station (ফুয়েল স্টেশন)',
      'desc': 'Gasoline, diesel, or octane filling station nearby.',
      'icon': Icons.local_gas_station,
    },
    {
      'title': 'Rest Area (বিশ্রামাগার)',
      'desc': 'Public rest stop area with washroom facilities.',
      'icon': Icons.hotel,
    },
  ];

  void _showSignDetails(Map<String, dynamic> sign) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(sign['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: _buildVisualSign(sign, size: 80),
            ),
            const SizedBox(height: 20),
            const Text(
              'Meaning & Instructions:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 6),
            Text(
              sign['desc']!,
              style: TextStyle(color: Colors.grey[700], fontSize: 12, height: 1.4),
            ),
            if (sign['fine'] != null) ...[
              const SizedBox(height: 14),
              const Text(
                'Penalty / Violations Fine:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  sign['fine']!,
                  style: const TextStyle(
                      color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close', style: TextStyle(color: Color(0xFF8B1A1A))),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualSign(Map<String, dynamic> sign, {double size = 48}) {
    if (sign['symbol'] == 'P') {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.blue[800],
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          'P',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.6),
        ),
      );
    }

    if (sign['number'] != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.red, width: size * 0.1),
        ),
        alignment: Alignment.center,
        child: Text(
          sign['number']!,
          style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.4),
        ),
      );
    }

    if (sign['isOctagon'] == true) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          'STOP',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12),
        ),
      );
    }

    if (sign['isCircle'] == true) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.red, width: size * 0.08),
        ),
        alignment: Alignment.center,
        child: Icon(sign['icon'] as IconData, color: Colors.red, size: size * 0.6),
      );
    }

    // Default to triangle for cautionary, blue square for informational
    final isCautionary = _cautionarySigns.contains(sign);
    if (isCautionary) {
      return CustomPaint(
        size: Size(size, size),
        painter: TrianglePainter(color: Colors.amber[700]!),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.only(bottom: size * 0.1),
          child: Icon(sign['icon'] as IconData, color: Colors.black, size: size * 0.45),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.blue[700],
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(sign['icon'] as IconData, color: Colors.white, size: size * 0.55),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Traffic Signs Guide',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF8B1A1A),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Mandatory'),
            Tab(text: 'Cautionary'),
            Tab(text: 'Informational'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSignsList(_mandatorySigns),
          _buildSignsList(_cautionarySigns),
          _buildSignsList(_informationalSigns),
        ],
      ),
    );
  }

  Widget _buildSignsList(List<Map<String, dynamic>> signs) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: signs.length,
      itemBuilder: (context, index) {
        final sign = signs[index];
        return Card(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey[200]!, width: 0.5),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _buildVisualSign(sign),
            title: Text(
              sign['title']!,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
            ),
            subtitle: Text(
              sign['desc'] ?? 'Traffic regulation checkpoint guide.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            onTap: () => _showSignDetails(sign),
          ),
        );
      },
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);

    // Draw internal outline for a nicer cautionary look
    final borderPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08;

    final borderPath = Path()
      ..moveTo(size.width / 2, size.width * 0.08)
      ..lineTo(size.width - size.width * 0.06, size.height - size.width * 0.04)
      ..lineTo(size.width * 0.06, size.height - size.width * 0.04)
      ..close();

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
