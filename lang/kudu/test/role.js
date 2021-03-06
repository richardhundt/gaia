object Explosive {
   var message = "BOOM!"
   function explode() {
      print(this.message)
   }
}

print("static:")
Explosive.explode()
print("done.")

class Point with Explosive {
   var x = 0
   var y = 0
   function this(x, y) {
      this.x = x || 0
      this.y = y || 0
   }
   function move(x, y) {
      this.x = x
      this.y = y
   }
}

var p = Point(23, 45)
print(p.x, p.y)
p.explode()
var old_explode = p.explode;

var new_explode = function(self, what) {
    print("KA"~self.message)
}

p.explode = new_explode
p.explode()
p.explode = old_explode
p.explode()

