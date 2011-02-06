class Point {
    var _x = 0
    var y = 0
    function get x() { return this._x }
    function set x(x) { this._x = x }
}

var p = new Point()
p.x = 69
p.y = 42

print(typeof p)
for (i in 1 .. 10000000) {
    p.x = 42
}
print(p.x)

