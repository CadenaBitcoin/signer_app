import 'package:flutter/material.dart';
import 'package:signer/src/ui/screens/createWallet/verify_seed_phrase_screen.dart';
import 'package:signer/src/ui/theme/colors.dart';
import 'package:signer/src/ui/widgets/custody_acknowledgement.dart';
import 'package:signer/src/ui/widgets/primaryButton.dart';
import 'package:bip39/bip39.dart' as bip39;

class SeedPhraseScreen extends StatefulWidget {
  final String? fromPage;

  final String mnemonic;
  final String email;
  final String password;

  const SeedPhraseScreen({super.key, required this.mnemonic, required this.email, required this.password, this.fromPage});

  @override
  _SeedPhraseScreenState createState() => _SeedPhraseScreenState();
}

class _SeedPhraseScreenState extends State<SeedPhraseScreen> {
  late String _mnemonic;
  CustodyAcknowledgementState _acknowledgement = const CustodyAcknowledgementState();

  @override
  void initState() {
    super.initState();
    _mnemonic = widget.mnemonic;
  }
  resetMnemonic() {
    setState(() {
      _mnemonic = bip39.generateMnemonic();
      _acknowledgement = const CustodyAcknowledgementState();
    });
  }

  void _onVerifyPressed() {
    if (!_acknowledgement.allAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Confirm all three statements before continuing.',
          ),
          backgroundColor: warningColor.value,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmSeedPhraseScreen(
          mnemonic: _mnemonic,
          email: widget.email,
          password: widget.password,
          fromPage: widget.fromPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final words = _mnemonic.split(' ');

    return Scaffold(
      backgroundColor: primaryBackgroundColor.value,
      appBar: AppBar(
        backgroundColor: primaryBackgroundColor.value,
        elevation: 0,
        centerTitle: true,
        title: Text("Your Seed Phrase", style: TextStyle(color: primaryTextColor.value, fontWeight: FontWeight.w600)),
        iconTheme: IconThemeData(color: primaryTextColor.value),
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Text(
                'Write these words down, in order, and store them offline. You will confirm three of them next.',
                style: TextStyle(color: warningColor.value, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (_mnemonic.isNotEmpty)
                Expanded(
                  child: GridView.builder(
                    itemCount: words.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.5),
                    itemBuilder: (_, index) {
                      return Container(
                        decoration: BoxDecoration(
                          color: cardBgColor.value,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: dividerColor.value),
                          boxShadow: [BoxShadow(color: surfaceColor.value.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: Center(child: Text('${index + 1}. ${words[index]}', style: TextStyle(color: primaryTextColor.value, fontWeight: FontWeight.w600, fontSize: 14))),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              CustodyAcknowledgement(
                value: _acknowledgement,
                onChanged: (next) => setState(() => _acknowledgement = next),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                text: "Generate New Seed",
                onTap: () async {
                  await resetMnemonic();
                },
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: _acknowledgement.allAccepted ? 1 : 0.45,
                child: PrimaryButton(
                  text: "Verify Seed Phrase",
                  onTap: _onVerifyPressed,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }
}
