class A {
    function greet(whom) {
        print("Hello", whom, this)
    }
}

class B {
    function this() {
        var o = object {
            __index = function(that) {
                var found = this[that]
                if (found == nil) {
                    throw new AccessError("no member called:"~that)
                }
                return found
            }
        }
        return proxy(this, o)
    }
}

var a = new A()
var b : Proxy = a
b.greet("World!")
print(a)
print(b)

object Recorder {
    function __index(k) {
        var member = this[k]
        var record = [ ]
        if (typeof member == Function) {
            return proxy(member, object {
                function __call(...args) {
                    record.push({ func = member, args = args })
                }
            })
        }
    }
    function __newindex(k,v) {
        this[k] = v
    }
    function apply() {

    }
}

var o = object {

}

var a = new A

a = a wrap Recorder
if (a is wrap Recorder) {

}
if (a wrap Recorder) {

}
a = proxy(a, Autoload)
a = unproxy(a)
p = proxyof(a)
proxyof(a).synchronize()


