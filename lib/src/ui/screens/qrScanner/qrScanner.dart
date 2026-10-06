import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:signer/src/ui/screens/qrScanner/scanResult.dart';
import 'package:signer/src/ui/theme/app_Text_Styles.dart';
import 'package:signer/src/ui/theme/colors.dart';

class QrScanner extends StatefulWidget {
  const QrScanner({Key? key}) : super(key: key);

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> {
  MobileScannerController cameraController = MobileScannerController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryBackgroundColor.value,
      body: SafeArea(
        child: Container(
          // decoration: BoxDecoration(
          //     gradient: LinearGradient(
          //         stops: [0.1,0.5],
          //         begin: Alignment.centerLeft,
          //         end: Alignment.centerRight,
          //         colors: [fadeColor,primaryColor.value,])
          // ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SizedBox(width: 16),
                      GestureDetector(
                        onTap: () {
                          Get.back();
                        },
                        child: Container(
                          height: 32,
                          width: 32,
                          // decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xffFFFFFF), border: Border.all(width: 1, color: borderColor.value)),
                          child: Center(child: Icon(Icons.arrow_back_ios, color: Colors.white)),
                        ),
                      ),
                      SizedBox(width: 7),
                      Text('Qr Scanner', style: TextStyle(fontSize: 16, color: Color(0xffFFFFFF)), textAlign: TextAlign.center),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 30.0),
                decoration: BoxDecoration(color: primaryBackgroundColor.value, borderRadius: BorderRadius.only(topLeft: Radius.circular(20.0), topRight: Radius.circular(20.0))),
                constraints: BoxConstraints(minHeight: Get.height - 110, minWidth: Get.width, maxWidth: Get.width),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
                      clipBehavior: Clip.antiAlias,
                      child: MobileScanner(
                        // fit: BoxFit.contain,
                        controller: cameraController,
                        onDetect: (capture) {
                          final List<Barcode> barcodes = capture.barcodes;
                          final Uint8List? image = capture.image;
                          for (final barcode in barcodes) {
                            cameraController.dispose();
                            Get.to(ScanResult(result: barcode.rawValue));
                            // Get.back(result: barcode.rawValue);
                          }
                        },
                      ),
                    ),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
