import gleam/erlang/atom

pub type Table(a)

pub type TableType {
  Set
}

pub type AccessType {
  Private
  Protected
  Public
}

pub opaque type KeyposType {
  Keypos(Int)
}

pub type Option {
  TableType(TableType)
  AccessType(AccessType)
  // Keypos is a nonnegative integer
  KeyposType(KeyposType)
}

pub fn keypos(i: Int) -> KeyposType {
  case i < 1 {
    True -> Keypos(1)
    _ -> Keypos(i)
  }
}

pub fn new_default(name: String) -> Table(a) {
  new(name, [TableType(Set), AccessType(Protected), KeyposType(keypos(1))])
}

pub fn new(name: String, options: List(Option)) -> Table(a) {
  let atom_name = atom.create(name)
  avm_ets_new(atom_name, options)
}

@external(erlang, "avmgls_ffi", "ets_new")
fn avm_ets_new(a: atom.Atom, o: List(Option)) -> Table(a)

@external(erlang, "avmgls_ffi", "ets_delete_table")
pub fn delete_table(t: Table(a)) -> Nil

@external(erlang, "avmgls_ffi", "ets_insert")
pub fn insert(t: Table(a), key: Int, value: a) -> Table(a)

@external(erlang, "avmgls_ffi", "ets_delete_object")
pub fn delete_object(t: Table(a), key: Int) -> Table(a)

@external(erlang, "avmgls_ffi", "ets_lookup")
pub fn lookup(t: Table(a), key: Int) -> Result(a, Nil)
