import 'package:flutter/material.dart';

import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';

/// Explicit self-custody confirmation collected before a new seed can be saved.
class CustodyAcknowledgementState {
  static const String noPasswordResetLabel =
      'I understand there is no password reset for my wallet seed.';
  static const String responsibleForBackupLabel =
      'I am responsible for backing up my seed phrase and keeping it private.';
  static const String cadenaCannotRecoverLabel =
      'I understand Cadena cannot recover my seed if I lose it.';

  final bool noPasswordReset;
  final bool responsibleForBackup;
  final bool cadenaCannotRecover;

  const CustodyAcknowledgementState({
    this.noPasswordReset = false,
    this.responsibleForBackup = false,
    this.cadenaCannotRecover = false,
  });

  bool get allAccepted =>
      noPasswordReset && responsibleForBackup && cadenaCannotRecover;

  CustodyAcknowledgementState copyWith({
    bool? noPasswordReset,
    bool? responsibleForBackup,
    bool? cadenaCannotRecover,
  }) {
    return CustodyAcknowledgementState(
      noPasswordReset: noPasswordReset ?? this.noPasswordReset,
      responsibleForBackup: responsibleForBackup ?? this.responsibleForBackup,
      cadenaCannotRecover: cadenaCannotRecover ?? this.cadenaCannotRecover,
    );
  }
}

class CustodyAcknowledgement extends StatelessWidget {
  final CustodyAcknowledgementState value;
  final ValueChanged<CustodyAcknowledgementState> onChanged;

  const CustodyAcknowledgement({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: inputFieldBackgroundColor.value,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value.allAccepted ? successColor.value : warningColor.value,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm before you continue',
            style: AppTextStyles.heading3.copyWith(color: primaryTextColor.value),
          ),
          const SizedBox(height: 4),
          Text(
            'Your seed is the only way back into this wallet.',
            style: AppTextStyles.caption.copyWith(color: subTextColor.value),
          ),
          _item(
            key: const Key('ack-no-password-reset'),
            label: CustodyAcknowledgementState.noPasswordResetLabel,
            checked: value.noPasswordReset,
            onChanged: (checked) =>
                onChanged(value.copyWith(noPasswordReset: checked)),
          ),
          _item(
            key: const Key('ack-responsible-for-backup'),
            label: CustodyAcknowledgementState.responsibleForBackupLabel,
            checked: value.responsibleForBackup,
            onChanged: (checked) =>
                onChanged(value.copyWith(responsibleForBackup: checked)),
          ),
          _item(
            key: const Key('ack-cadena-cannot-recover'),
            label: CustodyAcknowledgementState.cadenaCannotRecoverLabel,
            checked: value.cadenaCannotRecover,
            onChanged: (checked) =>
                onChanged(value.copyWith(cadenaCannotRecover: checked)),
          ),
        ],
      ),
    );
  }

  Widget _item({
    required Key key,
    required String label,
    required bool checked,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      key: key,
      value: checked,
      onChanged: (next) => onChanged(next ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: primaryColor.value,
      checkColor: primaryBackgroundColor.value,
      side: BorderSide(color: borderColor.value, width: 1.4),
      title: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: primaryTextColor.value,
          height: 1.3,
        ),
      ),
    );
  }
}
