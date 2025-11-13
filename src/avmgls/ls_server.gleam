import avmgls/avm_ets
import avmgls/ls.{type Colour, type LedSubject, type StartArgs}
import gleam/bit_array
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/otp/actor

type State {
  State(
    led_array: List(Colour),
    spi: Pid,
    strip_len: Int,
    device_name: ls.StripType,
    table: avm_ets.Table(BitArray),
    my_subject: ls.LedSubject,
  )
}

pub fn init(sa: StartArgs, ls_name: process.Name(ls.LedCommand)) {
  actor.new_with_initialiser(1000, fn(_) {
    let ls.StartArgs(di_pin:, ci_pin: _ci_pin, strip_type:, strip_len:) = sa
    let spi = spi_init_ws2812(di_pin)
    let led_subject: LedSubject = process.named_subject(ls_name)

    let state =
      State(
        led_array: init_leds(strip_len),
        spi: spi,
        strip_len: strip_len,
        device_name: strip_type,
        table: avm_ets.new_default("ledmatrix"),
        my_subject: led_subject,
      )
    Ok(actor.initialised(state))
  })
  |> actor.named(ls_name)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(state: State, message: ls.LedCommand) {
  let new_array = case message {
    ls.PrepareSetLed(index, colour) -> {
      ia_set(state.led_array, index, colour)
    }
    ls.PrepareLedStrip(row) -> {
      let _ = update_led_strip(state, row)
      init_leds(state.strip_len)
    }
    ls.LightLeds(row) -> {
      case avm_ets.lookup(state.table, row) {
        Ok(stream) -> {
          let _ = write_to_spi_ws2812(stream, state.spi)
          avm_ets.insert(state.table, 0, stream)
          Nil
        }
        Error(Nil) -> Nil
      }
      state.led_array
    }
    ls.Duration(ms) -> {
      process.sleep(ms)
      state.led_array
    }
    ls.Rotate(upto) -> {
      let assert Ok(stream) = avm_ets.lookup(state.table, 0)
      let stream = rotate_upto(stream, upto)
      let _ = write_to_spi_ws2812(stream, state.spi)
      avm_ets.insert(state.table, 0, stream)
      state.led_array
    }
    ls.RunCommands(commands) -> {
      // The gleam/otp/factory_supervisor uses the simple_on_for_one
      // supervisor strategy which is not implemented in AtomVM (yet).
      // Just spawn-link, it won't crash anyway since we have type checking.
      process.spawn(fn() { run_commands(state.my_subject, commands) })
      state.led_array
    }
  }
  actor.continue(State(..state, led_array: new_array))
}

// ---
fn run_commands(led_subject, commands) {
  list.each(commands, fn(command) { process.send(led_subject, command) })
}

// -----------------------------------------------------------
fn ia_set(list: List(a), index: Int, item: a) -> List(a) {
  list.index_map(list, fn(x, i) {
    case i == index {
      False -> x
      True -> item
    }
  })
}

fn init_leds(strip_len: Int) -> List(Colour) {
  list.range(1, strip_len) |> list.map(fn(_) { ls.RGB(0, 0, 0) })
}

// -------------------------------------------------

fn update_led_strip(state: State, row: Int) -> avm_ets.Table(BitArray) {
  let stream = build_stream(state.led_array)
  avm_ets.insert(state.table, row, stream)
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

/// Rotate bytes upto n.
/// Every index is 9 bytes in size.
pub fn rotate_upto(bytes: BitArray, n: Int) -> BitArray {
  // 9 bytes * 8 bits
  let length = bit_array.byte_size(bytes)
  let n = n * 9
  let n1 = int.min(n, length)
  let #(keep, to_rotate) = case bytes {
    <<to_rotate:size(n1)-bytes, fix:bytes>> -> #(fix, to_rotate)
    _ -> #(bytes, <<>>)
  }
  <<rotate(to_rotate):bits, keep:bits>>
}

/// Rotate one RGB LED <=> 9 bytes
fn rotate(bytes: BitArray) -> BitArray {
  let start = bit_array.byte_size(bytes) - 9
  case start <= 0 {
    True -> bytes
    False -> {
      case bytes {
        <<head:size(start)-bytes, last9:bytes>> -> <<
          last9:bits,
          head:bits,
        >>
        _ -> bytes
      }
    }
  }
}
