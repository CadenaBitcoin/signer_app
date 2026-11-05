import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/screens/signInScreen.dart';
import 'package:signer/src/ui/widgets/primaryButton.dart';

import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';
import '../widgets/security_help_link.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Welcome to Cadena Bitcoin",
                      style: AppTextStyles.heading2.copyWith(color: primaryTextColor.value, fontSize: 22), textAlign: TextAlign.center),
                  const SizedBox(height: 40),
                  Image.asset('assets/transparentLogo.png'),
                  const SizedBox(height: 40),

                  PrimaryButton(
                    text: 'Launch',
                    onTap: () {
                      Get.to(SignInScreen());
                    },
                  ),
                  const SizedBox(height: 8),
                  const SecurityHelpLink(),
                  // const SizedBox(height: 16),
                  //
                  // PrimaryButton(
                  //   text: 'Register',
                  //   onTap: () {
                  //     Get.to(SignUpScreen());
                  //   },
                  //   isOutlined: true,
                  // ),
                  SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
