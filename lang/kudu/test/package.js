import test.shapes.Point

//export Point, Point3D
class Point3D extends Point {
    var z = 0
    function move(x, y, z) {
        super.move(x, y)
        this.z = z
    }
}

var p1 = new Point
print(p1)
var p2 = new Point3D
p2.move(1,2,3)
print(p2)
print(p2.x, p2.y, p2.z)
