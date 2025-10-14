//// `avmgls` - Atom VM LED Strip walk implemented in Gleam
//// Walking leds with random colour and speed. Tested with ESP32-C3 SoC.

import avmgls/ls.{type Colour, type LedSubject, StartArgs, Ws2812}
import avmgls/ls_server
import gleam/erlang/process
import gleam/io
import glydamic

// Gleam run start
pub fn main() {
  io.println("Hello from gleam run!")
}

// For AtomVM start
/// Start the application, callback for AtomVM init.
///  Calls a loop that spawns one process for each led to walk the strip.
///  Lasts for 60 seconds.
pub fn start() {
  io.println("Hello from avmgls!")
  let testfile1 = read_priv("subdir/test2.txt")
  io.println(testfile1)
  let strip_len = 60
  // DI Pin 8 for ESP32-C3
  let start_args =
    StartArgs(di_pin: 8, ci_pin: -1, strip_type: Ws2812, strip_len: strip_len)
  let assert Ok(led_subject) = ls_server.init(start_args)
  loop(led_subject, strip_len, 20)
  process.sleep(60_000)
}

fn loop(led_subject, strip_len: Int, n: Int) -> Nil {
  case n {
    0 -> Nil
    n -> {
      let rand = random()
      let randbits = <<rand:size(32)>>
      let #(duration, r, g, b) = case randbits {
        <<duration:int, r:int, g:int, b:int>> -> #(
          duration + 200,
          r / 4,
          g / 4,
          b / 4,
        )
        _ -> #(1000, 0, 10, 0)
      }
      glydamic.splunk(fn() {
        walking_led_up(led_subject, strip_len, 0, duration, ls.RGB(r, g, b))
      })
      process.sleep(3000)
      loop(led_subject, strip_len, n - 1)
    }
  }
}

// ---------------------------------------------
fn light_led(led_subject: LedSubject, index: Int, duration: Int, colour: Colour) {
  ls.set_led(led_subject, index, colour)
  process.sleep(duration)
  ls.clear_led(led_subject, index)
}

// fn walking_led(
//   led_subject: LedSubject,
//   index: Int,
//   duration: Int,
//   colour: Colour,
// ) -> Nil {
//   case index {
//     n if n > 0 -> {
//       light_led(led_subject, index, duration, colour)
//       walking_led(led_subject, n - 1, duration, colour)
//     }
//     _ -> Nil
//   }
// }

fn walking_led_up(
  led_subject: LedSubject,
  max: Int,
  index: Int,
  duration: Int,
  colour: Colour,
) {
  case index {
    n if n < max && n >= 0 -> {
      light_led(led_subject, index, duration, colour)
      walking_led_up(led_subject, max, n + 1, duration, colour)
    }
    _ -> Nil
  }
}

/// atomvm:random() returns a 32 bit integer.
@external(erlang, "atomvm", "random")
fn random() -> Int

@external(erlang, "avmgls_ffi", "read_priv")
fn read_priv(path: String) -> String
