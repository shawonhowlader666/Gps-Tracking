import 'package:flutter/material.dart';
import 'package:gpspro/theme/custom_color.dart';

class CustomButtonItemMore extends StatelessWidget {
  const CustomButtonItemMore(
      {super.key, @required this.onTap,
      @required this.buttonText,
      @required this.imagePath,
      @required this.color});

  final Function()? onTap;
  final Color? color;
  final String? buttonText;
  final IconData? imagePath;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
          child: Container(
        height: 40,
        width: MediaQuery.of(context).size.width * 0.3,
        padding: EdgeInsets.only(left: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color!),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(imagePath, size: 25, color: CustomColor.primaryColor),
            SizedBox(
              width: 5,
            ),
            Expanded(
                child: Text(buttonText!,
                    style: TextStyle(
                        decoration: TextDecoration.none,
                        color: color,
                        fontWeight: FontWeight.w500,
                        fontSize: 12))),
          ],
        ),
      )),
    );
  }
}
