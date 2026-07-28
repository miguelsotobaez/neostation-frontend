
#include <wtypes.h>

#include <windows.h>
#include <functional>
#include <iostream>
#include <list>
#include <map>
#include <optional>
#include <GameInput.h>

struct GamepadData {
  std::string id;
  std::string name;
  int num_buttons;
  bool stop_thread;
  bool alive;
  int vendor_id;
  int product_id;
};

struct Event {
  int time;
  std::string type;
  std::string key;
  double value;
};

class Gamepads {
 private:
  std::list<GamepadData*> gamepads;

  GameInputCallbackToken* deviceCallbackToken;
  void read_gamepad(GamepadData* gamepad, IGameInputDevice* device);

  void on_gamepad_connected(IGameInputDevice* device);
  void on_gamepad_disconnected(IGameInputDevice* device);

 public:
  std::optional<std::function<void(GamepadData* gamepad, const Event& event)>>
      event_emitter;
  void init();
  void stop();
  std::list<GamepadData*> get_gamepads();
};

extern Gamepads gamepads;
