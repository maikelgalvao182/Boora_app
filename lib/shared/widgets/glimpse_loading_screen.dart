import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';

class GlimpseLoadingScreen extends StatelessWidget {
  const GlimpseLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: CupertinoActivityIndicator(
          radius: 16.r,
          color: GlimpseColors.primaryColorLight,
        ),
      ),
    );
  }
}
