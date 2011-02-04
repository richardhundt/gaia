/*
var r = 0
function double(x) {
    return x + x
}
for (x=1, 10000000) {
    r = double(x)
}
print(r)
*/

class Point {
   var x = 0
   var y = 0
   function this(x,y) {
      this.x = x
      this.y = y
   }
   function move(x,y) {
      this.x = x
      this.y = y
   }
}

class Point3D extends Point {
   var z = 0
   function move(x, y, z) {
      super.move(x, y)
      this.z = z
   }
}

var p = new Point3D()
for (i in 1 .. 10000000) {
   p.move(i, i + 1, i + 2)
}

