import 'package:gpspro/services/model/device_item.dart';
import 'package:gpspro/services/model/geofence_model.dart';

class FenceArguments {
  final Geofence? fenceModel;
  final DeviceItem? device;

  FenceArguments({this.fenceModel, this.device});
}
