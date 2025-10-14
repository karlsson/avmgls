import avmgls/ls.{type Colour, type LedSubject, type StartArgs}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import glydamic

type LedDict =
  Dict(Pid, Colour)

type State {
  State(
    led_array: List(LedDict),
    spi: Pid,
    strip_len: Int,
    index: Int,
    device_name: ls.StripType,
  )
}

pub fn init(sa: StartArgs) -> Result(LedSubject, Nil) {
  let ls.StartArgs(di_pin:, ci_pin: _ci_pin, strip_type:, strip_len:) = sa
  let spi = spi_init_ws2812(di_pin)
  let state =
    State(
      led_array: init_led_dict(strip_len),
      spi: spi,
      strip_len: strip_len,
      index: 0,
      device_name: strip_type,
    )
  let start_subject = process.new_subject()
  glydamic.splink(fn() { loop_init(start_subject, state) })
  process.receive(start_subject, 200)
}

fn loop_init(start_subject, state: State) {
  let led_subject: LedSubject = process.new_subject()
  process.send(start_subject, led_subject)
  process.send_after(led_subject, 1000, ls.UpdateLedStrip)
  loop(led_subject, state)
}

fn loop(led_subject: LedSubject, state: State) {
  let #(new_array, new_index) = case process.receive_forever(led_subject) {
    ls.ClearLed(sub, index) -> {
      let dict = ia_get(state.led_array, index)
      let new_dict = dict.delete(dict, sub)
      let na = ia_set(state.led_array, index, new_dict)
      #(na, index)
    }
    ls.SetLed(sub, index, colour) -> {
      let dict = ia_get(state.led_array, index)
      {
        let new_dict = dict.insert(dict, sub, colour)
        let na = ia_set(state.led_array, index, new_dict)
        #(na, index)
      }
    }
    ls.UpdateLedStrip -> {
      let na_index = update_led_strip(state)
      process.send_after(led_subject, 100, ls.UpdateLedStrip)
      na_index
    }
  }
  let new_index = int.max(state.index, new_index)
  loop(led_subject, State(..state, led_array: new_array, index: new_index))
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

fn ia_get(list: List(LedDict), index: Int) -> LedDict {
  let assert Ok(item) = list.first(list.drop(list, index))
  item
}

fn init_led_dict(strip_len: Int) -> List(LedDict) {
  list.range(1, strip_len) |> list.map(fn(_) { dict.from_list([]) })
}

// -------------------------------------------------

fn update_led_strip(state: State) -> #(List(LedDict), Int) {
  let State(led_array:, spi:, strip_len: _, index:, device_name: _) = state
  case index >= 0 {
    False -> #(led_array, index)
    True -> {
      let spi_led_array =
        list.reverse(
          list.index_fold(led_array, [], fn(acc, item, i) {
            case i < index {
              True -> [item, ..acc]
              False -> acc
            }
          }),
        )
      let spi_color_list =
        list.map(spi_led_array, fn(led_dict) { sum_rgb(led_dict) })
      let _ = write_to_spi_ws2812(build_stream(spi_color_list), spi)
      #(led_array, -1)
    }
  }
}

fn sum_rgb(led_dict: LedDict) {
  dict.fold(led_dict, ls.RGB(0, 0, 0), fn(acc, _key, rgb) {
    let ls.RGB(r1, g1, b1) = acc
    let ls.RGB(r2, g2, b2) = rgb
    ls.RGB(int.min(r1 + r2, 255), int.min(g1 + g2, 255), int.min(b1 + b2, 255))
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
