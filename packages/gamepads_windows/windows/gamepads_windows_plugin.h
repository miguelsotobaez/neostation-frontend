#ifndef FLUTTER_PLUGIN_GAMEPADS_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_GAMEPADS_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <deque>
#include <memory>
#include <mutex>
#include <string>

#include "gamepad.h"

namespace gamepads_windows {

// A gamepad event captured on a background reader thread, buffered until it can
// be forwarded to Flutter on the platform thread. We copy the identifying
// fields (rather than hold the GamepadData*) because the source device may be
// disconnected and freed before the platform thread drains the queue.
struct QueuedGamepadEvent {
  std::string gamepad_id;
  int vendor_id;
  int product_id;
  Event event;
};

class GamepadsWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  GamepadsWindowsPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~GamepadsWindowsPlugin();

  // Disallow copy and assign.
  GamepadsWindowsPlugin(const GamepadsWindowsPlugin&) = delete;
  GamepadsWindowsPlugin& operator=(const GamepadsWindowsPlugin&) = delete;

 private:
  flutter::PluginRegistrarWindows* registrar;
  static inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      channel{};

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Called on a background reader thread: buffers the event and signals the
  // platform thread to forward it. Platform-channel calls must not happen here.
  void emit_gamepad_event(GamepadData* gamepad, const Event& event);

  // Creates the hidden message-only window used to hop queued events onto the
  // platform thread.
  void create_message_window();

  // Runs on the platform thread (from the message-window proc): forwards all
  // buffered events to Flutter over the method channel.
  void drain_event_queue();

  static LRESULT CALLBACK MessageWindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam);

  // Hidden HWND_MESSAGE window owned by the platform thread.
  HWND message_window_ = nullptr;

  std::mutex queue_mutex_;
  std::deque<QueuedGamepadEvent> event_queue_;
};

}  // namespace gamepads_windows

#endif  // FLUTTER_PLUGIN_GAMEPADS_WINDOWS_PLUGIN_H_
