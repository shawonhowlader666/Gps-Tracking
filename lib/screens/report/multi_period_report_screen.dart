import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/screens/report/get_today_report.dart';
import 'package:gpspro/screens/report/pdf_generator_service.dart';
import 'package:gpspro/theme/custom_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class MultiPeriodReportScreen extends StatefulWidget {
  final int deviceId;
  final String deviceName;

  const MultiPeriodReportScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<MultiPeriodReportScreen> createState() => _MultiPeriodReportScreenState();
}

class _MultiPeriodReportScreenState extends State<MultiPeriodReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, TodayReportData> reportData = {
    'today': TodayReportData(),
    'yesterday': TodayReportData(),
    'week': TodayReportData(),
    'month': TodayReportData(),
  };

  Map<String, bool> loading = {
    'today': false,
    'yesterday': false,
    'week': false,
    'month': false,
  };

  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadReportForCurrentTab();
      }
    });
    // Load today's report initially
    _loadReportForCurrentTab();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadReportForCurrentTab() {
    switch (_tabController.index) {
      case 0:
        _loadTodayReport();
        break;
      case 1:
        _loadYesterdayReport();
        break;
      case 2:
        _loadWeekReport();
        break;
      case 3:
        _loadMonthReport();
        break;
    }
  }

  Future<void> _loadTodayReport() async {
    if (reportData['today']!.isNotEmpty) return;

    setState(() => loading['today'] = true);

    final data = await ReportService.getReportForPeriod(
      deviceId: widget.deviceId,
      period: ReportPeriod.today,
    );

    setState(() {
      reportData['today'] = data;
      loading['today'] = false;
    });
  }

  Future<void> _loadYesterdayReport() async {
    if (reportData['yesterday']!.isNotEmpty) return;

    setState(() => loading['yesterday'] = true);

    final data = await ReportService.getReportForPeriod(
      deviceId: widget.deviceId,
      period: ReportPeriod.yesterday,
    );

    setState(() {
      reportData['yesterday'] = data;
      loading['yesterday'] = false;
    });
  }

  Future<void> _loadWeekReport() async {
    if (reportData['week']!.isNotEmpty) return;

    setState(() => loading['week'] = true);

    final data = await ReportService.getReportForPeriod(
      deviceId: widget.deviceId,
      period: ReportPeriod.thisWeek,
    );

    setState(() {
      reportData['week'] = data;
      loading['week'] = false;
    });
  }

  Future<void> _loadMonthReport() async {
    if (reportData['month']!.isNotEmpty) return;

    setState(() => loading['month'] = true);

    final data = await ReportService.getReportForPeriod(
      deviceId: widget.deviceId,
      period: ReportPeriod.thisMonth,
    );

    setState(() {
      reportData['month'] = data;
      loading['month'] = false;
    });
  }

  String _getCurrentPeriodKey() {
    switch (_tabController.index) {
      case 0:
        return 'today';
      case 1:
        return 'yesterday';
      case 2:
        return 'week';
      case 3:
        return 'month';
      default:
        return 'today';
    }
  }

  String _getCurrentPeriodName() {
    switch (_tabController.index) {
      case 0:
        return 'Today';
      case 1:
        return 'Yesterday';
      case 2:
        return 'This Week';
      case 3:
        return 'This Month';
      default:
        return 'Today';
    }
  }

  Future<void> _downloadCurrentReportAsPDF() async {
    final periodKey = _getCurrentPeriodKey();
    final data = reportData[periodKey]!;

    if (data.isEmpty) {
      Fluttertoast.showToast(
        msg: "No data available to download",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _isDownloading = true);

    try {
      // Request storage permission
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception("Storage permission denied");
        }
      }

      // Generate PDF
      final pdfBytes = await PDFGeneratorService.generateReportPDF(
        data: data,
        deviceName: widget.deviceName,
        periodName: _getCurrentPeriodName(),
      );

      // Save to Downloads folder
      final fileName = 'Report_${widget.deviceName}_${_getCurrentPeriodName()}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = await _savePDFToDownloads(pdfBytes, fileName);

      setState(() => _isDownloading = false);

      // Show success message with options
      _showDownloadSuccessDialog(file);
    } catch (e) {
      setState(() => _isDownloading = false);

      Fluttertoast.showToast(
        msg: "Download failed: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }


  Future<File> _savePDFToDownloads(Uint8List pdfBytes, String fileName) async {
    Directory? directory;

    if (Platform.isAndroid) {
      // Try to get Downloads directory
      directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }
    } else if (Platform.isIOS) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = await getDownloadsDirectory();
    }

    final filePath = '${directory!.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(pdfBytes);

    return file;
  }

  void _showDownloadSuccessDialog(File file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Download Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PDF saved successfully!'),
            SizedBox(height: 8),
            Text(
              file.path,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Share.shareXFiles([XFile(file.path)], text: 'Report PDF');
            },
            icon: Icon(Icons.share, size: 18),
            label: Text('Share'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CustomColor.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(color: CustomColor.cssBlack),
        title: Text(
          widget.deviceName,
          style: FlutterFlowTheme.of(context).headlineMedium,
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          // Download PDF Button
          IconButton(
            icon: _isDownloading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  CustomColor.primaryColor,
                ),
              ),
            )
                : Icon(Icons.download_rounded),
            onPressed: _isDownloading ? null : _downloadCurrentReportAsPDF,
            tooltip: 'Download PDF',
          ),
          SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: CustomColor.primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: CustomColor.primaryColor,
          tabs: [
            Tab(text: 'Today'),
            Tab(text: 'Yesterday'),
            Tab(text: 'This Week'),
            Tab(text: 'This Month'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReportView('today'),
          _buildReportView('yesterday'),
          _buildReportView('week'),
          _buildReportView('month'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isDownloading ? null : _downloadCurrentReportAsPDF,
        backgroundColor: CustomColor.primaryColor,
        icon: _isDownloading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : Icon(Icons.download_rounded),
        label: Text(_isDownloading ? 'Downloading...' : 'Download PDF'),
      ),
    );
  }

  Widget _buildReportView(String period) {
    if (loading[period]!) {
      return Center(child: CircularProgressIndicator());
    }

    final data = reportData[period]!;

    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No data available',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          reportData[period] = TodayReportData();
        });
        _loadReportForCurrentTab();
      },
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _buildReportCard(data),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(TodayReportData data) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader('Route Information'),
            SizedBox(height: 12),
            if (data.routeStart != null) _buildInfoRow('Route Start', data.routeStart!),
            if (data.routeEnd != null) _buildInfoRow('Route End', data.routeEnd!),
            if (data.routeLength != null) _buildInfoRow('Route Length', data.routeLength!, Icons.route),

            SizedBox(height: 20),
            _buildHeader('Duration'),
            SizedBox(height: 12),
            if (data.moveDuration != null) _buildInfoRow('Move Duration', data.moveDuration!, Icons.directions_car),
            if (data.stopDuration != null) _buildInfoRow('Stop Duration', data.stopDuration!, Icons.stop_circle),

            SizedBox(height: 20),
            _buildHeader('Speed'),
            SizedBox(height: 12),
            if (data.topSpeed != null) _buildInfoRow('Top Speed', data.topSpeed!, Icons.speed),
            if (data.averageSpeed != null) _buildInfoRow('Average Speed', data.averageSpeed!, Icons.speed),
            if (data.overspeedCount != null) _buildInfoRow('Overspeed Count', data.overspeedCount!, Icons.warning),

            SizedBox(height: 20),
            _buildHeader('Engine'),
            SizedBox(height: 12),
            if (data.engineHours != null) _buildInfoRow('Engine Hours', data.engineHours!, Icons.access_time),
            if (data.engineWork != null) _buildInfoRow('Engine Work', data.engineWork!, Icons.build),
            if (data.engineIdle != null) _buildInfoRow('Engine Idle', data.engineIdle!, Icons.pause_circle),

            if (data.odometer != null || data.fuelConsumption != null) ...[
              SizedBox(height: 20),
              _buildHeader('Other'),
              SizedBox(height: 12),
            ],
            if (data.odometer != null) _buildInfoRow('Odometer', data.odometer!, Icons.dashboard),
            if (data.fuelConsumption != null) _buildInfoRow('Fuel Consumption', data.fuelConsumption!, Icons.local_gas_station),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: CustomColor.primaryColor,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [IconData? icon]) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.grey[600]),
            SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}