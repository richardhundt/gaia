class Point {
   var _x : Number = 0
   var _y : Number = 0
   function move(x,y) {
      this._x = x
      this._y = y
   }
}

class Point3D extends Point {
   var _z : Number = 0
   function move(x, y, z) {
      super.move(x, y)
      this._z = z
   }
}

var p = new Point3D()
p._z = 42
print(p._z)

for i=1, 1e7 {
   p.move(i, i + 1, i + 2)
}
print(p._x)
function cheese(mesg) {
    print("mesg:", mesg)
}
cheese("Hey!")
