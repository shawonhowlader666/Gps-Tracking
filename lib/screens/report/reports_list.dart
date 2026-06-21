import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/screens/report/multi_period_report_screen.dart';
import 'package:gpspro/theme/custom_color.dart';

class ReportListPage extends StatefulWidget {
  const ReportListPage({super.key});

  @override
  State<StatefulWidget> createState() => _ReportListPageState();
}

class _ReportListPageState extends State<ReportListPage> {
  static ReportArguments? args;

  // Simple color palette
  static const Color primaryColor = CustomColor.primary;
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color cardBg = Colors.white;
  static const Color pageBg = Color(0xFFF9FAFB);

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as ReportArguments;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date Range Header
          _buildDateHeader(),

          const SizedBox(height: 24),

          // Quick Reports Section
          Text(
            'Quick Reports',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textSecondary,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 12),

          // NEW: Multi-Period Report

          _buildReportItem(
            icon: Icons.auto_graph_outlined,
            title: 'Multi-Period Report',
            subtitle: 'Today, Yesterday, Week & Month',
            color: const Color(0xFFEC4899),
            onTap: () => _navigateToMultiPeriodReport(),
            isFeatured: true,
          ),
          _buildReportItem(
            icon: Icons.auto_graph_outlined,
            title: 'Multi-Period Report',
            subtitle: 'Today, Yesterday, Week & Month',
            color: const Color(0xFFEC4899),
            onTap: () => _navigateToMultiPeriodReport(),
            isFeatured: true,
          ),

          const SizedBox(height: 24),

          // Detailed Reports Section
          Text(
            'Detailed Reports',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textSecondary,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 12),

          // Report Options
          _buildReportItem(
            icon: Icons.summarize_outlined,
            title: 'generalInformation'.tr,
            subtitle: 'Complete route summary',
            color: CustomColor.primary,
            onTap: () => _navigateToReport(1, "/reportRoute"),
          ),

          _buildReportItem(
            icon: Icons.pin_drop_outlined,
            title: 'drivesAndStops'.tr,
            subtitle: 'Drives and stop locations',
            color: const Color(0xFF059669),
            onTap: () => _navigateToReport(3, "/reportStop"),
          ),

          _buildReportItem(
            icon: Icons.notifications_outlined,
            title: 'reportEvents'.tr,
            subtitle: 'Events and alerts',
            color: const Color(0xFFD97706),
            onTap: () => _navigateToReport(8, "/reportEvent"),
          ),

          _buildReportItem(
            icon: Icons.crop_free_outlined,
            title: 'geofenceInOut'.tr,
            subtitle: 'Geofence entry/exit logs',
            color: const Color(0xFF7C3AED),
            onTap: () => _navigateToReport(7, "/reportStop"),
          ),

          _buildReportItem(
            icon: Icons.schedule_outlined,
            title: 'workHoursDaily'.tr,
            subtitle: 'Daily work hours',
            color: const Color(0xFFDC2626),
            onTap: () => _navigateToReport(48, "/reportSummary"),
            isLast: true,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        args?.name ?? 'Reports',
        style: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.grey[200],
        ),
      ),
    );
  }

  Widget _buildDateHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.calendar_today_outlined,
              color: primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report Period',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${args?.fromDate ?? 'N/A'} → ${args?.toDate ?? 'N/A'}',
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isLast = false,
    bool isFeatured = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFeatured ? color.withValues(alpha: 0.3) : Colors.grey[200]!,
          width: isFeatured ? 1.5 : 1,
        ),
        gradient: isFeatured
            ? LinearGradient(
          colors: [
            color.withValues(alpha: 0.05),
            cardBg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 14),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          if (isFeatured) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'NEW',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow
                Icon(
                  Icons.chevron_right,
                  color: isFeatured ? color.withValues(alpha: 0.5) : Colors.grey[400],
                  size: 22,
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
        args!.toTime,
        args!.name,
        reportType,
        args!.deviceItem,
      ),
    );
  }

  void _navigateToMultiPeriodReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiPeriodReportScreen(
          deviceId: args!.id,
          deviceName: args!.name,
        ),
      ),
    );
  }
}