import 'package:permission_handler/permission_handler.dart';

enum PermissionRequestResult { granted, denied, permanentlyDenied }

class PermissionService {
  /// Request camera + gallery/storage permissions.
  /// Returns a [PermissionRequestResult] describing the outcome.
  static Future<PermissionRequestResult> requestCameraAndStorage() async {
    // Allow tests to override behavior
    if (testRequestHandler != null) return await testRequestHandler!();
    // Camera
    final camStatus = await Permission.camera.request();
    if (camStatus.isGranted) {
      // Continue to request gallery/storage
    } else if (camStatus.isPermanentlyDenied) {
      return PermissionRequestResult.permanentlyDenied;
    } else {
      return PermissionRequestResult.denied;
    }

    // Gallery / photos: prefer photos (Android 13 & iOS); fallback to storage
    PermissionStatus galleryStatus;
    try {
      galleryStatus = await Permission.photos.request();
    } catch (_) {
      galleryStatus = await Permission.storage.request();
    }

    if (galleryStatus.isGranted) return PermissionRequestResult.granted;
    if (galleryStatus.isPermanentlyDenied) {
      return PermissionRequestResult.permanentlyDenied;
    }
    return PermissionRequestResult.denied;
  }

  // Test hooks: allow tests to override check/request behavior.
  static Future<PermissionRequestResult> Function()? testCheckHandler;
  static Future<PermissionRequestResult> Function()? testRequestHandler;

  /// For tests: call this to set custom handlers.
  static void setTestHandlers({
    Future<PermissionRequestResult> Function()? checkHandler,
    Future<PermissionRequestResult> Function()? requestHandler,
  }) {
    testCheckHandler = checkHandler;
    testRequestHandler = requestHandler;
  }

  /// Clear test handlers.
  static void clearTestHandlers() {
    testCheckHandler = null;
    testRequestHandler = null;
  }

  // Use test handler when present
  // (Removed unused internal helpers to satisfy analyzer)

  /// Check current camera + gallery/storage permission state without prompting.
  static Future<PermissionRequestResult> checkCameraAndStorage() async {
    // Allow tests to override behavior
    if (testCheckHandler != null) return await testCheckHandler!();
    final cam = await Permission.camera.status;
    if (!cam.isGranted) {
      if (cam.isPermanentlyDenied) {
        return PermissionRequestResult.permanentlyDenied;
      }
      return PermissionRequestResult.denied;
    }

    PermissionStatus galleryStatus;
    try {
      galleryStatus = await Permission.photos.status;
    } catch (_) {
      galleryStatus = await Permission.storage.status;
    }

    if (galleryStatus.isGranted) {
      return PermissionRequestResult.granted;
    }
    if (galleryStatus.isPermanentlyDenied) {
      return PermissionRequestResult.permanentlyDenied;
    }
    return PermissionRequestResult.denied;
  }
}
