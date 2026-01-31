import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/loading_spinner.dart';
import '../services/p2p_service.dart';
import '../services/permission_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auth_service.dart'; // New import for AuthService
import '../models/user_status.dart'; // Import UserStatusType

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _statusCtrl = TextEditingController();

  UserProfile? _userProfile; // Use UserProfile from AuthService

  bool _loading = true;
  PermissionRequestResult? _permStatus;
  StreamSubscription<List<Map<String, dynamic>>>? _usersSubscription;
  UserStatusType _currentStatus = UserStatusType.offline;
  UserStatusType? _selectedStatus; // New state for selected status

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _refreshPermStatus();
  }

  // Moved _listenToUsersStream here to ensure it's called after _userProfile is loaded
  void _listenToUsersStream() {
    _usersSubscription = P2PService.instance.usersStream().listen((
      usersData,
    ) async {
      if (!mounted) return;
      final currentUserUid = _userProfile?.uid;
      if (currentUserUid == null) return;

      final updatedMeData = usersData.firstWhere(
        (user) => (user['id'] == currentUserUid),
        orElse: () => <String, dynamic>{},
      );

      if (updatedMeData.isNotEmpty) {
        // If the online status from P2PService is different, update the UI
        final String statusTypeStr =
            updatedMeData['statusType'] ?? UserStatusType.offline.name;
        final UserStatusType currentStatusType = UserStatusType.values
            .firstWhere(
              (e) => e.name == statusTypeStr,
              orElse: () => UserStatusType.offline,
            );
        if (_currentStatus != currentStatusType) {
          setState(() {
            _currentStatus = currentStatusType;
          });
        }
      }
    });
  }

  Future<void> _loadProfile() async {
    _userProfile = await AuthService.instance.getCurrentUser();
    if (_userProfile == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    _nameCtrl.text = _userProfile!.name;
    _photoUrl =
        _userProfile!.photoPath; // Get photo from AuthService's UserProfile

    // Load P2P-specific data
    final meP2PData = await P2PService.instance.getUserDoc(_userProfile!.uid);
    if (meP2PData != null) {
      _statusCtrl.text = meP2PData['status'] ?? '';
      final String statusTypeStr =
          meP2PData['statusType'] ?? UserStatusType.offline.name;
      _currentStatus = UserStatusType.values.firstWhere(
        (e) => e.name == statusTypeStr,
        orElse: () => UserStatusType.offline,
      );
      _selectedStatus = _currentStatus; // Initialize selected status
    } else {
      _selectedStatus = UserStatusType.offline; // Default if no P2P data
    }

    if (mounted) {
      setState(() => _loading = false);
    }

    // Start listening to the users stream only after _userProfile is loaded
    _listenToUsersStream();
  }

  Future<void> _refreshPermStatus() async {
    final s = await PermissionService.checkCameraAndStorage();
    if (!mounted) return;
    setState(() => _permStatus = s);
  }

  String? _photoUrl;

  Future<void> _saveProfile() async {
    if (_userProfile == null) return;
    final messenger = ScaffoldMessenger.of(context);

    // Update AuthService (for name, username, photoPath)
    // For this simple example, we update name in AuthService and P2PService
    final newName = _nameCtrl.text.trim();
    if (newName != _userProfile!.name || _photoUrl != _userProfile!.photoPath) {
      // In a real app, AuthService would have an updateName/updatePhoto method.
      // For now, we'll recreate and save the UserProfile in AuthService to update its state.
      final updatedProfile = UserProfile(
        uid: _userProfile!.uid,
        name: newName,
        username: _userProfile!.username,
        photoPath: _photoUrl, // Use the updated photoUrl
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AuthService.userProfileKey,
        json.encode(updatedProfile.toJson()),
      );
      AuthService.instance.updateCurrentUser(
        updatedProfile,
      ); // Update internal state
      if (mounted) {
        setState(() {
          _userProfile = updatedProfile;
        });
      } // Update local state for UI
    }

    // Update P2PService for profile fields and photoURL
    await P2PService.instance.setProfile(_userProfile!.uid, {
      'name': newName,
      'status': _statusCtrl.text.trim(),
      'photoURL': _photoUrl, // Ensure photoURL is updated in P2PService
      'statusType': _selectedStatus?.name, // Send the new status type
      'updatedAt': DateTime.now().toIso8601String(),
    });

    messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _statusCtrl.dispose();

    _usersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _showImageSourceActionSheet() async {
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
                if (res == PermissionRequestResult.granted) {
                  _pickAndUploadAvatar(ImageSource.camera);
                  return;
                }
                if (!mounted) return;
                if (res == PermissionRequestResult.permanentlyDenied) {
                  final open = await showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('Permission required'),
                      content: const Text(
                        'Camera permission is permanently denied. Open app settings to enable it?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dctx).pop(true),
                          child: const Text('Open settings'),
                        ),
                      ],
                    ),
                  );
                  if (open == true) {
                    await openAppSettings();
                  }
                  return;
                }
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Camera or storage permission denied'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final messenger = ScaffoldMessenger.of(context);
                final res = await PermissionService.requestCameraAndStorage();
                if (res == PermissionRequestResult.granted) {
                  _pickAndUploadAvatar(ImageSource.gallery);
                  return;
                }
                if (!mounted) return;
                if (res == PermissionRequestResult.permanentlyDenied) {
                  final open = await showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('Permission required'),
                      content: const Text(
                        'Storage permission is permanently denied. Open app settings to enable it?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dctx).pop(true),
                          child: const Text('Open settings'),
                        ),
                      ],
                    ),
                  );
                  if (open == true) {
                    await openAppSettings();
                  }
                  return;
                }
                messenger.showSnackBar(
                  const SnackBar(content: Text('Storage permission denied')),
                );
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

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    if (_userProfile == null) return;
    final picker = ImagePicker();
    final res = await picker.pickImage(source: source);
    if (res == null) return;
    File file = File(res.path);
    // crop
    final cropped = await _cropImage(file);
    if (cropped != null) file = cropped;
    // compress/resize
    final compressed = await _compressImage(file);
    if (compressed != null) file = compressed;

    final dest = await P2PService.instance.uploadFile(
      'profiles/${_userProfile!.uid}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file,
    );

    await P2PService.instance.setProfile(_userProfile!.uid, {
      'photoURL': dest,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    final updatedProfile = UserProfile(
      uid: _userProfile!.uid,
      name: _userProfile!.name,
      username: _userProfile!.username,
      photoPath: dest,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AuthService.userProfileKey,
      json.encode(updatedProfile.toJson()),
    );
    AuthService.instance.updateCurrentUser(updatedProfile);

    if (mounted) {
      setState(() {
        _photoUrl = dest;
        _userProfile = updatedProfile;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: LoadingSpinner()),
      );
    }

    if (_userProfile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('User not logged in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              final navigator = Navigator.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Do you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              await AuthService.instance.logout();
              if (!mounted) return;
              navigator.pushReplacementNamed('/');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                        ? (_photoUrl!.startsWith('file://')
                                  ? FileImage(
                                      File(
                                        _photoUrl!.replaceFirst('file://', ''),
                                      ),
                                    )
                                  : (_photoUrl!.startsWith('http')
                                        ? NetworkImage(_photoUrl!)
                                        : null))
                              as ImageProvider?
                        : null,
                    child: (_photoUrl == null || _photoUrl!.isEmpty)
                        ? Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.grey.shade600,
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.blue,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _showImageSourceActionSheet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_permStatus == PermissionRequestResult.granted)
              Center(
                child: TextButton(
                  onPressed: _showImageSourceActionSheet,
                  child: const Text('Change avatar'),
                ),
              ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _userProfile!.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Center(
              child: Text(
                '@${_userProfile!.username}',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _currentStatus.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (_currentStatus.icon != Icons.circle)
                        Icon(
                          _currentStatus.icon,
                          color: Colors.white,
                          size: 10,
                        ),
                    ],
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _currentStatus.displayName,
                    style: TextStyle(
                      color: _currentStatus.color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Online Status',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<UserStatusType>(
              initialValue: _selectedStatus,
              onChanged: (UserStatusType? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedStatus = newValue;
                  });
                }
              },
              items: UserStatusType.values.map((UserStatusType status) {
                return DropdownMenuItem<UserStatusType>(
                  value: status,
                  child: Row(
                    children: [
                      Icon(status.icon, color: status.color, size: 20),
                      const SizedBox(width: 10),
                      Text(status.displayName),
                    ],
                  ),
                );
              }).toList(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            if (_photoUrl != null && _photoUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final me = P2PService.instance.currentUser;
                  if (me == null) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await P2PService.instance.deleteUserAvatar(me.uid);
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Avatar deleted' : 'Delete failed'),
                    ),
                  );
                  setState(() => _photoUrl = null);
                },
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text(
                  'Delete avatar',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_permStatus != PermissionRequestResult.granted)
              Card(
                color: Colors.yellow[50],
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _permStatus ==
                                  PermissionRequestResult.permanentlyDenied
                              ? 'Permissions permanently denied. Open settings to enable camera and gallery access.'
                              : 'Camera or gallery permission is not granted. Please allow to change your avatar.',
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final res =
                              await PermissionService.requestCameraAndStorage();
                          if (!mounted) return;
                          setState(() => _permStatus = res);
                          if (res == PermissionRequestResult.granted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Permissions granted'),
                              ),
                            );
                          }
                        },
                        child: const Text('Request'),
                      ),
                      if (_permStatus ==
                          PermissionRequestResult.permanentlyDenied)
                        TextButton(
                          onPressed: () async => await openAppSettings(),
                          child: const Text('Open settings'),
                        ),
                    ],
                  ),
                ),
              ),
            const Text(
              'Display name',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(hintText: 'Your name'),
            ),
            const SizedBox(height: 12),
            const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _statusCtrl,
              decoration: const InputDecoration(hintText: 'Available'),
            ),

            const SizedBox(height: 8),
            ElevatedButton(onPressed: _saveProfile, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
