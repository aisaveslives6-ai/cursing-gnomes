extends SceneTree
func _initialize():
    for fc in [["humans"], ["humans","ogres","elves","gnomes","undead"]]:
        var m = MapGen.new().generate(fc, 7, "frozen")
        var img = m["terrain_image"]
        var c: Color = img.get_pixel(100, 100)
        var c2: Color = img.get_pixel(256, 256)
        print(fc.size(), " factions: px(100,100)=", c, " px(256,256)=", c2)
    quit(0)
