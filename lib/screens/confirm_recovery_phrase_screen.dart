import 'dart:io';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/loading_spinner.dart'; // Ensure LoadingSpinner is available

class ConfirmRecoveryPhraseScreen extends StatefulWidget {
  const ConfirmRecoveryPhraseScreen({super.key});

  @override
  State<ConfirmRecoveryPhraseScreen> createState() =>
      _ConfirmRecoveryPhraseScreenState();
}

class _ConfirmRecoveryPhraseScreenState
    extends State<ConfirmRecoveryPhraseScreen> {
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndFinish() async {
    final enteredPhrase = _confirmCtrl.text.trim();
    if (enteredPhrase.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your recovery phrase.')),
      );
      return;
    }

    final routeArgs =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final originalPhrase = routeArgs['phrase'] as String;
    final name = routeArgs['name'] as String;

    if (enteredPhrase != originalPhrase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The recovery phrase does not match.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await AuthService.instance.signUp(
        name: name,
        username: routeArgs['username'] as String,
        phrase: originalPhrase,
        avatar: routeArgs['avatar'] as File?,
      );

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/welcome',
          (route) => false,
          arguments: {'name': name},
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred during sign up.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Recovery Phrase'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'To complete your registration, please re-enter the recovery phrase you just saved.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _confirmCtrl,
                decoration: InputDecoration(
                  labelText: 'Recovery Phrase',
                  hintText: 'Enter the exact phrase here',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                ),
                maxLines: 3,
                minLines: 1,
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _loading ? null : _confirmAndFinish,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: LoadingSpinner(size: 20),
                      )
                    : const Text(
                        'Confirm & Finish',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
