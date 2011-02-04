object Explosive {
    function explode() {
        print("BOOM!")
    }
}

class Point {
    var x
    var y
    function this(x, y) {
        this.x = x
        this.y = y
        print("constructed a: ", this, "with:", x, y)
    }
    function move(x, y) {
        this.x = x || 0
        this.y = y || 0
    }
}

var p = new Point(42, 69)
p.move(1)

class Point3D extends Point with Explosive {
    var z
    function move(x, y, z) {
        print("Point3D.move", this, x, y, z)
        var inner = function() {
            super.move(x, y)
        }
        inner()
        this.z = z
    }
    function lambda(value) {
        return function() { return [ value, this ] }
    }
}

var p = new Point3D(11, 22)
p.move(1, 2, 3)
p.move(1, 2, 3)
p.explode()
print(p.x, p.y, p.z)

var closure = p.lambda(42)

print("the answer is: ", closure()[0])

var p = new Point(31,42)
p.x = 42

for (i in 0..10000000) {
    p.move(i, i + 1 << 1)
}

var t = { a : 42, b : 69 }

for (k, v in { a : 42, b : 69 }) {
    print("got: ", k, "=>", v)
}

for (k, v in t) {
    print("got: ", k, "=>", v)
}

function doit(arg) {
    return null
}

var p = null;
var retv = doit(p)


