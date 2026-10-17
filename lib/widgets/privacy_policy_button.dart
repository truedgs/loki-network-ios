import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyButton extends StatelessWidget {
  const PrivacyPolicyButton({super.key});

  static final policyUrl = Uri.https('policy.v2premium.com');

  Future<void> _openPolicy(BuildContext context) async {
    try {
      if (await launchUrl(policyUrl, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // A device may have no browser or may reject the launch request.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open https://policy.v2premium.com. Try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _openPolicy(context),
      icon: const Icon(Icons.privacy_tip_outlined),
      label: const Text('Privacy Policy'),
    );
  }
}
