import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/agenda_link.dart';
import '../theme/brand.dart';
import 'common.dart';

/// Builds the camera view; calls [onCode] with the text of every QR code it
/// sees. Injectable so tests can run without a camera.
typedef QrCameraBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

/// Full-screen QR scanner for "Scan agenda QR". Pops with the agenda payload
/// of the first agenda QR it sees; other codes show "Not an agenda QR" and
/// scanning goes on.
class AgendaQrScanner extends StatefulWidget {
  const AgendaQrScanner({super.key, this.camera});

  /// Null for the real camera ([MobileScanner]).
  final QrCameraBuilder? camera;

  /// Opens the scanner; resolves to an agenda payload, or null when closed.
  static Future<String?> open(
    BuildContext context, {
    QrCameraBuilder? camera,
  }) => Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AgendaQrScanner(camera: camera),
    ),
  );

  @override
  State<AgendaQrScanner> createState() => _AgendaQrScannerState();
}

class _AgendaQrScannerState extends State<AgendaQrScanner> {
  MobileScannerController? _controller;
  bool _done = false;
  String? _lastRejected;
  final _sinceRejected = Stopwatch();

  @override
  void initState() {
    super.initState();
    if (widget.camera == null) {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onCode(String raw) {
    if (_done || !mounted) return;
    final payload = agendaPayloadFromQr(raw);
    if (payload != null) {
      _done = true;
      Navigator.of(context).pop(payload);
      return;
    }
    // The camera reports the same code many times a second: say it once
    // per code, and again only after a pause.
    if (raw == _lastRejected &&
        _sinceRejected.elapsed < const Duration(seconds: 4)) {
      return;
    }
    _lastRejected = raw;
    _sinceRejected
      ..reset()
      ..start();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Not an agenda QR')));
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        _onCode(v);
        if (_done) return;
      }
    }
  }

  Widget _camera(BuildContext context) {
    final custom = widget.camera;
    if (custom != null) return custom(context, _onCode);
    return MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
      errorBuilder: (context, error) => ScannerError(error: error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan agenda QR'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [if (controller != null) _TorchButton(controller: controller)],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _camera(context),
          _HideOnError(controller: controller, child: _overlay(context)),
        ],
      ),
    );
  }

  /// Viewfinder frame and hint, over the live camera.
  Widget _overlay(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusCard),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        left: 24,
        right: 24,
        bottom: 32,
        child: SafeArea(
          top: false,
          child: Text(
            'Point the camera at a QR code from "Share my agenda".',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Colors.white),
          ),
        ),
      ),
    ],
  );
}

/// Hides [child] while the camera reports an error, so the frame and hint
/// do not cover the error message.
class _HideOnError extends StatelessWidget {
  const _HideOnError({required this.controller, required this.child});
  final MobileScannerController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return child;
    return ValueListenableBuilder(
      valueListenable: c,
      builder: (context, state, child) =>
          state.error == null ? child! : const SizedBox.shrink(),
      child: child,
    );
  }
}

/// Torch toggle, shown only when the camera has a torch.
class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.controller});
  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, state, _) {
      if (!state.isRunning || state.torchState == TorchState.unavailable) {
        return const SizedBox.shrink();
      }
      final on = state.torchState == TorchState.on;
      return IconButton(
        tooltip: on ? 'Turn torch off' : 'Turn torch on',
        icon: Icon(on ? Icons.flash_on : Icons.flash_off),
        onPressed: () => controller.toggleTorch(),
      );
    },
  );
}

/// Camera failure: permission denied, no camera, or anything else.
class ScannerError extends StatelessWidget {
  const ScannerError({super.key, required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: EmptyState(
        icon: denied ? Icons.no_photography_outlined : Icons.videocam_off,
        title: denied
            ? 'Camera access is off'
            : unsupported
            ? 'No camera available'
            : "Couldn't start the camera",
        message: denied
            ? (kIsWeb
                  ? 'Allow camera access for this site in your browser settings, or use "Import agenda link" to paste the link instead.'
                  : 'Allow camera access in Settings to scan agenda QR codes, or use "Import agenda link" to paste the link instead.')
            : 'Use "Import agenda link" to paste the shared link instead.',
        action: denied && !kIsWeb
            ? SubtleButton(
                icon: Icons.settings_outlined,
                label: 'Open settings',
                onPressed: () async {
                  try {
                    await Geolocator.openAppSettings();
                  } catch (_) {
                    // No settings page on this platform.
                  }
                },
              )
            : null,
      ),
    );
  }
}
