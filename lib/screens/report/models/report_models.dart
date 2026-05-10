// lib/screens/report/models/report_models.dart

import 'package:flutter/material.dart';

/// Hourly Report Data
class HourlyReportData {
  final int hour;
  final double distance;
  final Duration duration;
  final double avgSpeed;
  final double maxSpeed;
  final int tripCount;

  HourlyReportData({
    required this.hour,
    required this.distance,
    required this.duration,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.tripCount,
  });

  String get hourLabel {
    final startHour = hour.toString().padLeft(2, '0');
    final endHour = ((hour + 1) % 24).toString().padLeft(2, '0');
    return '$startHour:00 - $endHour:00';
  }

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

/// Trip Data
class TripData {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final String startLocation;
  final String endLocation;
  final double distance;
  final Duration duration;
  final double avgSpeed;
  final double maxSpeed;
  final double fuelConsumed;

  TripData({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.startLocation,
    required this.endLocation,
    required this.distance,
    required this.duration,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.fuelConsumed,
  });

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get formattedStartTime {
    return '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
  }

  String get formattedEndTime {
    return '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Daily Summary Data
class DailySummaryData {
  final DateTime date;
  final double totalDistance;
  final Duration totalMoveDuration;
  final Duration totalStopDuration;
  final double avgSpeed;
  final double maxSpeed;
  final int tripCount;
  final int overspeedCount;
  final Duration engineHours;
  final double fuelConsumed;
  final List<HourlyReportData> hourlyData;
  final List<TripData> trips;

  DailySummaryData({
    required this.date,
    required this.totalDistance,
    required this.totalMoveDuration,
    required this.totalStopDuration,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.tripCount,
    required this.overspeedCount,
    required this.engineHours,
    required this.fuelConsumed,
    required this.hourlyData,
    required this.trips,
  });

  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String get dayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}

/// Monthly Summary Data
class MonthlySummaryData {
  final int year;
  final int month;
  final double totalDistance;
  final Duration totalMoveDuration;
  final int totalTrips;
  final double avgDailyDistance;
  final List<DailyReportItem> dailyReports;

  MonthlySummaryData({
    required this.year,
    required this.month,
    required this.totalDistance,
    required this.totalMoveDuration,
    required this.totalTrips,
    required this.avgDailyDistance,
    required this.dailyReports,
  });

  String get monthName {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[month - 1]} $year';
  }
}

/// Daily Report Item (for monthly view)
class DailyReportItem {
  final DateTime date;
  final double distance;
  final Duration moveDuration;
  final Duration stopDuration;
  final int tripCount;
  final double maxSpeed;
  final double avgSpeed;
  final Duration engineHours;
  final int overspeedCount;
  bool isExpanded;

  DailyReportItem({
    required this.date,
    required this.distance,
    required this.moveDuration,
    required this.stopDuration,
    required this.tripCount,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.engineHours,
    required this.overspeedCount,
    this.isExpanded = false,
  });

  String get formattedDate {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String get dayName {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  String get shortDayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}