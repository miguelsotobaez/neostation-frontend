# 🎨 NeoStation Theme Guide

Welcome to the NeoStation theme system. This document will explain how to create new themes following established conventions.

> **Note:** This guide covers the app's **UI color themes** (`lib/themes/`). It is unrelated to **System Art packs** — the downloadable system card backgrounds and logos (formerly also called "themes"; their manifest and cache paths still use `theme.json` naming).

---

## 📋 Theme Structure

Each theme is defined in a `*_theme.dart` file within the `lib/themes/` folder.

```dart
// Example: my_theme_theme.dart
import 'package:flutter/material.dart';
import 'package:neostation/themes/corner_radii.dart';

// 1. Base color definition
const Color _primaryColor = Color(0xFFFF5722);     // Primary theme color
const Color _onPrimaryColor = Color(0xFFFFFFFF);   // Text on primary
const Color _secondaryColor = Color(0xFF4CAF50);   // Secondary color
const Color _surfaceColor = Color(0xFF1D232A);    // Surface background

// 2. ThemeData configuration
final ThemeData myThemeTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.dark(),

  cardColor: _backgroundColor,
  scaffoldBackgroundColor: _backgroundColor,

  textTheme: TextTheme(
    displayLarge: TextStyle(color: _onSurfaceColor, fontSize: 32),
    titleLarge: TextStyle(color: _onSurfaceColor, fontSize: 24),
    bodyLarge: TextStyle(color: _onSurfaceColor, fontSize: 16),
  ),
);

// 3. Class for custom colors
class MyThemeCustomColors {
  Color get batteryFull => _batteryFull;
  Color get batteryMedium => _batteryMedium;
  
  Color get errorColor => _errorColor;
  Color get successColor => _successColor;
}
```

---

## 🎨 Required Color Theme

### **Essential Colors**

| Property | Description | Example |
|----------|-------------|---------|
| `primary` | Main color for primary actions | Most important action |
| `onPrimary` | Text on primary components | Inverse of primary |
| `secondary` | Secondary color for highlighted elements | Complementary to primary |
| `surface` | Background for cards and main containers | Not the darkest background |
| `onSurface` | Text on surfaces | Inverse of surface |
| `error` | Color for errors/deletion | Red or similar |
| `onError` | Text on errors | Inverse of error |
| `outline` | Lines and borders | Soft gray |
| `shadow` | Shadows | Semi-transparent black |

### **Additional Colors (Recommended)**

| Property | Usage | Suggestions |
|----------|-------|-------------|
| `tertiary` | Accessory elements | Complementary to secondary |
| `cardColor` | Specific card background | Can be darker than surface |
| `scaffoldBackgroundColor` | General app background | Darker than surface in dark mode |

### **Specialized Colors**

```dart
// Colors for states and notifications
const Color _successColor = Color(0xFF00d390);   // Success (green)
const Color _errorColor = Color(0xFFff627d);     // Error (red/pink)
const Color _warningColor = Color(0xFFFcb700);   // Warning (yellow)
const Color _infoColor = Color(0xFF00bafe);      // Info (blue)

// Colors for battery indicator
const Color _batteryFull = Color(0xFF00d390);    // Full battery
const Color _batteryMedium = Color(0xFFFcb700);  // Medium battery
const Color _batteryLow = Color(0xFFff627d);     // Low battery
```

---

## 🎨 DaisyUI Color Theme Reference

We recommend reviewing **DaisyUI** as a reference for professional color themes:

🔗 [https://daisyui.com/docs/themes/](https://daisyui.com/docs/themes/)

### **Recommended Themes for Inspiration:**

1. **dracula** - Popular dark theme for developers
2. **nord** - Very balanced arctic theme
3. **solarized** - Classic, with good contrast and warm/cool colors
4. **catppuccin** - Modern pastel theme, very pleasant
5. **tokyo-night** - Optimized for developers

---

## ✅ Checklist for a Well-Built Theme

- [ ] **Adequate contrast** → Ensure text is readable on all backgrounds
- [ ] **Harmonious theme** → Primary, secondary, and tertiary colors should work together
- [ ] **Accessibility** → Complies with WCAG 2.1 standards for contrast
- [ ] **Consistency** → Follows the pattern established in other project themes
- [ ] **Distinctive primary color** → Primary should stand out without being aggressive

---

## 🔧 Integrating Your New Theme

Once you've created `my_theme_theme.dart`, you must:

### **1. Add to `lib/themes/app_themes.dart`**

```dart
import 'lib/my_theme_theme.dart' as my_theme;  // At the beginning of the file

class AppThemes {
  static ThemeData get myThemeTheme => my_theme.myThemeTheme;
  
  static dynamic get myThemeCustomColors => my_theme.MyThemeCustomColors();

  switch (themeName) {
    case 'my_theme':
      return myThemeTheme;
  }
}
```

### **2. Update `lib/providers/theme_provider.dart`**

In `availableThemes`:
```dart
static final Map<String, ThemeData> availableThemes = {
  'my_theme': AppThemes.myThemeThemes,
};
```

In `themeDisplayNames`:
```dart
static const Map<String, String> themeDisplayNames = {
  'my_theme': 'My Theme',
};
```

---

## 🎨 Design Tips

### **Dark Themes**

- **Surface**: Very dark gray, almost black (#1a1f26)
- **Primary**: Vibrant color but not overly saturated
- **OnSurface**: White or very light gray (#ecf9ff)
- Avoid pure neon colors on black backgrounds → strains eyes

### **Light Themes**

- **Surface**: White or very light gray (#f8fafb)
- **Primary**: Solid color, not aggressive
- **OnSurface**: Dark gray or almost black (#1c1917)
- Use subtle shadows for depth

---

## 📝 Complete Example: "Cyberpunk" Theme (Adapted)

```dart
// lib/themes/cyberpunk_theme.dart
import 'package:flutter/material.dart';
import 'package:neostation/themes/corner_radii.dart';

const Color _primaryColor = Color(0xFF00f3ff);      // Bright cyan
const Color _onPrimaryColor = Color(0xFF001a2b);    // Dark cyan for text
const Color _secondaryColor = Color(0xFFbc13fe);    // Electric violet

const Color _surfaceColor = Color(0xFF0d1117);      // Main background
const Color _onSurfaceColor = Color(0xFFC9D1D9);    // Main text

final ThemeData cyberpunkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.dark(
    primary: _primaryColor,
    onPrimary: _onPrimaryColor,
    secondary: _secondaryColor,
    onSecondary: Color(0xFFF5F7FA),
    surface: _surfaceColor,
    onSurface: _onSurfaceColor,
  ),

  cardColor: _backgroundColor,
  scaffoldBackgroundColor: _backgroundColor,

  textTheme: TextTheme(
    displayLarge: TextStyle(color: _onSurfaceColor, fontSize: 32),
    titleLarge: TextStyle(color: _onSurfaceColor, fontSize: 24),
    bodyLarge: TextStyle(color: _onSurfaceColor, fontSize: 16),
  ),
);

class CyberpunkCustomColors {
  Color get batteryFull => _primaryColor;
  Color get batteryMedium => _secondaryColor;
  
  Color get errorColor => _errorColor;
  Color get successColor => _successColor;
}
```

---

## 🚀 Conclusion

Creating a new theme for NeoStation is simple following this structure. Remember:

1. ✅ **Contrast is key** → Read text clearly on all backgrounds
2. ✅ **Color harmony** → Primary, secondary, and tertiary colors should work together
3. ✅ **Document your decisions** → Explain why you chose certain colors
4. ✅ **Test thoroughly** → Review in different modes and scenarios

Thanks for contributing to the NeoStation visual ecosystem! 🎨✨

---

*Last updated: 2025*