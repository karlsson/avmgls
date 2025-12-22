//// `avmgls` - Atom VM LED Strip walk implemented in Gleam
//// Walking leds with random colour and speed. Tested with ESP32-C3 SoC.

import avmgls/ls.{type Message, Lower, Message, StartArgs, Upper, Ws2812}
import avmgls/ls_server
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result

// import glydamic

// Gleam run start
pub fn main() {
  io.println("Hello from gleam run!")
}

const pink = ls.RGB(0x20, 0x00, 0x20)

const lightpink = ls.RGB(0x05, 0x00, 0x05)

const green = ls.RGB(0x00, 0x40, 0x00)

// const red = ls.RGB(0x40, 0x00, 0x00)

// For AtomVM start
/// Start the application, callback for AtomVM init.
///  Calls a loop that spawns one process for each led to walk the strip.
///  Lasts for 60 seconds.
pub fn start() {
  // Maybe one should spawn a watchdog feeding process instead.
  stop_watchdog()
  io.println("Hello from avmgls!")
  let testfile1 = read_priv("subdir/test2.txt")
  io.println(testfile1)
  let ls_name = process.new_name("led_strip_server")
  let led_subject: Subject(Message) = process.named_subject(ls_name)

  // On-board RGB LED:
  // DI Pin 8 for ESP32-C3-DevKit{C-02, M-1}
  // DI Pin 10 for ESP32-C3-Zero: https://www.waveshare.com/wiki/ESP32-C3-Zero
  let start_args = StartArgs(di_pin: 10, ci_pin: -1, strip_type: Ws2812)

  let child_spec =
    supervision.worker(fn() { ls_server.init(start_args, ls_name) })
    |> supervision.restart(supervision.Permanent)

  let _ =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(child_spec)
    |> supervisor.start()

  process.call_forever(led_subject, Message(_, prepare_lower()))
  process.call_forever(led_subject, Message(_, prepare_upper()))
  process.call_forever(led_subject, Message(_, [ls.LightLeds(Lower, 1)]))
  process.spawn(fn() { move_upper(led_subject, 1) })
  rotations(led_subject, 0, 45, ls.Up)
  rotations(led_subject, 0, 45, ls.Down)
  process.call_forever(led_subject, Message(_, [ls.LightLeds(Lower, 2)]))
  rotations(led_subject, 0, 45, ls.Down)
  rotations(led_subject, 0, 45, ls.Up)
  process.call_forever(led_subject, Message(_, [ls.LightLeds(Lower, 0)]))
  process.sleep(5000)

  // clear all leds
  process.call_forever(
    led_subject,
    Message(_, [ls.LightLeds(Lower, 0), ls.LightLeds(Upper, 0)]),
  )
  process.sleep(1000)
}

fn rotations(led_subject, n, max, direction) {
  case n < max {
    True -> {
      process.call_forever(led_subject, Message(_, rotate(direction)))
      rotations(led_subject, n + 1, max, direction)
    }
    False -> Nil
  }
}

fn rotate(direction) {
  let l1 = [ls.Rotate(direction), ls.Duration(100)]
  l1 |> list.append(l1) |> list.append(l1) |> list.append(l1)
}

fn move_upper(led_subject, n: Int) -> Nil {
  case n < 6 {
    True -> {
      process.call_forever(led_subject, Message(_, [ls.LightLeds(Upper, n)]))
      process.sleep(2000)
      move_upper(led_subject, n + 1)
    }
    False -> move_upper(led_subject, 1)
  }
}

fn prepare_lower() -> List(ls.LedCommand) {
  let strip_len = 50
  let f1 = fn(i, offset) {
    result.unwrap(int.remainder({ i * 5 } + offset, strip_len), 0)
  }
  // row 0 will clear all leds
  let ls0 = ls.PrepareLedStrip([], Lower, strip_len, 0)
  let ls1 =
    list.range(0, 9)
    |> list.map(fn(i) {
      [#(f1(i, 0), lightpink), #(f1(i, 1), pink), #(f1(i, 2), lightpink)]
    })
    |> list.flatten()
    |> ls.PrepareLedStrip(Lower, strip_len, 1)
  let ls2 =
    list.range(0, 9)
    |> list.map(fn(i) { [#(f1(i, 0), pink), #(f1(i, 1), green)] })
    |> list.flatten()
    |> ls.PrepareLedStrip(Lower, strip_len, 2)

  [ls0, ls1, ls2]
}

fn prepare_upper() -> List(ls.LedCommand) {
  let strip_len = 10
  // Index 0 clears all leds
  let ls0 = ls.PrepareLedStrip([], Upper, strip_len, 0)

  // Pinky leds moving into center
  let ls1 = ls.PrepareLedStrip([#(0, pink), #(9, pink)], Upper, strip_len, 1)
  let ls2 = ls.PrepareLedStrip([#(1, pink), #(8, pink)], Upper, strip_len, 2)
  let ls3 = ls.PrepareLedStrip([#(2, pink), #(7, pink)], Upper, strip_len, 3)
  let ls4 = ls.PrepareLedStrip([#(3, pink), #(6, pink)], Upper, strip_len, 4)
  let ls5 = ls.PrepareLedStrip([#(4, green), #(5, green)], Upper, strip_len, 5)
  [ls0, ls1, ls2, ls3, ls4, ls5]
}

@external(erlang, "avmgls_ffi", "read_priv")
fn read_priv(path: String) -> String

type WatchDogReturn

// todo - spawn_link a watchdog feeding process
@external(erlang, "esp", "task_wdt_deinit")
fn stop_watchdog() -> WatchDogReturn
// atomvm:random() returns a 32 bit integer.
// @external(erlang, "atomvm", "random")
// fn random() -> Int
