import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/bindings/app_binding.dart';

import 'package:casa_loop_engine/helpers/themes/app_theme.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

import 'routes/app_pages.dart';

class CasaLoopApp extends StatelessWidget {
  const CasaLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Diag.sync(
      'CasaLoopApp.build',
      () => ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        builder: (context, child) => Diag.sync(
          'CasaLoopApp.build.materialApp',
          () => GetMaterialApp(
            title: 'Casa Loop Engine',
            theme: AppTheme.light,
            initialRoute: AppPages.initial,
            getPages: AppPages.pages,
            initialBinding: AppBinding(),
          ),
        ),
      ),
    );
  }
}
