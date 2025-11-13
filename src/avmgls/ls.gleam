import gleam/erlang/process.{type Subject}

// Currently only Ws2812 implemented
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

pub type LedCommand {
  PrepareSetLed(index: Int, col: Colour)
  PrepareLedStrip(row: Int)
  LightLeds(row: Int)
  Rotate(upto: Int)
  Duration(ms: Int)
  RunCommands(List(LedCommand))
}

pub type LedSubject =
  Subject(LedCommand)

pub fn clear_led(ledsub: LedSubject, index: Int) -> Nil {
  set_led(ledsub, index, RGB(0, 0, 0))
}

pub fn set_led(ledsub: LedSubject, index: Int, col: Colour) -> Nil {
  process.send(ledsub, PrepareSetLed(index, col))
}
