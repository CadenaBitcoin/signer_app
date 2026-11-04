import 'package:flutter/material.dart';

import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';
import 'primaryButton.dart';

enum SecurityVideoOfferChoice { watch, skip }

/// First-run offer. The system back button does not dismiss it; Watch and
/// Skip are the only ways through, so the choice is explicit.
class SecurityVideoOfferDialog extends StatelessWidget {
  const SecurityVideoOfferDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: cardBgColor.value,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, color: warningColor.value, size: 36),
              const SizedBox(height: 12),
              Text(
                'Your keys stay with you',
                style: AppTextStyles.heading2.copyWith(color: primaryTextColor.value),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'This signer is non-custodial. There is no password reset for your wallet seed. You are responsible for backing it up, and Cadena cannot recover it if it is lost.',
                style: AppTextStyles.body.copyWith(color: subTextColor.value, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                text: 'Watch now',
                onTap: () => Navigator.of(context).pop(SecurityVideoOfferChoice.watch),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                text: 'Skip for now',
                isOutlined: true,
                onTap: () => Navigator.of(context).pop(SecurityVideoOfferChoice.skip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
