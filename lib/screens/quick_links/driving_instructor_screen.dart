import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class DrivingInstructorScreen extends StatefulWidget {
  const DrivingInstructorScreen({super.key});

  @override
  State<DrivingInstructorScreen> createState() => _DrivingInstructorScreenState();
}

class _DrivingInstructorScreenState extends State<DrivingInstructorScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Map<String, String>> _schools = [
    {
      'name': 'Orbit Driving Training School',
      'phone': '01901388950',
      'location': 'Mirpur, Dhaka',
      'status': 'BRTA Approved',
      'rating': '4.8',
    },
    {
      'name': 'BRAC Driving School',
      'phone': '01713063544',
      'location': 'Uttara, Dhaka',
      'status': 'BRTA Approved',
      'rating': '4.9',
    },
    {
      'name': 'BRTA Safety Training Center',
      'phone': '01552321456',
      'location': 'Mirpur-13, Dhaka',
      'status': 'Official Government',
      'rating': '4.7',
    },
    {
      'name': 'Nitol Driving Training School',
      'phone': '01711223344',
      'location': 'Tejgaon Industrial Area, Dhaka',
      'status': 'BRTA Approved',
      'rating': '4.5',
    },
    {
      'name': 'Ranks Driving Academy',
      'phone': '01977112233',
      'location': 'Kakrail, Dhaka',
      'status': 'BRTA Approved',
      'rating': '4.6',
    },
    {
      'name': 'Chittagong Driving School',
      'phone': '01819324567',
      'location': 'Agrabad, Chittagong',
      'status': 'BRTA Approved',
      'rating': '4.4',
    },
  ];

  Future<void> _makeCall(String number) async {
    final Uri url = Uri(scheme: 'tel', path: number);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('Error', 'Could not open phone dialer',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.redAccent,
            colorText: Colors.white);
      }
    } catch (e) {
      debugPrint('Error calling: $e');
    }
  }

  void _copyToClipboard(String text, String schoolName) {
    Clipboard.setData(ClipboardData(text: text));
    Get.snackbar(
      'Copied',
      '$schoolName info copied to clipboard',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xFF1E293B),
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSchools = _schools.where((school) {
      final nameMatches = school['name']!.toLowerCase().contains(_searchQuery.toLowerCase());
      final locMatches = school['location']!.toLowerCase().contains(_searchQuery.toLowerCase());
      return nameMatches || locMatches;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Driving Instructors',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFE53935), // Crimson red theme color
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFE53935),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search school name or location...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Expanded(
            child: filteredSchools.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No driving schools found',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredSchools.length,
                    itemBuilder: (context, index) {
                      final school = filteredSchools[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                          border: Border.all(color: Colors.grey[200]!, width: 0.5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE53935).withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.directions_car,
                                        color: Color(0xFFE53935), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          school['name']!,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1E293B)),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                school['status']!,
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.star,
                                                    color: Colors.amber, size: 12),
                                                const SizedBox(width: 2),
                                                Text(
                                                  school['rating']!,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[700],
                                                      fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.copy, color: Colors.grey[400], size: 18),
                                    onPressed: () => _copyToClipboard(
                                        '${school['name']}\nPhone: ${school['phone']}\nLocation: ${school['location']}',
                                        school['name']!),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.location_on, color: Colors.grey[500], size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      school['location']!,
                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.phone, color: Colors.grey[500], size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    school['phone']!,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _makeCall(school['phone']!),
                                    icon: const Icon(Icons.call, size: 14, color: Colors.white),
                                    label: const Text(
                                      'Call Now',
                                      style: TextStyle(fontSize: 11, color: Colors.white),
                                    ),
                                    style: TextButton.styleFrom(
                                      backgroundColor: const Color(0xFFE53935),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
