
// object is its own meta table
object Delegate {
    function __call(obj) {
        //...
    }
}

object Point {
    var x : Number = 0
    var y : Number = 0
    function new() {
        return object extends this { }
    }
    function move(x,y) {
        this.x = x
        this.y = y
    }
}

object Point3D extends Point {
    var z : Number = 0
    function move(x,y,z) {
        super.move(x,y)
        this.z = z
    }
}
var p = Point.new()

// object as a trait
object Trait {
    var required = object { }
    function __apply(recv, spec) {
        recv.__apply = function(recv, spec) {
            for (k, v in spec) {
                recv.__proto[k] = this[k]
            }
        }
        for (k, v in spec) {
            if (v == this.required) {
                if (recv.__proto[k].missing) {
                    throw new TypeError("missing required member:"~k)
                }
                spec[k] = recv.__proto[k]
            }
            else {
                recv.__proto[k] = v
            }
        }
    }
}
object Explosive {
    with Trait {
        ignite  : Function = required;
        message : String   = required;
    }
    function explode() {
        this.ignite()
    }
}


class Dynamite extends Object {
    with Explosive { blast = explode, message = nil }

    var message : String = "BOOM!"

    function ignite(mesg) {
        print(mesg)
    }
}

var d = new Dynamite()
d.blast()

