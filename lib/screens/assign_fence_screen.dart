// import 'package:flutter/material.dart';
// import 'package:smart_lock/services/model/geofence_model.dart';
// import 'package:smart_lock/theme/custom_color.dart';
//
// List<Geofence> fenceList = [];
// List<String> selectedFenceList = [];
// Widget AssignFenceScreen(
//     BuildContext context, StateSetter setState, bool loading) {
//   return Container(
//     child: Column(
//       children: [
//         Container(
//             decoration: BoxDecoration(
//               color: CustomColor.primaryColor,
//             ),
//             width: MediaQuery.of(context).size.width,
//             height: 50,
//             padding: EdgeInsets.only(left: 5, right: 5),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text("Fences",
//                     style: TextStyle(color: Colors.white, fontSize: 15)),
//                 InkWell(
//                   onTap: () {
//                     Navigator.pop(context);
//                   },
//                   child: Icon(
//                     Icons.close,
//                     color: Colors.white,
//                   ),
//                 )
//               ],
//             )),
//         Expanded(
//             child: !loading
//                 ? ListView.builder(
//                     itemCount: fenceList.length,
//                     itemBuilder: (context, index) {
//                       final f = fenceList[index];
//                       return FenceCard(f, context, setState);
//                     },
//                   )
//                 : Center(child: CircularProgressIndicator()))
//       ],
//     ),
//   );
// }
//
// Widget FenceCard(Geofence f, BuildContext context, StateSetter setState) {
//   return ListTile(
//     leading: Checkbox(
//         //ignore: unnecessary_null_comparison
//         value: selectedFenceList != null
//             ? selectedFenceList.contains("geofences[]=" + f.id.toString())
//                 ? true
//                 : false
//             : false,
//         onChanged: (value) {
//           if (value!) {
//             setState(() {
//               selectedFenceList.add("geofences[]=" + f.id.toString());
//             });
//           } else {
//             setState(() {
//               selectedFenceList.remove("geofences[]=" + f.id.toString());
//             });
//           }
//         }),
//     title: Row(
//       mainAxisAlignment: MainAxisAlignment.start,
//       children: <Widget>[
//         new Text(f.name!, style: TextStyle(fontSize: 13.0)),
//       ],
//     ),
//   );
// }
