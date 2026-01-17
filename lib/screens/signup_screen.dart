import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../services/permission_service.dart';
import '../services/auth/username_service.dart';
import '../widgets/loading_spinner.dart'; // Ensure LoadingSpinner is available

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  File? _avatar;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
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
                final messenger = ScaffoldMessenger.of(context);
                final res = await PermissionService.requestCameraAndStorage();
                if (res != PermissionRequestResult.granted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Permission denied.')),
                  );
                  return;
                }
                await _pickAndSetAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final messenger = ScaffoldMessenger.of(context);
                final res = await PermissionService.requestCameraAndStorage();
                if (res != PermissionRequestResult.granted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Permission denied.')),
                  );
                  return;
                }
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

  Future<void> _next() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();

    if (name.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() => _loading = true);

    final isAvailable = await UsernameService.instance.isUsernameAvailable(
      username,
    );

    if (!mounted) return;

    if (!isAvailable) {
      setState(() => _loading = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('This username is already taken.')),
      );
      return;
    }

    Navigator.of(context).pushNamed(
      '/recovery-phrase',
      arguments: {'name': name, 'username': username, 'avatar': _avatar},
    );

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Your Profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.blue.shade100,
                    backgroundImage: _avatar != null
                        ? FileImage(_avatar!)
                        : null,
                    child: _avatar == null
                        ? Icon(
                            Icons.camera_alt_outlined,
                            size: 40,
                            color: Colors.blue.shade600,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'Enter your display name',
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
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameCtrl,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'Choose a unique username',
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
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _loading ? null : _next,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Theme.of(
                    context,
                  ).primaryColor, // Use theme primary color
                  foregroundColor: Colors.white, // Text color
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: LoadingSpinner(size: 20),
                      )
                    : const Text('Next', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
