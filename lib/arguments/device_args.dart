import 'package:smart_lock/services/model/device_item.dart';

class DeviceArguments {
  final int id;
  final String name;
  final DeviceItem device;
  DeviceArguments(this.id, this.name, this.device);
}
