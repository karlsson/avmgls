// import avmgls/avm_ets
import avmgls/ls.{type Colour, type LedSubject, type StartArgs}
import gleam/bit_array
import gleam/dict
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/otp/actor

type State {
  State(
    spi: Pid,
    strip_len: Int,
    device_name: ls.StripType,
    table: dict.Dict(Int, BitArray),
    my_subject: ls.LedSubject,
  )
}

pub fn init(sa: StartArgs, ls_name: process.Name(List(ls.LedCommand))) {
  // You need a custom initialiser since the table should be created
  // by the owning, i.e. the spawned process.
  actor.new_with_initialiser(1000, fn(_) {
    let ls.StartArgs(di_pin:, ci_pin: _ci_pin, strip_type:, strip_len:) = sa
    let spi = spi_init_ws2812(di_pin)
    let led_subject: LedSubject = process.named_subject(ls_name)

    let state =
      State(
        spi: spi,
        strip_len: strip_len,
        device_name: strip_type,
        table: dict.new(),
        my_subject: led_subject,
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

// ---
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

fn run_command(state: State, command) -> State {
  case command {
    ls.PrepareLedStrip(led_array, row) -> {
      let new_table =
        set_leds(state.strip_len, led_array)
        |> build_stream()
        |> dict.insert(state.table, row, _)
      State(..state, table: new_table)
    }
    ls.LightLeds(row) -> {
      case dict.get(state.table, row) {
        Ok(stream) -> {
          echo row
          let _ = write_to_spi_ws2812(stream, state.spi)
          // Row 0 is special as the current working row.
          let new_table = dict.insert(state.table, 0, stream)
          State(..state, table: new_table)
        }
        Error(Nil) -> state
      }
    }
    ls.Duration(ms) -> {
      process.sleep(ms)
      state
    }
    ls.Rotate(upto, direction) -> {
      case dict.get(state.table, 0) {
        Ok(stream) -> {
          let new_stream = rotate_upto(stream, upto, direction)
          let _ = write_to_spi_ws2812(new_stream, state.spi)
          let new_table = dict.insert(state.table, 0, new_stream)
          State(..state, table: new_table)
        }
        Error(Nil) -> echo state
      }
    }
  }
}

// -------------------------------------------------

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

/// Rotate bytes upto n.
/// Every index is 9 bytes in size.
pub fn rotate_upto(bytes: BitArray, n: Int, direction: ls.Direction) -> BitArray {
  // 9 bytes * 8 bits
  let length = bit_array.byte_size(bytes)
  let n = n * 9
  let n1 = int.min(n, length)
  let #(keep, to_rotate) = case bytes {
    <<to_rotate:size(n1)-bytes, fix:bytes>> -> #(fix, to_rotate)
    _ -> #(bytes, <<>>)
  }
  <<rotate(to_rotate, direction):bits, keep:bits>>
}

/// Rotate one RGB LED <=> 9 bytes
fn rotate(bytes: BitArray, direction: ls.Direction) -> BitArray {
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
