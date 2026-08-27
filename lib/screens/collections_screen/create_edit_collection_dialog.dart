import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

enum _DialogFocusRegion { nameField, buttons }

/// Dialog allowing users to create a new collection or rename/edit an existing one.
class CreateEditCollectionDialog extends StatefulWidget {
  final CollectionModel? collection;
  final ValueChanged<String> onSave;

  const CreateEditCollectionDialog({
    super.key,
    this.collection,
    required this.onSave,
  });

  static Future<void> show({
    required BuildContext context,
    CollectionModel? collection,
    required ValueChanged<String> onSave,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          CreateEditCollectionDialog(collection: collection, onSave: onSave),
    );
  }

  @override
  State<CreateEditCollectionDialog> createState() =>
      _CreateEditCollectionDialogState();
}

class _CreateEditCollectionDialogState
    extends State<CreateEditCollectionDialog> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocus = FocusNode();

  _DialogFocusRegion _focusRegion = _DialogFocusRegion.nameField;
  int _focusedButtonIndex = 1; // 0 = Cancel, 1 = Save
  late final GamepadNavigation _gamepadNav;

  bool get _isEditing => widget.collection != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.collection?.name ?? '',
    );

    _nameFocus.addListener(_onNameFocusChanged);

    _nameFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _handleBack();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _setupGamepad();
  }

  void _onNameFocusChanged() {
    if (_nameFocus.hasFocus && _focusRegion != _DialogFocusRegion.nameField) {
      setState(() => _focusRegion = _DialogFocusRegion.nameField);
    }
  }

  void _handleBack() {
    SfxService().playBackSound();
    Navigator.of(context).pop();
  }

  void _setupGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () {
        if (_focusRegion == _DialogFocusRegion.buttons) {
          _nameFocus.requestFocus();
          setState(() => _focusRegion = _DialogFocusRegion.nameField);
          SfxService().playNavSound();
        }
      },
      onNavigateDown: () {
        if (_focusRegion == _DialogFocusRegion.nameField) {
          _nameFocus.unfocus();
          setState(() => _focusRegion = _DialogFocusRegion.buttons);
          SfxService().playNavSound();
        }
      },
      onNavigateLeft: () {
        if (_focusRegion == _DialogFocusRegion.buttons &&
            _focusedButtonIndex > 0) {
          setState(() => _focusedButtonIndex = 0);
          SfxService().playNavSound();
        }
      },
      onNavigateRight: () {
        if (_focusRegion == _DialogFocusRegion.buttons &&
            _focusedButtonIndex < 1) {
          setState(() => _focusedButtonIndex = 1);
          SfxService().playNavSound();
        }
      },
      onSelectItem: () {
        if (_focusRegion == _DialogFocusRegion.buttons &&
            _focusedButtonIndex == 0) {
          _handleBack();
        } else {
          _submit();
        }
      },
      onBack: _handleBack,
    );
    _gamepadNav.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GamepadNavigationManager.pushLayer(
        'create_edit_collection_dialog',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
        modal: true,
      );
    });
  }

  @override
  void dispose() {
    _gamepadNav.dispose();
    GamepadNavigationManager.popLayer('create_edit_collection_dialog');
    _nameFocus.removeListener(_onNameFocusChanged);
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _nameFocus.requestFocus();
      setState(() => _focusRegion = _DialogFocusRegion.nameField);
      return;
    }

    SfxService().playEnterSound();
    widget.onSave(name);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final isNameFocused = _focusRegion == _DialogFocusRegion.nameField;
    final isButtonsFocused = _focusRegion == _DialogFocusRegion.buttons;

    return Dialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.2),
          width: 1.r,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440.w),
        child: Padding(
          padding: EdgeInsets.all(24.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _isEditing
                        ? Symbols.edit_rounded
                        : Symbols.add_circle_rounded,
                    color: primaryColor,
                    size: 24.r,
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    _isEditing
                        ? AppLocale.editCollection.getString(context)
                        : AppLocale.createCollection.getString(context),
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Text(
                AppLocale.collectionName.getString(context),
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: isNameFocused
                      ? primaryColor
                      : theme.textTheme.bodyMedium?.color,
                ),
              ),
              SizedBox(height: 6.h),
              TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                autofocus: true,
                style: TextStyle(fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: AppLocale.collectionNameHint.getString(context),
                  hintStyle: TextStyle(fontSize: 13.sp, color: theme.hintColor),
                  filled: true,
                  fillColor: theme.cardColor.withValues(alpha: 0.5),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 12.h,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(
                      color: isNameFocused
                          ? primaryColor
                          : theme.dividerColor.withValues(alpha: 0.2),
                      width: isNameFocused ? 2.r : 1.r,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: primaryColor, width: 2.r),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              SizedBox(height: 24.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _handleBack,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 18.w,
                        vertical: 12.h,
                      ),
                      side: BorderSide(
                        color: isButtonsFocused && _focusedButtonIndex == 0
                            ? primaryColor
                            : theme.dividerColor.withValues(alpha: 0.3),
                        width: isButtonsFocused && _focusedButtonIndex == 0
                            ? 2.r
                            : 1.r,
                      ),
                      backgroundColor:
                          isButtonsFocused && _focusedButtonIndex == 0
                          ? primaryColor.withValues(alpha: 0.1)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    child: Text(
                      'Cancel [B]',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: isButtonsFocused && _focusedButtonIndex == 0
                            ? primaryColor
                            : theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: EdgeInsets.symmetric(
                        horizontal: 22.w,
                        vertical: 12.h,
                      ),
                      side: isButtonsFocused && _focusedButtonIndex == 1
                          ? BorderSide(color: Colors.white, width: 2.r)
                          : BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    child: Text(
                      _isEditing ? 'Save [A]' : 'Create [A]',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                      ),
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
}
