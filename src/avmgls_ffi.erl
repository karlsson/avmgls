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

%% ------------- Network --------------

-define(DEFAULT_AP_SSID, <<"AtomVM-ESP32">>).
-define(DEFAULT_AP_PSK, <<"esp32default">>).
-define(DEFAULT_WEB_SERVER_PORT, 8080).

erase_net_config() ->
    io:format("Erasing net config.~n"),
    esp:nvs_erase_key(atomvm, sta_ssid),
    esp:nvs_erase_key(atomvm, sta_psk).

save_net_config(SSID, Pass) ->
    io:format("Saving config: SSID: ~p Pass: ~p.~n", [SSID, Pass]),
    esp:nvs_set_binary(atomvm, sta_ssid, erlang:list_to_binary(SSID)),
    esp:nvs_set_binary(atomvm, sta_psk, erlang:list_to_binary(Pass)).

get_net_config() ->
    case esp:nvs_get_binary(atomvm, sta_ssid) of
        undefined ->
            get_default_net_config();
        SSID ->
            case esp:nvs_get_binary(atomvm, sta_psk) of
                undefined ->
                    get_default_net_config();
                Psk ->
                    get_net_config(SSID, Psk)
            end
    end.

get_default_net_config() ->
    Creds = [
        {ssid, ?DEFAULT_AP_SSID},
        {psk, ?DEFAULT_AP_PSK}
    ],
    {wait_for_ap, Creds}.

get_net_config(SSID, Psk) ->
    Creds = [
        {ssid, SSID},
        {psk, Psk}
    ],
    {wait_for_sta, Creds}.

maybe_start_network() ->
    case esp:nvs_get_binary(atomvm, wlan_enabled) of
        undefined ->
            start_network();
        <<"always">> ->
            start_network();
        <<"never">> ->
            not_started
    end.

start_network() ->
    io:format("Starting network...~n"),
    {WaitFunc, Creds} = get_net_config(),
    case network:WaitFunc(Creds) of
        ok ->
            io:format("WLAN AP ready. Waiting connections.~n"),
            Event = #{
                event => wlan_ap_started
            },
            avm_pubsub:pub(default_pubsub, [system, network, wlan, connected], Event),
            maybe_start_web_server(),
            started;
        {ok, {Address, Netmask, Gateway}} ->
            io:format(
                "Acquired IP address: ~s Netmask: ~s Gateway: ~s~n",
                [to_string(Address), to_string(Netmask), to_string(Gateway)]
            ),
            Event = #{
                event => wlan_connected,
                address => Address,
                netmask => Netmask,
                gateway => Gateway
            },
            avm_pubsub:pub(default_pubsub, [system, network, wlan, connected], Event),
            maybe_start_web_server(),
            started;
        Error ->
            io:format("An error occurred starting network: ~p~n", [Error]),
            not_started
    end.

to_string({{A, B, C, D}, Port}) ->
    io_lib:format("~p.~p.~p.~p:~p", [A, B, C, D, Port]);
to_string({A, B, C, D}) ->
    io_lib:format("~p.~p.~p.~p", [A, B, C, D]).

%% Web Server
%%

maybe_start_web_server() ->
    case get_web_server_config() of
        {always, Port} ->
            Router = [
                {"*", ?MODULE, []}
            ],
            http_server:start_server(Port, Router),
            io:format("Web server listening on port ~p~n", [Port]),
            started;
        _ ->
            io:format("Web server not enabled: skipping.~n"),
            not_started
    end.

get_web_server_config() ->
    Enable =
        case esp:nvs_get_binary(atomvm, web_server_enable) of
            undefined ->
                always;
            <<"always">> ->
                always;
            <<"never">> ->
                never
        end,
    Port =
        case esp:nvs_get_binary(atomvm, web_server_port) of
            undefined ->
                ?DEFAULT_WEB_SERVER_PORT;
            PortBinary ->
                try erlang:binary_to_integer(PortBinary) of
                    PortInt -> PortInt
                catch
                    Error ->
                        io:format("Unable to read web server port: ~p.~n", [Error]),
                        ?DEFAULT_WEB_SERVER_PORT
                end
        end,
    {Enable, Port}.

handle_req("GET", [], Conn) ->
    Body =
        <<
            "<html>\n"
            "   <body>\n"
            "       <h1>Configuration</h1>\n"
            "       <form method=\"post\">\n"
            "           <p>SSID: <input type=\"text\" name=\"ssid\"></p>\n"
            "           <p>Pass: <input type=\"text\" name=\"pass\"></p>\n"
            "           <input type=\"submit\" value=\"Submit\">\n"
            "       </form>\n"
            "   </body>\n"
            "</html>"
        >>,
    http_server:reply(200, Body, Conn);
handle_req("POST", [], Conn) ->
    ParamsBody = proplists:get_value(body_chunk, Conn),
    Params = http_server:parse_query_string(ParamsBody),

    SSID = proplists:get_value("ssid", Params),
    Pass = proplists:get_value("pass", Params),
    save_net_config(SSID, Pass),

    Body =
        <<
            "<html>\n"
            "   <body>\n"
            "       <h1>Configuration</h1>\n"
            "       <p>Configured, restart device to apply wifi configuration.</p>\n"
            "   </body>\n"
            "</html>"
        >>,
    http_server:reply(200, Body, Conn);
handle_req(Method, Path, Conn) ->
    erlang:display(Conn),
    erlang:display({Method, Path}),
    Body = <<"<html><body><h1>Not Found</h1></body></html>">>,
    http_server:reply(404, Body, Conn).
