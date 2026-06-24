import 'package:flutter/material.dart';

class ListViewTopItem extends StatelessWidget {
  final String? text;
  final Color? color;
  final bool? isSelected;
  final Function()? onTap;

  const ListViewTopItem(
      {super.key, this.text, this.color, this.isSelected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        curve: Curves.fastLinearToSlowEaseIn,
        duration: const Duration(milliseconds: 1000),
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 18),
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isSelected! ? color : Colors.white,
          border: Border.all(color: color!, width: 1),
          borderRadius: BorderRadius.circular(5.0),
          //boxShadow: [BoxShadow(color: isSelected? color.withOpacity(.4):Colors.transparent,blurRadius: 3.0,offset: Offset(0,3))]
        ),
        child: Center(
            child: Text(text!,
                style: TextStyle(
                    decoration: TextDecoration.none,
                    color: isSelected! ? Colors.white : color,
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w500))),
      ),
    );
  }
}
