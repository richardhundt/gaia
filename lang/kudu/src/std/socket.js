package std.socket

enum SockOpts {
   reuseaddr;
   type;
   error;
   dontroute;
   sndbuf;
   rcvbuf;
   sndlowat;
   rcvlowat;
   broadcast;
   keepalive;
   oobinline;
   linger;
   tcp_nodelay;
   multicast_ttl;
   multicast_if;
   multicast_loop;
}

function getaddrinfo(host, addr) {
   return magic::sys::sock::getaddrinfo(host, addr)
}

function address() { return magic::sys::sock::addr() }
function inet_pton(txt_addr) { return magic::sys::sock::inet_pton(txt_addr) }
function inet_ntop(bin_addr) { return magic::sys::sock::inet_ntop(bin_addr) }

function pack_sockaddr_in(port, host) {
   var saddr = magic::sys::sock::addr()
   if (!saddr.inet(port, magic::sys::sock::inet_pton(host))) {
      return false, _ERR
   }
   return saddr
}

function pack_sockaddr_un(path) {
   var saddr = sys.sock.addr()
   if (!saddr.file(path)) {
      return false, _ERR
   }
   return saddr
}

class Socket {

    public var type   = 'stream'
    public var domain = 'inet'
    public var handle
    public var buffer

    public var _nonblocking = false

    function this(type, domain) {
        if (type)   this.type   = type
        if (domain) this.domain = domain
        this.handle = magic::sys::sock::handle()
        this.buffer = magic::sys::mem::pointer().alloc()
        this.handle.socket(this.type, this.domain)
    }

    function shutdown(...) {
       return this.handle.shutdown(...)
    }

    function close() {
       return this.handle.close()
    }

    function getfd() {
       return this.handle.getfd()
    }

    function setfd(fd) {
       this.handle.setfd(fd)
    }

    function nonblocking(flag) {
       if (flag != nil) {
          var prev = this._nonblocking
          this._nonblocking = flag
          this.handle.nonblocking(flag)
          return prev
       }
       return this._nonblocking
    }

    function sockopt(opt, ...) {
       if (OPTS[opt]) {
          return magic::assert(this.handle.sockopt(opt, ...))
       }
       else {
          throw "invalid socket option:" ~ opt
       }
    }

    function errstr() {
       return magic::sys::sock::strerror()
    }

    function listen(backlog) {
       return assert(this.handle.listen(backlog))
    }

    function accept() {
       var newfd = magic::sys::sock::handle()
       var val, err = assert(this.handle.accept(newfd))
       if (val) {
          return this.accept_handle(newfd)
       }
       return nil, errorMessage
    }

    function accept_handle(newfd) {
       var sock = new Socket()
       sock.handle = newfd
       return sock
    }

    function read(...) {
       return this.handle.read(...)
    }

    function write(...) {
       return this.handle.write(...)
    }

    function readline(irs) {
       irs = irs || "\n"
       var rfh = this.handle
       var buf = this.buffer
       var got, ofs, idx = 0, 0
       while (true) {
          got = rfh.read(buf, 4096)
          idx = buf.index(irs, ofs)
          if (got) ofs += got
          if (!got) break
          if (idx) {
             return buf.substr(0, idx + irs.length, "")
          }
       }
       return buf.substr(0, nil, "")
    }

    function connect(host, port) {
       return this.handle.connect(pack_sockaddr_in(port, host))
    }

    function recv(how, from_addr, ...) {
       return this.handle.recv(how, from_addr)
    }
    function send(data, dest_addr, ...) {
       return this.handle.send(data, dest_addr, ...)
    }
    function bind(host, port) {
       return assert(this.handle.bind(pack_sockaddr_in(port, host)))
    }
    function membership(host, flag) {
       return this.handle.membership(magic::sys::sock::inet_aton(host), flag)
    }
}

var sock = new Socket()
assert(sock.bind('127.0.0.1', 8089))
assert(sock.listen(16))
while (true) {
    var client = sock.accept()
    print("client:", client)
    while (true) {
        var line = client.readline()
        print("read:", line)
        client.write("thanks for:", line)
    }
}


