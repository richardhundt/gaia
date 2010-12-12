class Point {
    var x : ?Number
    var y : ?Number
    function this(x, y) {
        print("constructor, x:", x, "y:", y, "this:", this)
        this.x = x
        this.y = y
    }
    function move(x : Number, y : Number) {
        this.clear()
        this.x = x
        this.y = y
        print("moved to: x => "~this.x~", y => "~this.y)
    }
    function clear() {
        this.x = null
        this.y = null
    }
}

var p = new Point(1, 2)
p.move(42, 69)

function addone(x : Number) {
    return x + 1;
}
var a = 42 << 1
print("add one: "~addone(a))

var o = { x : 42, y : 69 }

for (k,v in o) {
    print("o: ", k, v)
}

var a = [ 1, 2, null, 4 ]
for (i,v in a) {
    print("a:", i, v)
}

print("length: ", a.length)

print(null && true || false)
