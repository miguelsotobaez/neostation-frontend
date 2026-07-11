#include "gamepads_windows_plugin.h"

#include <dbt.h>
#include <hidclass.h>
#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <iomanip>
#include <memory>
#include <sstream>

namespace gamepads_windows {

namespace {
// Custom message posted from reader threads to drain the event queue on the
// platform thread.
constexpr UINT kDrainGamepadEventsMessage = WM_USER + 0x47;
constexpr wchar_t kMessageWindowClassName[] = L"GamepadsWindowsMessageWindow";
}  // namespace

// Formats a 16-bit vendor/product id as a 4-digit uppercase hex string
// (e.g. 0x045E -> "045E"). The Dart side (GamepadDeviceInfo) types vendorId /
// productId as String?, so we emit strings here rather than raw ints.
static std::string to_hex_id(int id) {
  std::ostringstream oss;
  oss << std::uppercase << std::hex << std::setw(4) << std::setfill('0')
      << (id & 0xFFFF);
  return oss.str();
}

void GamepadsWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "xyz.luan/gamepads",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<GamepadsWindowsPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

GamepadsWindowsPlugin::GamepadsWindowsPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar(registrar) {
  create_message_window();
  gamepads.event_emitter = [&](GamepadData* gamepad, const Event& event) {
    this->emit_gamepad_event(gamepad, event);
  };
  gamepads.init();
}

GamepadsWindowsPlugin::~GamepadsWindowsPlugin() {
  gamepads.stop();
  if (message_window_ != nullptr) {
    DestroyWindow(message_window_);
    message_window_ = nullptr;
  }
  UnregisterClassW(kMessageWindowClassName, GetModuleHandle(nullptr));
}

LRESULT CALLBACK GamepadsWindowsPlugin::MessageWindowProc(HWND hwnd,
                                                          UINT message,
                                                          WPARAM wparam,
                                                          LPARAM lparam) {
  if (message == kDrainGamepadEventsMessage) {
    auto* self = reinterpret_cast<GamepadsWindowsPlugin*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (self != nullptr) {
      self->drain_event_queue();
    }
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void GamepadsWindowsPlugin::create_message_window() {
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = GamepadsWindowsPlugin::MessageWindowProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kMessageWindowClassName;
  // Ignore a "class already exists" failure from a previous instance (e.g.
  // after a hot restart); CreateWindowExW below will still succeed.
  RegisterClassExW(&wc);

  message_window_ = CreateWindowExW(0, kMessageWindowClassName, L"", 0, 0, 0, 0,
                                    0, HWND_MESSAGE, nullptr,
                                    GetModuleHandle(nullptr), nullptr);
  if (message_window_ != nullptr) {
    SetWindowLongPtr(message_window_, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(this));
  }
}

void GamepadsWindowsPlugin::drain_event_queue() {
  std::deque<QueuedGamepadEvent> pending;
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    pending.swap(event_queue_);
  }

  auto _channel = this->channel.get();
  if (!_channel) return;

  for (const auto& queued : pending) {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("gamepadId")] =
        flutter::EncodableValue(queued.gamepad_id);
    map[flutter::EncodableValue("time")] =
        flutter::EncodableValue(queued.event.time);
    map[flutter::EncodableValue("type")] =
        flutter::EncodableValue(queued.event.type);
    map[flutter::EncodableValue("key")] =
        flutter::EncodableValue(queued.event.key);
    map[flutter::EncodableValue("value")] =
        flutter::EncodableValue(queued.event.value);
    map[flutter::EncodableValue("vendorId")] =
        flutter::EncodableValue(queued.vendor_id);
    map[flutter::EncodableValue("productId")] =
        flutter::EncodableValue(queued.product_id);
    _channel->InvokeMethod("onGamepadEvent",
                           std::make_unique<flutter::EncodableValue>(
                               flutter::EncodableValue(map)));
  }
}

void GamepadsWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("listGamepads") == 0) {
    flutter::EncodableList list;
    for (auto gamepad : gamepads.get_gamepads()) {
      if (!gamepad) continue;

      flutter::EncodableMap map;
      map[flutter::EncodableValue("id")] = flutter::EncodableValue(gamepad->id);
      map[flutter::EncodableValue("name")] =
          flutter::EncodableValue(gamepad->name);

      // Extended device metadata consumed by the Dart GamepadDeviceInfo /
      // gamepad_translator. GameInput exposes VID/PID and a button count but
      // no bus/connection type, so connectionType is left unknown; the Windows
      // input path maps GameInput's standardized named keys directly and does
      // not rely on connection type.
      flutter::EncodableMap system_info;
      system_info[flutter::EncodableValue("connectionType")] =
          flutter::EncodableValue("unknown");
      system_info[flutter::EncodableValue("driver")] =
          flutter::EncodableValue("gameinput");
      system_info[flutter::EncodableValue("vendorId")] =
          flutter::EncodableValue(to_hex_id(gamepad->vendor_id));
      system_info[flutter::EncodableValue("productId")] =
          flutter::EncodableValue(to_hex_id(gamepad->product_id));
      system_info[flutter::EncodableValue("buttonCount")] =
          flutter::EncodableValue(gamepad->num_buttons);

      map[flutter::EncodableValue("systemInfo")] =
          flutter::EncodableValue(system_info);

      list.push_back(flutter::EncodableValue(map));
    }
    result->Success(flutter::EncodableValue(list));
  } else {
    result->NotImplemented();
  }
}

void GamepadsWindowsPlugin::emit_gamepad_event(GamepadData* gamepad,
                                               const Event& event) {
  // This runs on a background reader thread. Platform-channel calls must happen
  // on the platform thread, so buffer the event and signal the message window
  // (owned by the platform thread) to drain the queue.
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    event_queue_.push_back(
        {gamepad->id, gamepad->vendor_id, gamepad->product_id, event});
  }
  if (message_window_ != nullptr) {
    PostMessage(message_window_, kDrainGamepadEventsMessage, 0, 0);
  }
}
}  // namespace gamepads_windows
