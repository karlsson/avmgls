import avmgls/avm_ets
import avmgls/ls_server
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  1
  |> should.equal(1)
}

pub fn ets_test() {
  let table: avm_ets.Table(BitArray) = avm_ets.new_default("myname")
  assert Ok(<<49, 50>>)
    == table
    |> avm_ets.insert(1, <<23, 45>>)
    |> avm_ets.insert(2, <<45, 46>>)
    |> avm_ets.insert(1, <<49, 50>>)
    |> avm_ets.lookup(1)
  assert Error(Nil)
    == table
    |> avm_ets.delete_object(1)
    |> avm_ets.lookup(1)
}

pub fn rotate_test() {
  let list2bin = fn(a) { list.fold(a, <<>>, fn(b, i) { <<b:bits, i>> }) }
  let array = list.range(1, 27) |> list2bin
  let array1 = list.range(1, 9) |> list2bin
  let array2 = list.range(10, 18) |> list2bin
  let array3 = list.range(19, 27) |> list2bin
  let array4 = <<array2:bits, array1:bits, array3:bits>>
  assert ls_server.rotate_upto(array, 2) == array4
}
