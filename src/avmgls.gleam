//// `avmgls` - Atom VM LED Strip walk implemented in Gleam
//// Walking leds with random colour and speed. Tested with ESP32-C3 SoC.

import avmgls/ls.{type LedSubject, Lower, StartArgs, Upper, Ws2812}
import avmgls/ls_server
import gleam/erlang/process
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

const red = ls.RGB(0x40, 0x00, 0x00)

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

  process.send(led_subject, prepare_lower())
  process.send(led_subject, prepare_upper())
  process.send(
    led_subject,
    list.map([Upper, Lower], fn(part) { ls.LightLeds(part, 1) }),
  )
  rotations(led_subject, 0, 45, ls.Up)
  rotations(led_subject, 0, 45, ls.Down)
  process.sleep(40_000)
  process.send(
    led_subject,
    list.map([Upper, Lower], fn(part) { ls.LightLeds(part, 2) }),
  )
  rotations(led_subject, 0, 45, ls.Down)
  rotations(led_subject, 0, 45, ls.Up)
  process.sleep(40_000)
  process.send(led_subject, [ls.LightLeds(Upper, 3), ls.LightLeds(Lower, 0)])
  process.sleep(20_000)

  // clear all leds
  process.send(led_subject, [ls.LightLeds(Lower, 0), ls.LightLeds(Upper, 0)])
  process.sleep(1000)
}

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
  let l1 = [ls.Rotate(direction), ls.Duration(100)]
  l1 |> list.append(l1) |> list.append(l1) |> list.append(l1)
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
  let ls0 = ls.PrepareLedStrip([], Upper, strip_len, 0)
  let ls1 =
    ls.PrepareLedStrip(
      [#(0, red), #(4, pink), #(9, green)],
      Upper,
      strip_len,
      1,
    )
  let ls2 =
    ls.PrepareLedStrip(
      [#(0, green), #(4, red), #(9, pink)],
      Upper,
      strip_len,
      2,
    )
  let ls3 =
    ls.PrepareLedStrip(
      [#(0, pink), #(4, green), #(9, red)],
      Upper,
      strip_len,
      3,
    )
  [ls0, ls1, ls2, ls3]
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
