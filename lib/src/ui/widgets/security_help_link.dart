import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/screens/security_help_screen.dart';

import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';

/// Opens the self-custody help screen so the security video can be watched
/// again after the first-run offer is dismissed.
class SecurityHelpLink extends StatelessWidget {
  final String label;

  const SecurityHelpLink({super.key, this.label = 'Security video'});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Get.to(() => const SecurityHelpScreen()),
      style: TextButton.styleFrom(
        foregroundColor: subTextColor.value,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: subTextColor.value),
      ),
    );
  }
}
