import 'dart:io';
import 'dart:developer' as developer;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../services/permission_service.dart';
import '../services/recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/loading_spinner.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameCtrl = TextEditingController();
  final _recoveryHintCtrl = TextEditingController();
  File? _avatar;
  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _recoveryHintCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    // Show action sheet to choose camera or gallery
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take photo'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final res = await PermissionService.requestCameraAndStorage();
                if (res != PermissionRequestResult.granted) return;
                await _pickAndSetAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final res = await PermissionService.requestCameraAndStorage();
                if (res != PermissionRequestResult.granted) return;
                await _pickAndSetAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<File?> _cropImage(File file) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        uiSettings: [
          AndroidUiSettings(
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            toolbarTitle: 'Crop avatar',
          ),
          IOSUiSettings(title: 'Crop avatar'),
        ],
      );
      if (cropped == null) return null;
      return File(cropped.path);
    } catch (_) {
      return file;
    }
  }

  Future<File?> _compressImage(File file) async {
    try {
      final tmp = await getTemporaryDirectory();
      final targetPath =
          '${tmp.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await FlutterImageCompress.compressWithFile(
        file.path,
        quality: 85,
        minWidth: 600,
      );
      if (bytes != null) {
        final outFile = File(targetPath);
        await outFile.writeAsBytes(bytes);
        return outFile;
      }
      return file;
    } catch (_) {
      return file;
    }
  }

  Future<void> _pickAndSetAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final res = await picker.pickImage(source: source);
    if (res == null) return;
    File file = File(res.path);
    final cropped = await _cropImage(file);
    if (cropped != null) file = cropped;
    final compressed = await _compressImage(file);
    if (compressed != null) file = compressed;
    setState(() => _avatar = file);
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (username.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('กรุณาใส่ชื่อผู้ใช้')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // Generate or ensure recovery phrase
      final phrase = await RecoveryService.instance.ensureRecoveryPhrase();

      // Persist a simple user profile locally
      final prefs = await SharedPreferences.getInstance();
      final uid = 'user_${DateTime.now().millisecondsSinceEpoch}';
      String? photoPath;
      if (_avatar != null) {
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final dest = File('${appDir.path}/avatar_$uid.jpg');
          await _avatar!.copy(dest.path);
          photoPath = dest.path;
        } catch (_) {}
      }
      final profile = {
        'uid': uid,
        'username': username,
        'photo': photoPath ?? '',
        'recovery': phrase,
      };
      await prefs.setString('user_profile', json.encode(profile));

      if (!mounted) return;
      // Show recovery phrase to user and require them to confirm saving it
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Recovery phrase'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('โปรดเก็บคำกู้คืนนี้ไว้ในที่ปลอดภัย'),
                const SizedBox(height: 12),
                SelectableText(phrase),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e, st) {
      // Log full error for debugging, but show a friendly message to users.
      developer.log(
        '[Register] signUp error',
        name: 'Register',
        error: e,
        stackTrace: st,
      );
      final messenger = ScaffoldMessenger.of(context);
      final msg = 'สมัครสมาชิกล้มเหลว';
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Create Account',
          style: TextStyle(color: Colors.black),
        ),
        leading: BackButton(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _avatar != null
                          ? FileImage(_avatar!)
                          : null,
                      child: _avatar == null
                          ? const Icon(
                              Icons.camera_alt_outlined,
                              size: 30,
                              color: Colors.black45,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Optional note about recovery phrase
                TextField(
                  controller: _recoveryHintCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Recovery hint (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: LoadingSpinner(size: 16),
                        )
                      : const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
