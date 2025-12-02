import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list

/// Currently only Ws2812 implemented.
pub type StripType {
  Ws2812
  Sk9822
  Ap102
}

pub type StartArgs {
  StartArgs(di_pin: Int, ci_pin: Int, strip_type: StripType, strip_len: Int)
}

pub type Colour {
  RGB(red: Int, green: Int, blue: Int)
}

/// Index start at 0 to strip length-1
pub type LedSetting =
  #(Int, Colour)

pub type Direction {
  Up
  Down
}

pub type LedCommand {
  /// Prepare a list of different colours in indexed LEDs.
  /// Once prepared, store in a row.
  /// You can set rows 1 to ..
  PrepareLedStrip(led_settings: List(LedSetting), row: Int)
  /// Pull in a row and store in the working (row 0) area.
  /// Light the LED strip.
  LightLeds(row: Int)
  /// Rotate the LEDs in the working row upto index.
  Rotate(upto: Int, direction: Direction)
  /// Wait ms milliseconds until next command.
  Duration(ms: Int)
}

pub type LedSubject =
  Subject(List(LedCommand))

pub fn increase(colour: Colour) -> Colour {
  colmap(colour, fn(rgb: Int) { int.min(255, rgb * 2) })
}

pub fn decrease(colour: Colour) -> Colour {
  colmap(colour, fn(rgb) { rgb / 2 })
}

fn colmap(colour: Colour, f: fn(Int) -> Int) -> Colour {
  let RGB(r, g, b) = colour
  let assert [r, g, b] = list.map([r, g, b], f)
  RGB(r, g, b)
}
