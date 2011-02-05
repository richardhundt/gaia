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
