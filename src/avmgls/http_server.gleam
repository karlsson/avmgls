import gleam/erlang/process
import gleam/string

type SocketOption {
  Binary
}

type ListenSocket

pub opaque type Router {
  Router
}

pub fn start_server(port: Int, router: Router) -> Result(Nil, String) {
  case listen(port, [Binary]) {
    Ok(listen_socket) -> {
      process.spawn(fn() { accept(listen_socket, router) })
      Ok(Nil)
    }
    Error(reason) -> Error(string.inspect(reason))
  }
}

type ErrorReason

@external(erlang, "gen_tcp", "listen")
fn listen(
  port: Int,
  options: List(SocketOption),
) -> Result(ListenSocket, ErrorReason)

fn accept(listen_socket, router) -> Result(Nil, String) {
  case ext_accept(listen_socket) {
    Ok(_socket) -> {
      process.spawn_unlinked(fn() { accept(listen_socket, router) })
      loop(router)
    }
    Error(reason) -> Error(string.inspect(reason))
  }
}

type InetSocket

@external(erlang, "gen_tcp", "accept")
fn ext_accept(listen_socket: ListenSocket) -> Result(InetSocket, ErrorReason)

fn loop(router) {
  todo
}
