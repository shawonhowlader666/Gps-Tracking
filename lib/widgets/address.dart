import 'package:flutter/material.dart';
import 'package:smart_lock/services/api_service.dart';
import 'package:smart_lock/theme/custom_color.dart';
import 'package:marquee_widget/marquee_widget.dart';

Widget addressLoad(String lat, String lng, {TextStyle? style}) {
  return AddressText(lat: lat, lng: lng, style: style);
}

Widget addressLoadMarque(String lat, String lng, {TextStyle? style}) {
  return AddressMarqueeText(lat: lat, lng: lng, style: style);
}

class AddressText extends StatefulWidget {
  final String lat;
  final String lng;
  final TextStyle? style;

  const AddressText({
    super.key,
    required this.lat,
    required this.lng,
    this.style,
  });

  @override
  State<AddressText> createState() => _AddressTextState();
}

class _AddressTextState extends State<AddressText> {
  String? _address;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  @override
  void didUpdateWidget(covariant AddressText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      _loadAddress();
    }
  }

  void _loadAddress() {
    final cached = APIService.getCachedAddress(widget.lat, widget.lng);
    if (cached != null) {
      _address = cached.replaceAll('"', '');
      _isLoading = false;
      return;
    }

    // Keep the old address to prevent flickering to "..."
    _isLoading = true;
    APIService.getGeocoderAddress(widget.lat, widget.lng).then((res) {
      if (mounted) {
        setState(() {
          _address = res.replaceAll('"', '');
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayStyle = widget.style ?? const TextStyle(
      color: Colors.black,
      fontFamily: "Popins",
      fontSize: 12,
    );

    if (_isLoading && _address == null) {
      return Text(
        "",
        style: displayStyle,
      );
    }

    return Text(
      _address ?? "Address not available",
      style: displayStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class AddressMarqueeText extends StatefulWidget {
  final String lat;
  final String lng;
  final TextStyle? style;

  const AddressMarqueeText({
    super.key,
    required this.lat,
    required this.lng,
    this.style,
  });

  @override
  State<AddressMarqueeText> createState() => _AddressMarqueeTextState();
}

class _AddressMarqueeTextState extends State<AddressMarqueeText> {
  String? _address;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  @override
  void didUpdateWidget(covariant AddressMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      _loadAddress();
    }
  }

  void _loadAddress() {
    final cached = APIService.getCachedAddress(widget.lat, widget.lng);
    if (cached != null) {
      _address = cached.replaceAll('"', '');
      _isLoading = false;
      return;
    }

    // Keep the old address to prevent flickering to "..."
    _isLoading = true;
    APIService.getGeocoderAddress(widget.lat, widget.lng).then((res) {
      if (mounted) {
        setState(() {
          _address = res.replaceAll('"', '');
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayStyle = widget.style ?? TextStyle(
      color: CustomColor.cssBlack,
      fontSize: 13,
    );

    if (_isLoading && _address == null) {
      return Text(
        "",
        style: displayStyle,
      );
    }

    final addr = _address ?? "Address not available";

    return Marquee(
      direction: Axis.horizontal,
      textDirection: TextDirection.ltr,
      animationDuration: const Duration(seconds: 4),
      backDuration: const Duration(seconds: 1000),
      pauseDuration: const Duration(milliseconds: 1000),
      directionMarguee: DirectionMarguee.oneDirection,
      child: Text(
        addr,
        style: displayStyle,
      ),
    );
  }
}
