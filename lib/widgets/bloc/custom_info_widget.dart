import 'package:flutter/material.dart';
class Window extends StatefulWidget {
  double? offsetY = 0,
      offsetX = 0;
  final Map<String, String>? data;

  Window({
    Key? key,
    this.offsetX,
    this.offsetY,
    this.data,
  }) : super(key: key);

  @override
  _WindowState createState() => _WindowState();
}
  class _WindowState extends State<Window> {
    double offsetY = 0,
        offsetX = 0;

    @override
    void initState() {
      super.initState();
    }

    @override
    Widget build(BuildContext context) {
      return Transform(
            transform: Matrix4.translationValues(widget.offsetX!, widget.offsetY!, 0.0),
            child: ClipPath(
              clipper: MyCustomClipper(),
              child: Container(
                width: 250,
                  padding:
                  EdgeInsets.only(top: 15, left: 15, right: 15, bottom: 30),
                  margin: EdgeInsets.only(top: 15, left: 15, right: 15),
                  color: Colors.white,
                  child: Wrap(
                    children: <Widget>[
                      Column(
                        children: [
                          for (int i = 0; i < widget.data!.length; i++)
                            RowsWidget(
                              title: widget.data!.keys.elementAt(i),
                              value: widget.data!.values.elementAt(i),
                            )
                        ],
                      ),
                    ],
                  )),
            ),
          );
    }
  }
  class RowsWidget extends StatelessWidget {
    final String? title, value;

    RowsWidget({this.title, this.value});

    @override
    Widget build(BuildContext context) {
      return Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Flexible(
                fit: FlexFit.tight,
                flex: 2,
                child: Text(
                  title!,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              Flexible(
                flex: 4,
                child: Text(
                  value!,
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 5,
          )
        ],
      );
    }
  }
  class MyCustomClipper extends CustomClipper<Path> {
    @override
    Path getClip(Size size) {
      double width = size.width;
      double height = size.height;
      final path = Path();
      path.lineTo(0.0, size.height - 30);
      path.quadraticBezierTo(0.0, size.height - 25, 5.0, size.height - 25);
      path.lineTo(size.width - 5.0, size.height - 25);
      path.lineTo((width / 2) - 15, height - 25);
      path.lineTo((width / 2), height);
      path.lineTo((width / 2) + 15, height - 25);
      path.lineTo(width - 5, height - 25);
      path.quadraticBezierTo(
          size.width, size.height - 25, size.width, size.height - 30);
      path.lineTo(size.width, 5.0);
      path.quadraticBezierTo(size.width, 0.0, size.width - 5.0, 0.0);
      path.lineTo(5.0, 0.0);
      path.quadraticBezierTo(0.0, 0.0, 0.0, 5.0);
      return path;
    }
    @override
    bool shouldReclip(CustomClipper<Path> oldClipper) => true;
  }