//// `avmgls` - Atom VM LED Strip walk implemented in Gleam
//// Walking leds with random colour and speed. Tested with ESP32-C3 SoC.

import avmgls/ls.{type LedSubject, StartArgs, Ws2812}
import avmgls/ls_server
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

// import glydamic

// Gleam run start
pub fn main() {
  io.println("Hello from gleam run!")
}

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
  let led_subject: LedSubject = process.named_subject(ls_name)

  let strip_len = 60
  // On-board RGB LED:
  // DI Pin 8 for ESP32-C3-DevKit{C-02, M-1}
  // DI Pin 10 for ESP32-C3-Zero: https://www.waveshare.com/wiki/ESP32-C3-Zero
  let start_args =
    StartArgs(di_pin: 8, ci_pin: -1, strip_type: Ws2812, strip_len: strip_len)

  let child_spec =
    supervision.worker(fn() { ls_server.init(start_args, ls_name) })
    |> supervision.restart(supervision.Permanent)

  let _ =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(child_spec)
    |> supervisor.start()

  let cs = [
    // first row will clear all leds
    ls.PrepareLedStrip([], 1),
    ..[
      list.range(0, 11)
        |> list.map(fn(i) { #(i * 5, pink) })
        |> ls.PrepareLedStrip(2),
      ls.LightLeds(2),
      ls.Duration(200),
    ]
  ]
  process.send(led_subject, cs)
  //  process.send(led_subject, [ls.LightLeds(2), ls.Duration(200)])

  rotations(led_subject, 0, 45, ls.Up)
  rotations(led_subject, 0, 45, ls.Down)
  process.sleep(100_000)
  // clear all leds
  process.send(led_subject, [ls.LightLeds(1)])
  process.sleep(1000)
}

const pink = ls.RGB(0x20, 0x00, 0x20)

fn rotations(led_subject, n, max, direction) {
  case n < max {
    True -> {
      process.send(led_subject, rotate(direction))
      rotations(led_subject, n + 1, max, direction)
    }
    False -> Nil
  }
}

fn rotate(direction) {
  let l1 = [ls.Rotate(50, direction), ls.Duration(100)]
  l1 |> list.append(l1) |> list.append(l1) |> list.append(l1)
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
