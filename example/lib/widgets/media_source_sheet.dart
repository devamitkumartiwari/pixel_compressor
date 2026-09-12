import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Bottom sheet letting the user choose between picking from the gallery
/// or capturing fresh with the camera. Shared by the image and video pages.
///
/// `image_picker`'s macOS backend has no camera capture support (it throws
/// unless a `cameraDelegate` is wired up), so on desktop this skips the
/// sheet and goes straight to the gallery/file picker.
Future<ImageSource?> showMediaSourceSheet(
  BuildContext context, {
  required String captureLabel,
}) {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return Future.value(ImageSource.gallery);
  }
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Add media', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Choose where to pick it from',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SourceOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: const Color(0xFF3B82F6),
                    onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SourceOption(
                    icon: Icons.camera_alt_rounded,
                    label: captureLabel,
                    color: const Color(0xFFEF4444),
                    onTap: () => Navigator.of(context).pop(ImageSource.camera),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
