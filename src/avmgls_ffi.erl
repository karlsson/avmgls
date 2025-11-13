-module(avmgls_ffi).
-export([spi_init_ws2812/1, write_to_spi_ws2812/2,
        read_priv/1]).
-export([ets_new/2, ets_delete_table/1,
        ets_insert/3, ets_delete_object/2, ets_lookup/2]).

-doc "Only mosi is used for ws2812. Clock speed set to 2.4 MHz".
-spec spi_init_ws2812(DiPin:: integer()) -> pid().
spi_init_ws2812(DiPin) ->
    C = spi_config(DiPin, -1, ws2812),
    spi:open(C).


write_to_spi_ws2812(WriteData, Spi) ->
    case spi:write(Spi, ws2812, #{write_data => WriteData}) of
      ok -> {ok, nil};
    _ -> {error, nil}
    end.

spi_config(DiPin, CiPin, DeviceName = ws2812) ->
    [
     {bus_config,
      [
       {miso, -1},       %% Not used
       {mosi, DiPin},
       {sclk, CiPin}     %% Not used, set to -1
      ]},
     {device_config,
      [
       {DeviceName,
        [
         {clock_speed_hz, 2400000}, %% 3 SPI bits per LED bit ~ 1.25 uS
         {mode, 0},
         {cs, -1}, %% Not used
         {address_len_bits, 8}
        ]}
      ]}
    ].

read_priv(Path) ->
  atomvm:read_priv(avmgls, Path).

%% ---------- ETS table handling ---------------
ets_new(Name, Options) ->
  EtsOpts = ets_map(Options, []),
  ets:new(Name, EtsOpts).

ets_map([], O) ->
  O;
ets_map([{table_type, set}|T], O) ->
  ets_map(T, [set|O]);
ets_map([{access_type, Type}|T], O) ->
  ets_map(T, [Type|O]);
ets_map([{keypos_type, {keypos, N}}| T], O) ->
  ets_map(T, [{keypos, N}|O]).

ets_delete_table(Table) ->
  ets:delete(Table),
  nil.

ets_insert(Table, Key, Value) ->
  ets:insert(Table, {Key, Value}),
  Table.

ets_delete_object(Table, Key) ->
  ets:delete(Table, Key),
  Table.

ets_lookup(Table, Key) ->
  case ets:lookup(Table, Key) of
    [{Key, Value}] -> {ok, Value};
    _ -> {error, nil}
  end.
