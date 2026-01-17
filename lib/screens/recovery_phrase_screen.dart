import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/recovery_service.dart';
import '../widgets/loading_spinner.dart'; // Ensure LoadingSpinner is available

class RecoveryPhraseScreen extends StatefulWidget {
  const RecoveryPhraseScreen({super.key});

  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen> {
  String? _phrase;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _generatePhrase();
  }

  Future<void> _generatePhrase() async {
    setState(() => _loading = true);
    final newPhrase = await RecoveryService.instance.ensureRecoveryPhrase();
    if (mounted) {
      setState(() {
        _phrase = newPhrase;
        _loading = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_phrase == null) return;
    Clipboard.setData(ClipboardData(text: _phrase!));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard!')));
  }

  void _next() {
    final routeArgs =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    Navigator.of(context).pushNamed(
      '/confirm-recovery-phrase',
      arguments: {...routeArgs, 'phrase': _phrase},
    );
  }

  @override
  Widget build(BuildContext context) {
    final words = _phrase?.split(' ') ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Recovery Phrase'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please write down or copy these words in the right order and keep them in a safe place. You will need them to recover your account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _loading || _phrase == null
                    ? const Center(child: LoadingSpinner(size: 30))
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2.5,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: words.length,
                        itemBuilder: (context, index) {
                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}. ${words[index]}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, color: Colors.blueAccent),
                label: const Text(
                  'Copy Phrase',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 16),
                ),
                onPressed: _phrase == null ? null : _copyToClipboard,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.blueAccent.shade100),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _phrase == null ? null : _next,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Next', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
