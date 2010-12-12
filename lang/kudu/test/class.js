class Point {
   var x, y = 0, 0
   function this(x, y) {
      print("Point.this")
      this.x = x
      this.y = y
   }
   function move(x, y) {
      this.x = x
      this.y = y
   }
}

var p = new Point()
p.x = 11
p.y = 22
print(p.x, p.y)

class Point3D extends Point {
   var z = 0
   var o = { answer : 42 }
   function this(x, y, z) {
      print("Point3D.this")
      super.this(x, y)
      this.z = z
   }
   function move(x, y, z) {
      super.move(x, y)
      this.z = z
   }
}

print("constructing p")
var p = new Point3D()
print("constructing q")
var q = new Point3D()
p.o['answer'] = 69
print(p.o['answer'], q.o['answer']);

p.move(11,22,33)
print(p.x, p.y, p.z)

p = new Point3D()
print(p.x, p.y, p.z)

