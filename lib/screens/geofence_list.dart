import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/services/model/geofence_model.dart';
import 'package:gpspro/services/model/user.dart';
import 'package:gpspro/services/api_service.dart';
import 'package:gpspro/theme/custom_color.dart';

class GeofenceListPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _GeofenceListPageState();
}

class _GeofenceListPageState extends State<GeofenceListPage> {
  GoogleMapController? mapController;
  Timer? _timer;
  bool addFenceVisible = false;
  bool deleteFenceVisible = false;
  bool addClicked = false;
  User? user;
  int? deleteFenceId;
  bool isLoading = false;
  List<Geofence> fenceList = [];
  List<int> selectedFenceList = [];

  Marker? newFenceMarker;
  bool loading = true;

  @override
  initState() {
    super.initState();
    getFences();
  }

  void deactivateFence(id) {
    setState(() {
      loading = true;
    });
    fenceList.clear();
    selectedFenceList.clear();

    Map<String, String> requestBody = <String, String>{
      'id': id.toString(),
      'active': "false"
    };
    APIService.activateFence(requestBody).then((value) => {
          if (value.statusCode == 200)
            {
              getFences(),
              setState(() {
                loading = false;
              })
            }
          else
            {
              setState(() {
                loading = false;
              })
            }
        });
  }

  void activateFence(id) {
    setState(() {
      loading = true;
    });
    fenceList.clear();
    selectedFenceList.clear();
    Map<String, String> requestBody = <String, String>{
      'id': id.toString(),
      'active': "true"
    };
    APIService.activateFence(requestBody).then((value) => {
          if (value.statusCode == 200)
            {
              getFences(),
              setState(() {
                loading = false;
              })
            }
          else
            {
              setState(() {
                loading = false;
              })
            }
        });
  }

  void getFences() async {
    setState(() {
      loading = true;
    });
    APIService.getGeoFences().then((value) {
      if (value != null) {
        fenceList.addAll(value);
        setState(() {
          loading = false;
        });
        setState(() {});
      } else {
        setState(() {});
        setState(() {
          loading = false;
        });
        Fluttertoast.showToast(
            msg: ("noFence").tr,
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.CENTER,
            timeInSecForIosWeb: 1,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0);
      }
      ;
    });
  }

  void deleteFence(id) {
    setState(() {
      loading = true;
    });
    APIService.destroyGeofence(id).then((value) => {
          setState(() {
            loading = false;
          }),
          Navigator.of(context).pop(false),
          fenceList.clear(),
          selectedFenceList.clear(),
          getFences(),
          setState(() {
            Fluttertoast.showToast(
                msg: ("fenceDeleted").tr,
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.CENTER,
                timeInSecForIosWeb: 1,
                backgroundColor: Colors.green,
                textColor: Colors.white,
                fontSize: 16.0);
          }),
        });
  }

  @override
  void dispose() {
    super.dispose();
    if (_timer != null) {
      _timer!.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(color: CustomColor.cssBlack),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'geofence'.tr,
              style: FlutterFlowTheme.of(context).headlineMedium,
            ),
          ],
        ),
        actions: <Widget>[
          GestureDetector(
            onTap: () {
              setState(() {
                loading = true;
              });
              fenceList.clear();
              getFences();
            },
            child: const Icon(Icons.refresh),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(0, 0, 10, 0)),
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, "/geofenceAdd",
                  arguments: FenceArguments(fenceModel: Geofence()));
            },
            child: const Icon(Icons.add),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(0, 0, 10, 0)),
        ],
        centerTitle: false,
        elevation: 0,
      ),
      body: !isLoading
          ? Column(children: <Widget>[
              Expanded(
                  child: ListView.builder(
                      itemCount: fenceList.length,
                      itemBuilder: (context, index) {
                        final fence = fenceList[index];
                        return fenceCard(fence, context);
                      }))
            ])
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }

  Widget fenceCard(Geofence fence, BuildContext context) {
    return Card(
        elevation: 2.0,
        child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(children: <Widget>[
              InkWell(
                  onTap: () {
                    // Navigator.pushNamed(context, "/geofence",
                    //     arguments: FenceArguments(
                    //         fenceModel: fence,
                    //         deviceId: args!.id,
                    //         name: args!.name));
                  },
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Row(
                                children: [
                                  Checkbox(
                                      value: fence.active.toString() == "1"
                                          ? true
                                          : false,
                                      onChanged: (value) {
                                        if (value!) {
                                          activateFence(fence.id);
                                        } else {
                                          deactivateFence(fence.id);
                                        }
                                      }),
                                  Text(
                                    fence.name!,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),

                              // Checkbox(
                              //     value: selectedFenceList != null
                              //         ? selectedFenceList.contains(fence.id)
                              //             ? true
                              //             : false
                              //         : false,
                              //     onChanged: (value) {
                              //       if (value) {
                              //         updateFence(fence.id);
                              //       } else {
                              //         removeFence(fence.id);
                              //       }
                              //     }),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  deleteFenceConfirm(fence.id);
                                },
                              )
                            ])
                      ]))
            ])));
  }

  Future<dynamic> deleteFenceConfirm(dynamic id) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fence'),
        content: const Text('Are you sure?'),
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => {deleteFence(id)},
            /*Navigator.of(context).pop(true)*/
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }
}

class FenceArguments extends Object {
  Geofence? fenceModel;

  FenceArguments({this.fenceModel});
}
