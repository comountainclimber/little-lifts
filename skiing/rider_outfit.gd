extends RefCounted

# Cloth, skin, helmet and hardware are baked per moving part. Every guest with
# the same outfit shares the meshes; the wrap lens uses a second, glossy finish.
static var _parts := {}
static var _paint: StandardMaterial3D
static var _glass: StandardMaterial3D
const INK := Color("#283849")
const SEAM := Color("#435263")
const MITT := Color("#3b4651")

static func _surface(gloss := false) -> SurfaceTool:
	if _paint == null:
		_paint = StandardMaterial3D.new()
		_paint.vertex_color_use_as_albedo = true
		_paint.vertex_color_is_srgb = true
		_paint.roughness = 0.86
		_glass = _paint.duplicate()
		_glass.roughness = 0.23
		_glass.metallic = 0.23
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	s.set_material(_glass if gloss else _paint)
	return s

static func _triangle(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var normal := (c-a).cross(b-a)
	if normal.length_squared()<0.00000000000001:
		return
	normal = normal.normalized()
	var reverse := normal.dot(out)<0.0
	s.set_normal(-normal if reverse else normal)
	s.set_color(ca)
	s.add_vertex(a)
	s.set_color(cc if reverse else cb)
	s.add_vertex(c if reverse else b)
	s.set_color(cb if reverse else cc)
	s.add_vertex(b if reverse else c)

static func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, tone: Color) -> void:
	_triangle(s,a,b,c,out,tone,tone,tone)
	_triangle(s,a,c,d,out,tone,tone,tone)

# A ring is (height, half width, half depth, centre Z).
static func _loft(s: SurfaceTool, rings: Array, tones: Array, offset := Vector3.ZERO, shift: Array = [], count := 14) -> void:
	var previous := PackedVector3Array()
	for j in rings.size():
		var r: Vector4 = rings[j]
		var row := PackedVector3Array()
		var x:float = 0.0 if shift.is_empty() else shift[j]
		var center := offset+Vector3(x,r.x,r.w)
		for i in count:
			var angle := TAU*i/count
			row.append(center+Vector3(sin(angle)*r.y,0,-cos(angle)*r.z))
		for i in count:
			var k := (i+1)%count
			var color: Color = tones[clampi(j-1,0,tones.size()-1)]
			if j>0:
				var outward := (row[i]+row[k])*0.5-center
				_quad(s,previous[i],row[i],row[k],previous[k],outward,color)
			if j==0 or j==rings.size()-1:
				_triangle(s,center,row[k],row[i],Vector3.DOWN if j==0 else Vector3.UP,color,color,color)
		previous = row

static func _tube(s: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, tone: Color, count := 7) -> void:
	var along := a.direction_to(b)
	var right := along.cross(Vector3.FORWARD if absf(along.z)<0.9 else Vector3.RIGHT).normalized()
	var side := right.cross(along)
	for i in count:
		var t := TAU*i/count
		var u := TAU*(i+1)/count
		var p := right*cos(t)+side*sin(t)
		var q := right*cos(u)+side*sin(u)
		_quad(s,a+ra*p,b+rb*p,b+rb*q,a+ra*q,p+q,tone)
		_triangle(s,b,b+rb*p,b+rb*q,along,tone,tone,tone)

static func _shell_point(theta: float, ring: int) -> Vector3:
	var front := maxf(0,cos(theta))
	var rear := maxf(0,-cos(theta))
	var y:float = [0.090+0.049*front-0.014*rear,0.101+0.047*front-0.012*rear,0.158+0.008*front,0.184,0.201,0.207][ring]
	var rx:float = [0.098,0.106,0.104,0.088,0.057,0.018][ring]
	var rz:float = [0.097,0.105,0.107,0.096,0.066,0.023][ring]
	var brim:float = (0.012 if ring==1 else (0.008 if ring==0 else 0.0))*pow(front,3)
	return Vector3(sin(theta)*rx,y,0.002-cos(theta)*(rz+brim))

static func _helmet(s: SurfaceTool, trim: Color) -> void:
	var shell := trim.lerp(Color("#938673"),0.22)
	var count := 24
	for i in count:
		var a := TAU*i/count
		var b := TAU*(i+1)/count
		var mid := (a+b)*0.5
		for j in 5:
			var color := shell
			if j==0:
				color = INK
			elif j==1:
				color = shell.darkened(0.05)
			_quad(s,_shell_point(a,j),_shell_point(a,j+1),_shell_point(b,j+1),_shell_point(b,j),Vector3(sin(mid),0.4,-cos(mid)),color)
		_triangle(s,Vector3(0,0.208,0.002),_shell_point(a,5),_shell_point(b,5),Vector3.UP,shell,shell,shell)
	# Four scooped intake slots lie on the crown, each following the shell.
	for theta:float in [-1.66,-0.70,0.70,1.66]:
		var a:=_shell_point(theta-0.052,3)
		var b:=_shell_point(theta+0.052,3)
		var c:=_shell_point(theta+0.075,4)
		var d:=_shell_point(theta-0.075,4)
		var lift:=Vector3(sin(theta),0.8,-cos(theta))*0.0015
		_quad(s,a.lerp(d,0.12)+lift,b.lerp(c,0.12)+lift,b.lerp(c,0.79)+lift,a.lerp(d,0.79)+lift,lift,SEAM)

static func _strap_point(theta: float, edge: float, radius: float) -> Vector3:
	return Vector3(sin(theta)*radius,0.113+edge*0.0125+0.0025*cos(theta),0.002-cos(theta)*(radius-0.001))

static func _strap(s: SurfaceTool, trim: Color) -> void:
	var start := 1.14
	for i in 24:
		var a := lerpf(start,TAU-start,float(i)/24)
		var b := lerpf(start,TAU-start,float(i+1)/24)
		var n := Vector3(sin(a),0,-cos(a))
		_quad(s,_strap_point(a,-1,0.108),_strap_point(a,1,0.108),_strap_point(b,1,0.108),_strap_point(b,-1,0.108),n,INK)
		_quad(s,_strap_point(a,-0.30,0.109),_strap_point(a,-0.09,0.109),_strap_point(b,-0.09,0.109),_strap_point(b,-0.30,0.109),n,trim.darkened(0.27))
	for angle:float in [-1.56,1.56]:
		var n:=Vector3(sin(angle),0,-cos(angle))
		_quad(s,_strap_point(angle-0.085,-1.1,0.111),_strap_point(angle-0.085,1.1,0.111),_strap_point(angle+0.085,1.1,0.111),_strap_point(angle+0.085,-1.1,0.111),n,SEAM)

static func _visor_point(u: float, v: float, lens: bool) -> Vector3:
	var theta := u*(1.23 if lens else 1.31)
	var edge := absf(u)
	var upper := 0.144-0.014*pow(edge,2.4)
	var lower := 0.079+0.023*(1.0-smoothstep(0.0,0.26,edge))+0.018*pow(edge,3.2)
	if lens:
		upper -= 0.0054+0.002*edge
		lower += 0.0046
	var depth := (0.0048 if lens else 0.0)+0.005*(1.0-pow(2*v-1.0,2))
	return Vector3(sin(theta)*(0.106+depth),lerpf(lower,upper,v),-0.007-cos(theta)*(0.113+depth))

static func _goggle_foam(s: SurfaceTool) -> void:
	# The glass stands away from the cheeks on a compressed foam seal; in
	# profile its top edge joins the helmet brim and the lower edge the face.
	for i in 20:
		var u := float(i)/10.0-1.0
		var w := float(i+1)/10.0-1.0
		var a:=_visor_point(u,1.0,false)
		var b:=_visor_point(w,1.0,false)
		var c:=_shell_point(w*1.31,0)
		var d:=_shell_point(u*1.31,0)
		_quad(s,a,b,c,d,Vector3.UP,INK)
		a=_visor_point(u,0.0,false)
		b=_visor_point(w,0.0,false)
		c=Vector3(b.x*0.85,b.y+0.004,b.z*0.76)
		d=Vector3(a.x*0.85,a.y+0.004,a.z*0.76)
		_quad(s,a,b,c,d,Vector3.DOWN,INK)

static func _reflection(u: float, p: Vector3) -> Color:
	# A reflected mountain horizon runs across the curved lens independently
	# of the nose aperture. Warm alpenglow sits on the sheltered left edge.
	var band := (p.y-0.079)/0.066 + 0.07*u
	var horizon := 0.38 + 0.048*cos(4.0*u) + 0.018*cos(10.0*u+0.7)
	var frost := Color("#9abdc0").lerp(Color("#ceb6a4"),0.34*smoothstep(0.12,0.88,-u))
	if band < horizon:
		return Color("#3e6379").lerp(frost,smoothstep(-0.03,horizon,band))
	return frost.lerp(Color("#2b384f"),smoothstep(horizon,0.89,band))

static func _visor(s: SurfaceTool, lens: bool) -> void:
	var rows := [0.0,0.21,0.43,0.55,0.82,1.0] if lens else [0.0,0.5,1.0]
	var colors := [Color("#416680"),Color("#75a8b3"),Color("#b6d0ce"),Color("#647c92"),Color("#414e69"),Color("#303e55")] if lens else [INK,INK,Color("#344857")]
	for i in 20:
		var u := float(i)/10-1.0
		var w := float(i+1)/10-1.0
		var normal := Vector3(sin(u*1.23),0,-cos(u*1.23))
		for j in range(rows.size()-1):
			var v:float=rows[j]
			var t:float=rows[j+1]
			var a:=_visor_point(u,v,lens)
			var b:=_visor_point(u,t,lens)
			var c:=_visor_point(w,t,lens)
			var d:=_visor_point(w,v,lens)
			var bottom:Color=colors[j]
			var top:Color=colors[j+1]
			if lens:
				var ca:=_reflection(u,a)
				var cb:=_reflection(u,b)
				var cc:=_reflection(w,c)
				var cd:=_reflection(w,d)
				_triangle(s,a,b,c,normal,ca,cb,cc)
				_triangle(s,a,c,d,normal,ca,cc,cd)
			else:
				_triangle(s,a,b,c,normal,bottom,top,top)
				_triangle(s,a,c,d,normal,bottom,top,bottom)

static func _gaiter(s: SurfaceTool) -> void:
	var previous := PackedVector3Array()
	for j in 4:
		var ring := PackedVector3Array()
		for i in 18:
			var angle := TAU*i/18
			var front := maxf(0.0,cos(angle))
			# Stretch fabric dips beneath the bridge at the front and wraps up
			# the cheekbones below the helmet's ear pads.
			var y:float=[-0.015,0.014,0.032+0.012*(1.0-front),0.041+0.028*(1.0-front)][j]
			var width:float=[0.052,0.062,0.071,0.080][j]
			var depth:float=[0.051,0.069,0.075,0.082][j]
			ring.append(Vector3(sin(angle)*width,y,-0.004-cos(angle)*depth))
		if j>0:
			for i in 18:
				var k:=(i+1)%18
				var radial := (ring[i]+ring[k])*0.5
				radial.y=0
				_quad(s,previous[i],ring[i],ring[k],previous[k],radial,SEAM if j==2 else INK)
		previous=ring

static func head(trim: Color, variant: int) -> Mesh:
	var key := "head"+str(variant)
	if _parts.has(key): return _parts[key]
	var s:=_surface()
	var skin:Color=[Color("#cc9074"),Color("#bb8063"),Color("#d5a284"),Color("#986955")][posmod(variant,4)]
	_loft(s,[Vector4(0.020,0.044,0.047,-0.008),Vector4(0.036,0.065,0.070,-0.005),Vector4(0.068,0.082,0.087,-0.005),Vector4(0.099,0.087,0.089,-0.006),Vector4(0.13,0.078,0.081,0.0)],[skin,skin,skin,skin])
	# Nose and the exposed upper cheeks sit below the cutout in the lens.
	var bridge:=Vector3(0,0.100,-0.093)
	var tip:=Vector3(0,0.077,-0.111)
	var left:=Vector3(-0.013,0.071,-0.094)
	var right:=Vector3(0.013,0.071,-0.094)
	_triangle(s,left,tip,bridge,Vector3.FORWARD,skin,skin.lightened(0.04),skin)
	_triangle(s,bridge,tip,right,Vector3.FORWARD,skin,skin.lightened(0.04),skin)
	_triangle(s,right,tip,left,Vector3.DOWN,skin.darkened(0.15),skin,skin.darkened(0.15))
	_gaiter(s)
	for side:float in [-1.0,1.0]:
		_loft(s,[Vector4(0.044,0.009,0.022,0.010),Vector4(0.054,0.014,0.030,0.010),Vector4(0.105,0.015,0.034,0.009),Vector4(0.115,0.008,0.028,0.009)],[INK,SEAM,INK],Vector3(side*0.086,0,0),[],10)
	_helmet(s,trim)
	_strap(s,trim)
	_goggle_foam(s)
	_visor(s,false)
	var mesh:=s.commit()
	var glass:=_surface(true)
	_visor(glass,true)
	glass.commit(mesh)
	_parts[key]=mesh
	return mesh

static func jacket(tone: Color) -> Mesh:
	var key:="coat"+tone.to_html()
	if _parts.has(key): return _parts[key]
	var s:=_surface()
	var base:=tone.darkened(0.09)
	var ring:=[Vector4(-0.005,0.107,0.080,0.014),Vector4(0.012,0.121,0.084,0.008),Vector4(0.062,0.125,0.087,0.007),Vector4(0.153,0.138,0.099,-0.002),Vector4(0.210,0.151,0.097,-0.002),Vector4(0.241,0.142,0.083,0.001),Vector4(0.272,0.069,0.062,0.004)]
	_loft(s,ring,[tone.darkened(0.24),base,tone,tone,tone.lightened(0.035),tone],Vector3.ZERO,[],16)
	_loft(s,[Vector4(0.253,0.069,0.061,0.001),Vector4(0.278,0.076,0.069,-0.001),Vector4(0.294,0.066,0.063,-0.003)],[base,tone.darkened(0.24)])
	var zipper:=tone.darkened(0.48)
	for i in range(1,ring.size()):
		var a:Vector4=ring[i-1]
		var b:Vector4=ring[i]
		_tube(s,Vector3(0,a.x,a.w-a.z-0.0015),Vector3(0,b.x,b.w-b.z-0.0015),0.0018,0.0018,zipper,5)
	for signum:float in [-1.0,1.0]:
		_tube(s,Vector3(signum*0.069,0.047,-0.065),Vector3(signum*0.092,0.089,-0.060),0.0025,0.0025,zipper,5)
	_parts[key]=s.commit()
	return _parts[key]

static func sleeve(side: float, coat:Color, on_board:bool) -> Mesh:
	var key:="arm"+str(side)+coat.to_html()+str(on_board)
	if _parts.has(key):return _parts[key]
	var s:=_surface()
	var x:=[0.063*side,0.063*side,0.073*side,0.068*side,0.041*side,0.012*side,0.0]
	_loft(s,[Vector4(-0.143,0.033,0.031,-0.082),Vector4(-0.125,0.037,0.039,-0.066),Vector4(-0.099,0.044,0.050,-0.028),Vector4(-0.078,0.046,0.044,-0.014),Vector4(-0.040,0.051,0.054,-0.004),Vector4(0.008,0.054,0.061,0.0),Vector4(0.026,0.032,0.038,0.001)],[coat.darkened(0.23),coat.darkened(0.10),coat.darkened(0.08),coat,coat,coat.lightened(0.045)],Vector3.ZERO,x,12)
	var hand:=Vector3(side*0.063,-0.151,-0.091)
	_loft(s,[Vector4(-0.026,0.019,0.023,-0.013),Vector4(-0.014,0.033,0.038,-0.011),Vector4(0.001,0.036,0.041,-0.009),Vector4(0.018,0.030,0.029,0.005)],[MITT,MITT,INK],hand,[],10)
	_loft(s,[Vector4(-0.014,0.010,0.013,-0.027),Vector4(-0.002,0.015,0.019,-0.027),Vector4(0.013,0.010,0.012,-0.020)],[MITT,MITT],hand+Vector3(-side*0.023,0,0),[],8)
	if not on_board:
		var handle:=hand+Vector3(-side*0.012,0.021,-0.008)
		var spike:=hand+Vector3(side*0.072,-0.375,0.204)
		_tube(s,handle,handle.lerp(spike,0.12),0.010,0.009,INK)
		_tube(s,handle.lerp(spike,0.11),spike,0.0055,0.0035,Color("#566978"))
		_tube(s,handle.lerp(spike,0.88),handle.lerp(spike,0.90),0.020,0.018,INK,9)
	_parts[key]=s.commit()
	return _parts[key]

static func trousers(thigh:bool) -> Mesh:
	var key := "thigh" if thigh else "shin"
	if _parts.has(key):return _parts[key]
	var s:=_surface()
	var navy:=Color("#384c60")
	var width:=0.55 if thigh else 0.49
	_loft(s,[Vector4(-0.56,0.42,0.43,0.0),Vector4(-0.43,0.49,0.47,0.0),Vector4(0.24,width,0.53,0.0),Vector4(0.52,width*0.91,0.46,0.0),Vector4(0.59,0.34,0.35,0.0)],[navy.darkened(0.10),navy,navy,navy.darkened(0.05)],Vector3.ZERO,[],10)
	_parts[key]=s.commit()
	return _parts[key]

static func ski(trim: Color) -> Mesh:
	var key:="ski"+trim.to_html()
	if _parts.has(key):return _parts[key]
	var s:=_surface()
	var deck:=Color("#364c5c")
	# Variable sidecut, raised shovel, little upturn at the tail.
	var sections:=[Vector3(-0.539,0.009,0.074),Vector3(-0.521,0.036,0.066),Vector3(-0.487,0.053,0.046),Vector3(-0.423,0.052,0.030),Vector3(-0.38,0.049,0.021),Vector3(-0.29,0.044,0.018),Vector3(0.0,0.036,0.019),Vector3(0.22,0.042,0.017),Vector3(0.359,0.049,0.019),Vector3(0.438,0.046,0.030),Vector3(0.455,0.034,0.035)]
	for i in range(1,sections.size()):
		var p:Vector3=sections[i-1];var q:Vector3=sections[i]
		var a:=Vector3(-p.y,p.z,p.x);var b:=Vector3(p.y,p.z,p.x)
		var c:=Vector3(q.y,q.z,q.x);var d:=Vector3(-q.y,q.z,q.x)
		var down:=Vector3.DOWN*0.012
		var color:=trim if i<4 else (deck.lightened(0.35) if i==4 else deck)
		_quad(s,a,b,c,d,Vector3.UP,color)
		_quad(s,a+down,d+down,c+down,b+down,Vector3.DOWN,INK)
		_quad(s,a,d,d+down,a+down,Vector3.LEFT,INK)
		_quad(s,b,b+down,c+down,c,Vector3.RIGHT,INK)
		if i==1:_quad(s,a,a+down,b+down,b,Vector3.FORWARD,INK)
		if i==sections.size()-1:_quad(s,c,c+down,d+down,d,Vector3.BACK,INK)
	# Rounded ski boot shell, lifting heel cup and a pair of buckles; these
	# move with the deck and their shins bend independently above the cuff.
	_loft(s,[Vector4(0.019,0.048,0.102,-0.014),Vector4(0.042,0.054,0.104,-0.014),Vector4(0.067,0.050,0.094,-0.015),Vector4(0.103,0.048,0.058,0.018),Vector4(0.147,0.049,0.055,0.023),Vector4(0.157,0.039,0.043,0.022)],[INK,SEAM,MITT,SEAM,INK],Vector3.ZERO,[],12)
	for y:float in [0.080,0.113]:
		var z:float=-0.049 if y<0.10 else -0.033
		_tube(s,Vector3(-0.029,y,z),Vector3(0.030,y+0.003,z),0.005,0.005,Color("#9ba7a9"),6)
	_parts[key]=s.commit()
	return _parts[key]
