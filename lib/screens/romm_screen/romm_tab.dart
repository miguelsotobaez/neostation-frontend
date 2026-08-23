import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/romm_provider.dart';
import 'romm_browse_screen.dart';
import 'romm_connect_content.dart';

/// Top-level RomM tab.
///
/// Hosts the whole RomM lifecycle so the library is reachable directly via
/// L1/R1 tab navigation instead of being buried inside Settings:
///  * disconnected → the connect / credentials form ([RommConnectContent]),
///    so a first-time user can connect without leaving the tab.
///  * connected → the [RommBrowseScreen] library browser, whose title bar
///    hosts the account affordances (save-sync toggle, disconnect) directly.
///
/// Each child owns its own gamepad navigation layer, so swapping between them
/// (here) pushes/pops the appropriate layer via their init/dispose lifecycle.
class RommTab extends StatelessWidget {
  const RommTab({super.key});

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<RommProvider>().isConnected;
    return connected ? const RommBrowseScreen() : const RommConnectContent();
  }
}
