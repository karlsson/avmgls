import avmgls/ls.{type Colour, type StartArgs}
import gleam/bit_array
import gleam/dict
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/otp/actor

// import avmgls/avm_ets

type PartArea {
  PartArea(working_ls: BitArray, table: dict.Dict(Int, BitArray))
}

type Parts {
  Parts(upper: PartArea, lower: PartArea)
}

type State {
  State(spi: Pid, device_name: ls.StripType, parts: Parts)
}

pub fn init(sa: StartArgs, ls_name: process.Name(List(ls.LedCommand))) {
  // If ETS table you need a custom initialiser since the table should be
  // created by the owning, i.e. the spawned process.
  actor.new_with_initialiser(1000, fn(_) {
    let ls.StartArgs(di_pin:, ci_pin: _ci_pin, strip_type:) = sa
    let spi = spi_init_ws2812(di_pin)

    let state =
      State(
        spi: spi,
        device_name: strip_type,
        parts: Parts(
          upper: PartArea(<<>>, dict.new()),
          lower: PartArea(<<>>, dict.new()),
        ),
      )
    Ok(actor.initialised(state))
  })
  |> actor.named(ls_name)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(state: State, message: List(ls.LedCommand)) {
  let new_state =
    list.fold(message, state, fn(state, command) { run_command(state, command) })
  actor.continue(new_state)
}

fn run_command(state: State, command) -> State {
  case command {
    ls.PrepareLedStrip(led_array, part, length, row) -> {
      let stream =
        set_leds(length, led_array)
        |> build_stream()

      let pa = case part {
        ls.Upper -> state.parts.upper
        ls.Lower -> state.parts.lower
      }

      let new_table = dict.insert(pa.table, row, stream)

      State(..state, parts: case part {
        ls.Upper ->
          Parts(..state.parts, upper: PartArea(..pa, table: new_table))
        ls.Lower ->
          Parts(..state.parts, lower: PartArea(..pa, table: new_table))
      })
    }
    ls.LightLeds(part, row) -> {
      case part {
        ls.Upper -> {
          let pa = state.parts.upper
          case dict.get(pa.table, row) {
            Ok(stream) -> {
              let _ =
                write_to_spi_ws2812(
                  <<state.parts.lower.working_ls:bits, stream:bits>>,
                  state.spi,
                )
              State(
                ..state,
                parts: Parts(
                  ..state.parts,
                  upper: PartArea(..pa, working_ls: stream),
                ),
              )
            }
            Error(Nil) -> state
          }
        }
        ls.Lower -> {
          let pa = state.parts.lower
          case dict.get(pa.table, row) {
            Ok(stream) -> {
              let _ =
                write_to_spi_ws2812(
                  <<stream:bits, state.parts.upper.working_ls:bits>>,
                  state.spi,
                )
              State(
                ..state,
                parts: Parts(
                  ..state.parts,
                  lower: PartArea(..pa, working_ls: stream),
                ),
              )
            }
            Error(Nil) -> state
          }
        }
      }
    }
    ls.Duration(ms) -> {
      process.sleep(ms)
      state
    }
    ls.Rotate(direction) -> {
      case state.parts.lower {
        PartArea(<<>>, _) -> state
        PartArea(stream, dict) -> {
          let new_stream = rotate(stream, direction)
          let _ =
            write_to_spi_ws2812(
              <<new_stream:bits, state.parts.upper.working_ls:bits>>,
              state.spi,
            )
          State(
            ..state,
            parts: Parts(..state.parts, lower: PartArea(new_stream, dict)),
          )
        }
      }
    }
  }
}

// -------------------------------------------------
pub fn set_leds(
  strip_len: Int,
  led_settings: List(ls.LedSetting),
) -> List(Colour) {
  list.range(0, { strip_len - 1 })
  |> list.map(fn(i) {
    case list.key_find(led_settings, i) {
      Error(Nil) -> ls.RGB(0, 0, 0)
      Ok(item) -> item
    }
  })
}

@external(erlang, "avmgls_ffi", "spi_init_ws2812")
fn spi_init_ws2812(di_pin: Int) -> Pid

@external(erlang, "avmgls_ffi", "write_to_spi_ws2812")
fn write_to_spi_ws2812(write_data: BitArray, spi: Pid) -> Result(Nil, Nil)

fn build_stream(lc: List(Colour)) -> BitArray {
  let f1 = fn(acc: BitArray, c: Colour) {
    let ls.RGB(r, g, b) = c
    // The stream colour order is green, red, blue
    let lsb = led_strip_bytes(g, r, b)
    <<acc:bits, lsb:bits>>
  }
  list.fold(lc, <<>>, f1)
}

// One RGB Led will be 72 SPI bits <=> 9 bytes
fn led_strip_bytes(c1: Int, c2: Int, c3: Int) -> BitArray {
  let cb1 = led_strip_bits(c1)
  let cb2 = led_strip_bits(c2)
  let cb3 = led_strip_bits(c3)
  <<cb1:size(24), cb2:size(24), cb3:size(24)>>
}

/// --------------------------------
// WS2812 LED SPI 1 bit in will be 3 bits out
// Bit = 1 -> 110, 0.8 us high, 0.45 us low at 2.4 MHz
// Bit = 0 -> 100, 0.4 us high, 0.85 us low
// One byte will be 24 SPI bits ( 3 bytes )
fn led_strip_bits(a: Int) -> Int {
  let byte = int.bitwise_and(a, 255)
  led_strip_bits2(byte, 7, 0)
}

fn led_strip_bits2(b: Int, n: Int, acc: Int) -> Int {
  case n < 0 {
    True -> acc
    False -> {
      let spi_bits = case int.bitwise_shift_right(b, n) |> int.bitwise_and(1) {
        // 110
        1 -> 6
        // 100
        0 -> 4
        // one bit can only be 0 or 1 unless we are on a quant computer
        _ -> panic
      }
      led_strip_bits2(
        b,
        n - 1,
        int.bitwise_shift_left(acc, 3) |> int.bitwise_or(spi_bits),
      )
    }
  }
}

/// Rotate one RGB LED <=> 9 bytes
pub fn rotate(bytes: BitArray, direction: ls.Direction) -> BitArray {
  let start = bit_array.byte_size(bytes) - 9
  case start {
    start if start <= 0 -> bytes
    start -> {
      case bytes, direction {
        <<head:size(start)-bytes, last9:bytes>>, ls.Up -> <<
          last9:bits,
          head:bits,
        >>
        <<first9:size(9)-bytes, last:bytes>>, ls.Down -> <<
          last:bits,
          first9:bits,
        >>
        _, _ -> bytes
      }
    }
  }
}
