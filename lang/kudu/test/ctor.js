class Point {
    var x, y = 0, 0
    function this(x, y) {
        this.x = x
        this.y = y
        print("ctor:", x, y)
    }
}

var p = new Point(1, 2)

