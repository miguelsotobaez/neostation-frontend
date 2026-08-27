import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// Dialog allowing users to create a new collection or rename/edit an existing one.
class CreateEditCollectionDialog extends StatefulWidget {
  final CollectionModel? collection;
  final ValueChanged<({String name, String? description})> onSave;

  const CreateEditCollectionDialog({
    super.key,
    this.collection,
    required this.onSave,
  });

  static Future<void> show({
    required BuildContext context,
    CollectionModel? collection,
    required ValueChanged<({String name, String? description})> onSave,
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
  late final TextEditingController _descriptionController;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();
  int _focusedButtonIndex = 1; // 0 = Cancel, 1 = Save
  late final GamepadNavigation _gamepadNav;

  bool get _isEditing => widget.collection != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.collection?.name ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.collection?.description ?? '',
    );

    _gamepadNav = GamepadNavigation(
      onNavigateLeft: () {
        if (_focusedButtonIndex > 0) {
          SfxService().playNavSound();
          setState(() => _focusedButtonIndex = 0);
        }
      },
      onNavigateRight: () {
        if (_focusedButtonIndex < 1) {
          SfxService().playNavSound();
          setState(() => _focusedButtonIndex = 1);
        }
      },
      onNavigateUp: () {
        _nameFocus.requestFocus();
      },
      onNavigateDown: () {
        _descriptionFocus.requestFocus();
      },
      onSelectItem: _submit,
      onBack: () {
        SfxService().playBackSound();
        Navigator.of(context).pop();
      },
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
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    SfxService().playEnterSound();
    widget.onSave((
      name: name,
      description: _descriptionController.text.trim(),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

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
        constraints: BoxConstraints(maxWidth: 460.w),
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
                  color: primaryColor,
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
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: primaryColor, width: 2.r),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              SizedBox(height: 16.h),
              Text(
                AppLocale.collectionDescription.getString(context),
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              SizedBox(height: 6.h),
              TextField(
                controller: _descriptionController,
                focusNode: _descriptionFocus,
                style: TextStyle(fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'Optional description...',
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
                  _buildButton(
                    context: context,
                    label: 'Cancel',
                    isFocused: _focusedButtonIndex == 0,
                    isPrimary: false,
                    onTap: () {
                      SfxService().playBackSound();
                      Navigator.of(context).pop();
                    },
                  ),
                  SizedBox(width: 12.w),
                  _buildButton(
                    context: context,
                    label: 'Save',
                    isFocused: _focusedButtonIndex == 1,
                    isPrimary: true,
                    onTap: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required String label,
    required bool isFocused,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: isPrimary
                ? (isFocused
                      ? primaryColor
                      : primaryColor.withValues(alpha: 0.8))
                : (isFocused
                      ? theme.cardColor.withValues(alpha: 0.8)
                      : theme.cardColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: isFocused
                  ? Colors.white
                  : (isPrimary
                        ? primaryColor
                        : theme.dividerColor.withValues(alpha: 0.3)),
              width: isFocused ? 2.r : 1.r,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              color: isPrimary
                  ? Colors.white
                  : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}
