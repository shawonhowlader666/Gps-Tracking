import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/theme/custom_color.dart';

class ReportListPage extends StatefulWidget {
  const ReportListPage({super.key});

  @override
  State<StatefulWidget> createState() => new _ReportListPageState();
}

class _ReportListPageState extends State<ReportListPage> with SingleTickerProviderStateMixin {
  static ReportArguments? args;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as ReportArguments;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reports Dashboard',
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              args?.name ?? 'Select Report',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              _buildHeaderCard(),

              const SizedBox(height: 24),

              Text(
                'Available Reports',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),

              const SizedBox(height: 16),

              // Report Cards Grid
              _buildReportCard(
                icon: Icons.route,
                title: 'generalInformation'.tr,
                description: 'View complete route information',
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () => _navigateToReport(1, "/reportRoute"),
              ),

              const SizedBox(height: 16),

              _buildReportCard(
                icon: Icons.location_on,
                title: 'drivesAndStops'.tr,
                description: 'Track all drives and stops',
                gradient: const LinearGradient(
                  colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () => _navigateToReport(3, "/reportStop"),
              ),

              const SizedBox(height: 16),

              _buildReportCard(
                icon: Icons.notifications_active,
                title: 'reportEvents'.tr,
                description: 'View all events and alerts',
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () => _navigateToReport(8, "/reportEvent"),
              ),

              const SizedBox(height: 16),

              _buildReportCard(
                icon: Icons.fence,
                title: 'geofenceInOut'.tr,
                description: 'Geofence entry and exit logs',
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () => _navigateToReport(7, "/reportStop"),
              ),

              const SizedBox(height: 16),

              _buildReportCard(
                icon: Icons.access_time,
                title: 'workHoursDaily'.tr,
                description: 'Daily work hours summary',
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () => _navigateToReport(48, "/reportSummary"),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.analytics,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Report Period',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${args?.fromDate ?? ''} - ${args?.toDate ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard({
    required IconData icon,
    required String title,
    required String description,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Icon Container with Gradient
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors.first.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),

                const SizedBox(width: 16),

                // Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow Icon
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToReport(int reportType, String route) {
    Navigator.pushNamed(
      context,
      route,
      arguments: ReportArguments(
        args!.id,
        args!.fromDate,
        args!.fromTime,
        args!.toDate,
        args!.name,
        args!.name,
        reportType,
        args!.deviceItem,
      ),
    );
  }
}