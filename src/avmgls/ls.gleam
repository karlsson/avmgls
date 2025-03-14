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
  ClearLed(from: process.Pid, index: Int)
  SetLed(from: process.Pid, index: Int, col: Colour)
  UpdateLedStrip
}

pub type LedSubject =
  Subject(LedCommand)

pub fn clear_led(ledsub: LedSubject, index: Int) -> Nil {
  process.send(ledsub, ClearLed(process.self(), index))
}

pub fn set_led(ledsub: LedSubject, index: Int, col: Colour) -> Nil {
  process.send(ledsub, SetLed(process.self(), index, col))
}
