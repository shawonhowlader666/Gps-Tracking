import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:gpspro/arguments/report_args.dart';
import 'package:gpspro/flutter_flow/flutter_flow_theme.dart';
import 'package:gpspro/theme/custom_color.dart';

class ReportListPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => new _ReportListPageState();
}

class _ReportListPageState extends State<ReportListPage> {
  static ReportArguments? args;

  Material Items(IconData icon, String heading, Color cColor) {
    return Material(
        color: Colors.white,
        elevation: 14.0,
        shadowColor: CustomColor.primaryColor,
        borderRadius: BorderRadius.circular(24.0),
        child: InkWell(
          onTap: () {
            if (heading == ('generalInformation').tr) {
              Navigator.pushNamed(context, "/reportRoute",
                  arguments: ReportArguments(
                      args!.id,
                      args!.fromDate,
                      args!.fromTime,
                      args!.toDate,
                      args!.name,
                      args!.name,
                      1,
                      args!.deviceItem));
            } else if (heading == ('drivesAndStops').tr) {
              Navigator.pushNamed(context, "/reportStop",
                  arguments: ReportArguments(
                      args!.id,
                      args!.fromDate,
                      args!.fromTime,
                      args!.toDate,
                      args!.name,
                      args!.name,
                      3,
                      args!.deviceItem));
            } else if (heading == ('reportEvents').tr) {
              Navigator.pushNamed(context, "/reportEvent",
                  arguments: ReportArguments(
                      args!.id,
                      args!.fromDate,
                      args!.fromTime,
                      args!.toDate,
                      args!.name,
                      args!.name,
                      8,
                      args!.deviceItem));
            } else if (heading == ('geofenceInOut').tr) {
              Navigator.pushNamed(context, "/reportStop",
                  arguments: ReportArguments(
                      args!.id,
                      args!.fromDate,
                      args!.fromTime,
                      args!.toDate,
                      args!.name,
                      args!.name,
                      7,
                      args!.deviceItem));
            } else if (heading == ('workHoursDaily').tr) {
              Navigator.pushNamed(context, "/reportSummary",
                  arguments: ReportArguments(
                      args!.id,
                      args!.fromDate,
                      args!.fromTime,
                      args!.toDate,
                      args!.name,
                      args!.name,
                      48,
                      args!.deviceItem));
            }
          },
          child: Container(
              height: 150,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Expanded(
                            child: Container(
                              width: 140,
                              padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                              child: Text(
                                heading,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cColor,
                                  fontSize: 15.0,
                                ),
                              ),
                            ),
                          ),
                          Material(
                            color: cColor,
                            borderRadius: BorderRadius.circular(24.0),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Icon(
                                icon,
                                color: Colors.white,
                                size: 30.0,
                              ),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              )),
        ));
  }

  @override
  Widget build(BuildContext context) {
    args = ModalRoute.of(context)!.settings.arguments as ReportArguments;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(color: CustomColor.cssBlack),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'reportDashboard'.tr,
              style: FlutterFlowTheme.of(context).headlineMedium,
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: Padding(
          padding: EdgeInsets.only(top: 20),
          child: StaggeredGrid.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
            children: <Widget>[
              Items(Icons.show_chart, ('generalInformation').tr,
                  CustomColor.primaryColor),
              Items(Icons.info_outline, ('drivesAndStops').tr,
                  CustomColor.primaryColor),
              Items(Icons.timeline, ('reportEvents').tr,
                  CustomColor.primaryColor),
              Items(
                  Icons.block, ('geofenceInOut').tr, CustomColor.primaryColor),
              Items(
                  Icons.list, ('workHoursDaily').tr, CustomColor.primaryColor),
              //Items(Icons.assessment, "Chart", 0xFF1E88E5)
            ],
          )),
    );
  }
}
