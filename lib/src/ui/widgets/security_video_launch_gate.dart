import 'package:flutter/material.dart';
import 'package:signer/services/security_video_offer_store.dart';
import 'package:signer/src/ui/screens/security_help_screen.dart';

import 'security_video_offer_dialog.dart';

/// Shows the security-video offer once, over [child], on the first launch
/// where it has not been offered yet.
class SecurityVideoLaunchGate extends StatefulWidget {
  final Widget child;

  const SecurityVideoLaunchGate({super.key, required this.child});

  @override
  State<SecurityVideoLaunchGate> createState() => _SecurityVideoLaunchGateState();
}

class _SecurityVideoLaunchGateState extends State<SecurityVideoLaunchGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _offerIfNeeded();
    });
  }

  Future<void> _offerIfNeeded() async {
    final store = await SecurityVideoOfferStore.load();
    if (!mounted || store.wasOffered) return;

    final choice = await showDialog<SecurityVideoOfferChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SecurityVideoOfferDialog(),
    );
    if (!mounted || choice == null) return;

    await store.markOffered();
    if (!mounted || choice != SecurityVideoOfferChoice.watch) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SecurityHelpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
