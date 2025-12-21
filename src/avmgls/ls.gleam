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
  StartArgs(di_pin: Int, ci_pin: Int, strip_type: StripType)
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

pub type Part {
  Upper
  Lower
}

pub type LedCommand {
  /// Prepare a list of different colours in indexed LEDs.
  /// Once prepared, store in a row.
  /// You can set rows 1 to ..
  PrepareLedStrip(
    led_settings: List(LedSetting),
    part: Part,
    length: Int,
    row: Int,
  )
  /// Pull in a row and store in the working area.
  /// Light the LED strip.
  LightLeds(part: Part, row: Int)
  /// Rotate the LEDs in the low part of the working row.
  Rotate(direction: Direction)
  // SetUpperPart(length: Int, led_settings: List(LedSetting))
  /// Set upper part of led strip
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
