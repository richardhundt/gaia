class A {
    private   var priv = 'a'
    public    var publ = 'b'
    protected var prot = 'c'

    private function priv_func() {
        print("private!")
    }
    public function publ_func() {
        print("public!")
    }
    protected function prot_func() {
        print("protected!")
    }
}

class B extends A {
    function test() {
        try {
            print(this.priv)
        } catch(ex) {
            print("caught:", ex)
        }
        assert(this.prot)
        assert(this.publ)
        this.publ_func()
        this.prot_func()
        try {
            this.priv_func()
        } catch(ex) {
            print("caught:", ex)
        }
    }
}

var b = new B
b.test()
b.publ_func()

try {
    b.priv_func()
} catch(ex) {
    print("caught:", ex)
}

try {
    b.prot_func()
} catch(ex) {
    print("caught:", ex)
}

