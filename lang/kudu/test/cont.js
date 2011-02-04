var i=0
while (i < 10) {
    i += 1
    if (i % 2 == 0) {
        print("got here")
        continue
    }
    if (i == 5) { break }
    print(i, i % 2)
}

