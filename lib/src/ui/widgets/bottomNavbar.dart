import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:signer/services/auto_signing_service.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/src/ui/screens/SignTransactionScreen.dart';

import '../controllers/appController.dart';
import '../screens/HomeScreen.dart';
import '../screens/verifyIdentity.dart';
import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';

class BottomNavBar extends StatefulWidget {
  bool? checkVerification;
  BottomNavBar({super.key, this.checkVerification});

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  List pages = [HomeScreen(), SignTransactions(), VerifyIdentity()];
  AppController appController = Get.find<AppController>();
  final AutoSigningService autoSigningService = Get.find<AutoSigningService>();
  DateTime? lastPressed;
  late DateTime currentBackPressTime;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> getLoggedInEmail() async {
    return await _storage.read(key: 'logged_in_user_email');
  }

  void fetchUser() async {
    var email = await getLoggedInEmail();

    final user = await StorageService.getUserByEmail('${email}');

    if (user != null) {
      print("User data found");
    } else {
      print("User not found");
    }
  }

  @override
  void initState() {
    fetchUser();
    // Start auto-signing service when app is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (autoSigningService.isEnabled) {
        autoSigningService.resumePolling();
      }
    });
    super.initState();
  }

  @override
  void dispose() async {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        bottomNavigationBar: Obx(
          () => SafeArea(
            child: Container(
              height: 70,
              padding: EdgeInsets.symmetric(vertical: 3, horizontal: 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                color: primaryBackgroundColor.value,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: InkWell(
                          splashColor: Colors.transparent,
                          onTap: () async {
                            appController.selectedBottomTabIndex.value = 0;
                          },
                          child: SizedBox(
                            height: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Home',
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight:
                                        appController
                                                    .selectedBottomTabIndex
                                                    .value ==
                                                0
                                            ? FontWeight.w600
                                            : null,
                                    color:
                                        appController
                                                    .selectedBottomTabIndex
                                                    .value ==
                                                0
                                            ? primaryTextColor.value
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          splashColor: Colors.transparent,
                          onTap: () async {
                            appController.selectedBottomTabIndex.value = 1;
                          },
                          child: SizedBox(
                            height: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Sign',
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight:
                                        appController
                                                    .selectedBottomTabIndex
                                                    .value ==
                                                1
                                            ? FontWeight.w600
                                            : null,
                                    color:
                                        appController
                                                    .selectedBottomTabIndex
                                                    .value ==
                                                1
                                            ? primaryTextColor.value
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          splashColor: Colors.transparent,
                          onTap: () async {
                            appController.selectedBottomTabIndex.value = 2;
                          },
                          child: SizedBox(
                            height: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Recover',
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight:
                                        appController
                                                    .selectedBottomTabIndex
                                                    .value ==
                                                2
                                            ? FontWeight.w600
                                            : null,
                                    color:
                                        appController
                                                    .selectedBottomTabIndex
                                                    .value ==
                                                2
                                            ? primaryTextColor.value
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: pages.elementAt(appController.selectedBottomTabIndex.value),
      ),
    );
  }
}
