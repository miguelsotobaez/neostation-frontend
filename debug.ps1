# Kill orphan processes from VS Code debug sessions
Get-Process -Name dart -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name neostation -ErrorAction SilentlyContinue | Stop-Process -Force

# Remove only the symlink folder (keeps other cached files for faster rebuild)
Remove-Item -LiteralPath "windows\flutter\ephemeral\.plugin_symlinks" -Recurse -Force -ErrorAction SilentlyContinue

# Run flutter
flutter pub get
flutter run -d windows
