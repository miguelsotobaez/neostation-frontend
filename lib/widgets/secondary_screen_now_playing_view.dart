import 'dart:async';
import 'package:flutter/material.dart';
import '../models/secondary_display_state.dart';
import '../screens/secondary_screen/now_playing_helpers.dart';
import '../screens/secondary_screen/widgets/now_playing_panel.dart';

/// Full-screen Now Playing view shown on the PRIMARY display for a system
/// launched with "open on second screen" — the game itself runs on the
/// secondary display, so the primary one shows the same Now Playing content
/// that would normally appear on the secondary display, instead of sitting
/// idle on whatever screen was open when the game launched.
///
/// Reuses [NowPlayingPanel] driven by [SecondaryDisplayState.instance], which
/// the main engine already populates for every launched game regardless of
/// which display it ends up running on (see
/// `SecondaryAchievementsController.pushForLaunch`) — no new data plumbing
/// needed, just a second place to render the same state.
class SecondaryScreenNowPlayingView extends StatefulWidget {
  const SecondaryScreenNowPlayingView({super.key});

  @override
  State<SecondaryScreenNowPlayingView> createState() =>
      _SecondaryScreenNowPlayingViewState();
}

class _SecondaryScreenNowPlayingViewState
    extends State<SecondaryScreenNowPlayingView> {
  final Stopwatch _sessionWatch = Stopwatch()..start();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatSessionTime() {
    final total = _sessionWatch.elapsed.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m '
          '${s.toString().padLeft(2, '0')}s';
    }
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SecondaryDisplayStateData?>(
      valueListenable: SecondaryDisplayState.instance,
      builder: (context, value, _) {
        final scheme = value != null
            ? panelScheme(value)
            : Theme.of(context).colorScheme;
        return Material(
          color: scheme.surface,
          child: value == null
              ? const SizedBox.expand()
              : NowPlayingPanel(
                  // No relevant screenshot target on this display — the game
                  // is running on the other one.
                  value: value.copyWith(screenshotAccessEnabled: false),
                  sessionRunning: true,
                  sessionTime: _formatSessionTime(),
                  onRequestScreenshot: () {},
                ),
        );
      },
    );
  }
}
