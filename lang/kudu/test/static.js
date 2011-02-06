class Point {
    static var DEBUG = true
    static function greet() {
        print("HELLO FROM:", this)
    }
    var x, y = 0, 0
    private var answer = 42
    function move(x, y) {
        print("move")
        this.munge()
    }
    private function munge() {
        print("private - answer:", this.answer)
    }
}

class Point3D extends Point {
    var z = 0
    function move(x, y, z) {
        this.x = x
        this.y = y
        this.z = z
        this.munge()
        print("HERE answer:", this.answer)
    }
}

var p = new Point3D()
p.move(1,2,3)

try {
    p.munge()
} catch(ex) {
    print("caught:", ex)
}

print(Point.DEBUG)
Point.greet()

print(Point::DEBUG)
Point::greet()

var p = new Point()
p.move()
try {
    print(p.answer)
} catch(ex) {
    print("caught error:", ex)
}
