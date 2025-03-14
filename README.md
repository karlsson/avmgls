# avmgls

An AtomVM LED strip application using SPI implemented in Gleam for the ESP32-C3 SoC.

<!-- [![Package Version](https://img.shields.io/hexpm/v/avmgls)](https://hex.pm/packages/avmgls)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/avmgls/) -->


<!-- Further documentation can be found at <https://hexdocs.pm/avmgls>. -->

## Use
```sh
git clone https://github.com/karlsson/avmgls.git
cd avmgls
gleam build                      # Build the project
gleam run -m atomvm_packgleam    # Create avmgls.avm file
```
Consult [AtomVM](https://www.atomvm.net/) documentation on how to install the AtomVM image and then flash the application for your device. Par example:
```sh
$ATOMVM_ROOT/src/platforms/esp32/build/flash.sh build/dev/erlang/avmgls/avmgls.avm
```
