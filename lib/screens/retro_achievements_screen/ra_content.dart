import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:provider/provider.dart';
import '../../providers/retro_achievements_provider.dart';
import '../../widgets/confirm_action_dialog.dart';
import '../../widgets/custom_notification.dart';
import '../../responsive.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import '../../services/game_service.dart' show GamepadNavigationManager;
import '../app_screen.dart' show AppNavigation;
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import '../../utils/login_form_selection.dart';
import 'ra_dashboard.dart';

class RAContent extends StatefulWidget {
  const RAContent({super.key});

  @override
  State<RAContent> createState() => _RAContentState();
}

class _RAContentState extends State<RAContent>
    with LoginFormSelection<RAContent> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _apiKeyFocus = FocusNode();
  final ScrollController _dashboardScrollController = ScrollController();

  /// Connected dashboard: whether the cursor is parked on the header's logout
  /// button. Nothing is selected at rest — Right parks on it, Left releases it,
  /// and Up/Down stay dedicated to scrolling the dashboard.
  bool _logoutSelected = false;

  /// Set while Right is scrolling the header back into view, so the scroll
  /// listener doesn't read that movement as the user leaving the button.
  bool _scrollingToLogout = false;

  /// Matches the ScreenScraper login's password field, which the RA card sits
  /// next to: an API key is as worth hiding as a password, and as easy to
  /// mistype without being able to check it.
  bool _obscureApiKey = true;
  GamepadNavigation? _gamepadNav;

  @override
  List<FocusNode?> get selectionSlots => [
    _usernameFocus,
    _apiKeyFocus,
    null,
    null,
  ];

  @override
  void initState() {
    super.initState();
    attachFocusSelectionListeners();
    _dashboardScrollController.addListener(_releaseLogoutOnScroll);
    _initControllerNavigation();
  }

  void _initControllerNavigation() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _handleNavigateUp,
      onNavigateDown: _handleNavigateDown,
      onNavigateLeft: _handleNavigateLeft,
      onNavigateRight: _handleNavigateRight,
      onSelectItem: _selectCurrent,
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
      allowRepeat: false,
      isTextFieldFocused: isAnyFieldFocused,
      onBack: exitTextEntry,
    );
    _gamepadNav!.initialize();
    GamepadNavigationManager.pushLayer(
      'ra_content',
      onActivate: () => _gamepadNav?.activate(),
      onDeactivate: () => _gamepadNav?.deactivate(),
    );
  }

  void _selectCurrent() {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (raProvider.isConnected) {
      if (_logoutSelected) _requestDisconnect();
      return;
    }
    if (focusSelectedField()) return;
    if (selectedSlot == 2) {
      _openRaControlPanel();
      return;
    }
    _connectToRA();
  }

  bool _setLogoutSelected(bool selected) {
    if (!mounted || _logoutSelected == selected) return false;
    setState(() => _logoutSelected = selected);
    return true;
  }

  /// Releases the logout parking when the dashboard scrolls off the top by any
  /// means, so a touch scroll can't leave the button armed behind the content.
  void _releaseLogoutOnScroll() {
    if (_scrollingToLogout) return;
    if (!_logoutSelected || !_dashboardScrollController.hasClients) return;
    final position = _dashboardScrollController.position;
    if (position.pixels > position.minScrollExtent + 1) {
      _setLogoutSelected(false);
    }
  }

  Future<void> _requestDisconnect() async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.disconnectRaConfirm.getString(context),
      body: AppLocale.disconnectRaConfirmBody.getString(context),
      confirmLabel: AppLocale.logout.getString(context),
      icon: Symbols.logout_rounded,
    );
    if (!confirmed || !mounted) return;
    context.read<RetroAchievementsProvider>().disconnect(clearSavedUser: true);
    if (!mounted) return;
    resetSelection();
    _setLogoutSelected(false);
    AppNotification.showNotification(
      context,
      AppLocale.disconnectedRA.getString(context),
      type: NotificationType.info,
    );
  }

  Future<void> _connectToRA() async {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (raProvider.isLoading) return;
    // Same up-front check (and message) as the ScreenScraper login: without it
    // an empty submit round-trips to the API and surfaces a raw connection
    // error instead of telling the user what is missing.
    if (_usernameController.text.trim().isEmpty ||
        _apiKeyController.text.trim().isEmpty) {
      AppNotification.showNotification(
        context,
        AppLocale.pleaseCompleteAllFields.getString(context),
        type: NotificationType.error,
      );
      return;
    }
    final apiKey = _apiKeyController.text.trim();
    final success = await raProvider.connect(
      _usernameController.text,
      apiKey: apiKey,
    );
    if (!mounted) return;
    if (success) {
      AppNotification.showNotification(
        context,
        AppLocale.successConnectedRA.getString(context),
        type: NotificationType.success,
      );
    } else if (raProvider.error != null) {
      AppNotification.showNotification(
        context,
        raProvider.error!,
        type: NotificationType.error,
      );
    }
  }

  Future<void> _openRaControlPanel() async {
    final url = Uri.parse(
      'https://retroachievements.org/settings?tab=applications',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('ra_content');
    _gamepadNav?.dispose();
    detachFocusSelectionListeners();
    _usernameController.dispose();
    _apiKeyController.dispose();
    _usernameFocus.dispose();
    _apiKeyFocus.dispose();
    _dashboardScrollController.dispose();
    super.dispose();
  }

  /// Returns whether the selection/scroll actually moved, so the gamepad
  /// handler can suppress the nav sound at a boundary.
  bool _handleNavigateUp() {
    if (!context.read<RetroAchievementsProvider>().isConnected) {
      return moveSelection(-1);
    }
    return _scrollDashboard(-160.r);
  }

  bool _handleNavigateDown() {
    if (!context.read<RetroAchievementsProvider>().isConnected) {
      return moveSelection(1);
    }
    return _scrollDashboard(160.r);
  }

  /// Right parks the cursor on the header's logout button.
  ///
  /// The header scrolls with the content, so anything below the top has to come
  /// back into view first — parking on a button that is off screen would leave
  /// the highlight invisible and A destructive-looking out of nowhere.
  bool _handleNavigateRight() {
    if (!context.read<RetroAchievementsProvider>().isConnected) return false;
    if (_logoutSelected) return false;
    _scrollHeaderIntoView();
    return _setLogoutSelected(true);
  }

  bool _handleNavigateLeft() {
    if (!context.read<RetroAchievementsProvider>().isConnected) return false;
    return _setLogoutSelected(false);
  }

  void _scrollHeaderIntoView() {
    if (!_dashboardScrollController.hasClients) return;
    final position = _dashboardScrollController.position;
    if (position.pixels <= position.minScrollExtent + 1) return;
    _scrollingToLogout = true;
    _dashboardScrollController
        .animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _scrollingToLogout = false);
  }

  bool _scrollDashboard(double delta) {
    if (!_dashboardScrollController.hasClients) return false;
    final position = _dashboardScrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return false;
    _dashboardScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetroAchievementsProvider>(
      builder: (context, raProvider, child) {
        return Responsive(
          handheldXS: _buildLandscapeLayout(context, raProvider),
          handheldSmall: _buildLandscapeLayout(context, raProvider),
          handheldMedium: _buildLandscapeLayout(context, raProvider),
          handheldLarge: _buildLandscapeLayout(context, raProvider),
          handheldXL: _buildLandscapeLayout(context, raProvider),
        );
      },
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 64.r), // Space for header (32.r + margin)
          // Contenido principal
          if (!raProvider.isConnected) ...[
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.r),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: 260.r),
                        child: _buildLandscapeConnectionForm(
                          context,
                          raProvider,
                        ),
                      ),
                      SizedBox(width: 16.r),
                      SizedBox(width: 300.r, child: _buildInfoBox(context)),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: RepaintBoundary(
                child: RADashboardHub(
                  scrollController: _dashboardScrollController,
                  logoutSelected: _logoutSelected,
                  onDisconnectRequested: _requestDisconnect,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldHighlight({
    required int slot,
    required ThemeData theme,
    required Widget child,
  }) {
    if (!isSelected(slot)) return child;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            blurRadius: 6.r,
            spreadRadius: 1.r,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildLandscapeConnectionForm(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header principal con logo y título
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocale.raLogin.getString(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 14.r,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 12.r),

          // Username field
          Container(
            constraints: BoxConstraints(maxWidth: 220.r),
            child: _buildFieldHighlight(
              slot: 0,
              theme: theme,
              child: SizedBox(
                height: 32.r,
                child: TextFormField(
                  controller: _usernameController,
                  focusNode: _usernameFocus,
                  decoration: InputDecoration(
                    labelText: AppLocale.username.getString(context),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 10.r,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 10.r,
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: AppLocale.enterUsername.getString(context),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10.r,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.05,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: isSelected(0)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.1),
                        width: isSelected(0) ? 2.r : 1.r,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.r,
                      ),
                    ),
                  ),
                  enabled: !raProvider.isLoading,
                  style: TextStyle(fontSize: 11.r),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _apiKeyFocus.requestFocus(),
                ),
              ),
            ),
          ),
          SizedBox(height: 6.r),

          // API key field
          Container(
            constraints: BoxConstraints(maxWidth: 220.r),
            child: _buildFieldHighlight(
              slot: 1,
              theme: theme,
              child: SizedBox(
                height: 32.r,
                child: TextFormField(
                  controller: _apiKeyController,
                  focusNode: _apiKeyFocus,
                  obscureText: _obscureApiKey,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: AppLocale.raApiKey.getString(context),
                    suffixStyle: TextStyle(
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      fontSize: 12.r,
                    ),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 10.r,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 10.r,
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: AppLocale.raEnterApiKey.getString(context),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10.r,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.05,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: isSelected(1)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.1),
                        width: isSelected(1) ? 2.r : 1.r,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.r,
                      ),
                    ),
                    suffixIcon: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        size: 18.r,
                        _obscureApiKey
                            ? Symbols.visibility_rounded
                            : Symbols.visibility_off_rounded,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureApiKey = !_obscureApiKey;
                        });
                      },
                    ),
                  ),
                  enabled: !raProvider.isLoading,
                  style: TextStyle(fontSize: 11.r),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _connectToRA(),
                ),
              ),
            ),
          ),
          SizedBox(height: 6.r),

          // Direct users to the page where RetroAchievements exposes their
          // personal Web API key, without asking the app to handle passwords.
          Container(
            constraints: BoxConstraints(maxWidth: 320.r),
            decoration: isSelected(2)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8.r),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.35,
                        ),
                        blurRadius: 8.r,
                        spreadRadius: 1.r,
                      ),
                    ],
                  )
                : null,
            child: OutlinedButton.icon(
              onPressed: _openRaControlPanel,
              icon: Icon(Symbols.key_rounded, size: 14.r),
              label: Text(
                AppLocale.raGetApiKey.getString(context),
                style: TextStyle(fontSize: 11.r, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(double.infinity, 32.r),
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
            ),
          ),
          SizedBox(height: 4.r),
          Text(
            AppLocale.raApiKeyHelp.getString(context),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              fontSize: 8.r,
            ),
          ),
          SizedBox(height: 6.r),

          // Connect button
          Container(
            constraints: BoxConstraints(maxWidth: 320.r),
            decoration: isSelected(submitSlot)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8.r),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        blurRadius: 8.r,
                        spreadRadius: 2.r,
                      ),
                    ],
                  )
                : null,
            child: SizedBox(
              width: double.infinity,
              height: 32.r,
              child: ElevatedButton(
                onPressed: raProvider.isLoading ? null : _connectToRA,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  elevation: 0,
                  padding: EdgeInsets.zero,
                ),
                child: raProvider.isLoading
                    ? SizedBox(
                        width: 16.r,
                        height: 16.r,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Text(
                        AppLocale.login.getString(context),
                        style: TextStyle(
                          fontSize: 14.r,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Symbols.emoji_events_rounded,
                color: theme.colorScheme.primary,
                size: 24.r,
              ),
              SizedBox(width: 12.r),
              Expanded(
                child: Text(
                  AppLocale.raWhatIs.getString(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 14.r,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.r),
          Text(
            AppLocale.raDescription.getString(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
              fontSize: 8.r,
            ),
            softWrap: true,
          ),
          SizedBox(height: 6.r),
          _buildInfoItem(
            context,
            Symbols.star_outline_rounded,
            AppLocale.raEarnPoints.getString(context),
          ),
          _buildInfoItem(
            context,
            Symbols.public_rounded,
            AppLocale.raGlobalLeaderboards.getString(context),
          ),
          _buildInfoItem(
            context,
            Symbols.history_rounded,
            AppLocale.raGameplayHistory.getString(context),
          ),
          SizedBox(height: 6.r),
          RichText(
            softWrap: true,
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 8.r,
              ),
              children: [
                TextSpan(text: AppLocale.raCreateAccountAt.getString(context)),
                TextSpan(
                  text: 'retroachievements.org',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                      final url = Uri.parse('https://retroachievements.org');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                ),
                TextSpan(text: AppLocale.raToStartEarning.getString(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8.r),
      child: Row(
        children: [
          Icon(
            icon,
            size: 12.r,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          SizedBox(width: 8.r),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 8.r,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
