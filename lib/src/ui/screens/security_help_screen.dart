import 'package:flutter/material.dart';
import 'package:signer/config/security_video.dart';
import 'package:signer/services/security_video_launcher.dart';

import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';
import '../widgets/primaryButton.dart';

/// Help entry for the self-custody briefing. Opened from first-run "Watch now"
/// and from Help later, including when the video URL is still a placeholder.
class SecurityHelpScreen extends StatefulWidget {
  final SecurityVideoLauncher launcher;

  const SecurityHelpScreen({
    super.key,
    this.launcher = const SecurityVideoLauncher(),
  });

  @override
  State<SecurityHelpScreen> createState() => _SecurityHelpScreenState();
}

class _SecurityHelpScreenState extends State<SecurityHelpScreen> {
  bool _opening = false;

  Future<void> _play() async {
    if (_opening) return;
    setState(() => _opening = true);
    final result = await widget.launcher.open();
    if (!mounted) return;
    setState(() => _opening = false);
    if (result == SecurityVideoLaunchResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open the security video.'),
          backgroundColor: errorColor.value,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoReady = isSecurityVideoConfigured(kSecurityVideoUrl);
    return Scaffold(
      backgroundColor: primaryBackgroundColor.value,
      appBar: AppBar(
        backgroundColor: primaryBackgroundColor.value,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryTextColor.value),
        title: Text(
          'Help',
          style: TextStyle(
            color: primaryTextColor.value,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              'Self-custody and backups',
              style: AppTextStyles.heading2.copyWith(color: primaryTextColor.value),
            ),
            const SizedBox(height: 12),
            Text(
              'Cadena Signer is non-custodial. The seed phrase is created and stored on this device. Cadena never receives it, so nobody else can reset it for you.',
              style: AppTextStyles.body.copyWith(color: subTextColor.value, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (videoReady)
              PrimaryButton(
                text: 'Play security video',
                onTap: _play,
                isLoading: _opening,
                loadingText: 'Opening...',
              )
            else
              _placeholderCard(),
            const SizedBox(height: 20),
            _rule(
              'No password reset',
              'The app password only unlocks this device. It cannot restore a lost seed phrase.',
            ),
            _rule(
              'You back it up',
              'Write the 12 words down, in order, and keep that copy offline and private.',
            ),
            _rule(
              'Cadena cannot recover it',
              'If the seed is lost, access to the wallet is lost with it.',
            ),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _placeholderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: inputFieldBackgroundColor.value,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.value),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ondemand_video_outlined, color: warningColor.value),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Video not available yet',
                  style: AppTextStyles.heading3.copyWith(color: primaryTextColor.value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The security video has not been published. The written briefing on this screen is the same message it will cover. You can open Help again after the video is added.',
            style: AppTextStyles.body.copyWith(color: subTextColor.value, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _rule(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: primaryColor.value, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.heading3.copyWith(color: primaryTextColor.value),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTextStyles.body.copyWith(color: subTextColor.value, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
