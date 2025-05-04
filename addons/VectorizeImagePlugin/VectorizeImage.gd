@tool
@icon('res://addons/VectorizeImagePlugin/blue-up-right-arrow.svg')

extends MeshInstance2D
class_name VectorizeImage

@export 
var texture_image: Texture2D

@export_group("General")

@export_range(1.0, 20.0, 0.1)  
var down_scale_multiplier: float ## Reduces the input image resolution before processing. Higher values simplify shapes and improve performance.

@export_enum("Random", "Edge", "Segment") 
var generation_mode: int ## Selects the algorithm for generating dots and triangulation.

## Controls how color is applied: "Single" uses one color from the center of the triangle, "Blend" averages between vertices.
@export_enum("Blend", "Single") var color: int

@export_group("Generation Mode Options")

@export_subgroup("Random")

## Controls the approximate distance between randomly placed dots. Lower values result in more dots.
@export var random_spacing: int

@export_subgroup("Edge")

## Minimum value to consider a pixel an edge. Higher values result in narrower edges.
@export_range(0.0, 1.0, 0.01) var edge_threshold: float

@export_subgroup("Segment")

## Minimum value to consider a pixel an edge.
@export_range(0.0, 1.0, 0.0001) var segment_threshold: float

@export_subgroup("Edge and Segment")

## Minimum difference between colors to detect a transition between colors.
@export_range(0.0, 2.0, 0.01) var color_contrast_threshold: float

## Controls how frequently dots are placed in non-edge areas. Lower values increase edge dot density.
@export var dot_spacing: int

@export_group("Vectorizing")

## Generates and displays a triangulated mesh from the dot pattern based on the selected algorithm and parameters.
@export var Generate: bool = false : set = set_mesh_instance_mesh         

func in_same_direction( dir_x: int, dir_y: int, threshold: float, x: int, y: int, sobel_rows: Array, image_x: int, image_y: int, direction: Vector2 ):
	var temp_x = x + dir_x * -1
	var temp_y = y + dir_y * -1
	if(temp_x >= 0 and temp_x < image_x and temp_y >= 0 and temp_y < image_y):
		var color2 = sobel_rows[temp_y][temp_x]
		var direction2 = Vector2(color2.r - 0.5, color2.g - 0.5) * 2.0
		
		if( direction.dot(direction2) > color_contrast_threshold ):
			return true
	return false

func get_sobel_texture(texture: Texture2D) -> Texture2D:
	var subviewport = SubViewport.new()
	subviewport.size = texture.get_size()
	subviewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	
	add_child(subviewport)
	
	var script_path = get_script().resource_path
	var folder_path = script_path.get_base_dir()
	var shader = load(folder_path + "/sobel_shader.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader

	var texture_rect = TextureRect.new()
	texture_rect.texture = texture
	texture_rect.size = texture.get_size()
	texture_rect.material = shader_material
	
	
	subviewport.add_child(texture_rect)
	
	await get_tree().create_timer(0.5).timeout
	
	var sobel_texture = subviewport.get_texture()
	subviewport.queue_free()
	return sobel_texture

func add_color(color_array: PackedColorArray, color: Color) -> PackedColorArray:
	color_array.push_back(color)
	color_array.push_back(color)
	color_array.push_back(color)
	return color_array

func add_index(index_array: PackedInt32Array, index: int) -> PackedInt32Array:
	index_array.push_back(index)
	index_array.push_back(index + 1)
	index_array.push_back(index + 2)
	return index_array

func segment_sobel_image(sobel_rows: Array, dots_in_block: int) -> Dictionary:
	var index = 1
	var dict = {}
	var dict_pixels = {}
	var pixel_group = []
	
	for i in range(sobel_rows.size()):
		pixel_group.append([])
		for j in range(sobel_rows[i].size()):
			pixel_group[i].append(0)
			var color = sobel_rows[i][j] as Color
			var direction = Vector2(color.r - 0.5, color.g - 0.5)
			var updated = false # Variable to check if pixel group and current location was changed
			if(i > 0):
				var u_color = sobel_rows[i-1][j] as Color
				var u_direction = Vector2(u_color.r - 0.5, u_color.g - 0.5)
				var u_group = "g_"+str(pixel_group[i-1][j])
				# Adding up group to current
				var isEdgeCurrent: bool = direction.length_squared() >= segment_threshold
				var isEdgeAbove: bool = u_direction.length_squared() >= segment_threshold
				var isSameColor: bool = direction.dot(u_direction) > color_contrast_threshold
				#if( direction.dot(u_direction) > edge_contrast_threshold or ( !(direction.length_squared() >= segment_threshold) and !(u_direction.length_squared() >= segment_threshold) ) ):
				if( (isEdgeCurrent and isEdgeAbove and isSameColor) or (!isEdgeCurrent and !isEdgeAbove) ):
					pixel_group[i][j] = pixel_group[i-1][j]
					var group = "p_"+str(pixel_group[i][j])
					dict_pixels[group].push_back(Vector2(j, i))
					updated = true
				
			if(j > 0):
				var l_color = sobel_rows[i][j-1] as Color
				var l_direction = Vector2(l_color.r - 0.5, l_color.g - 0.5)
				var isEdgeCurrent: bool = direction.length_squared() >= segment_threshold
				var isEdgeLeft: bool = l_direction.length_squared() >= segment_threshold
				var isSameColor: bool = direction.dot(l_direction) > color_contrast_threshold
				if( (isEdgeCurrent and isEdgeLeft and isSameColor) or (!isEdgeCurrent and !isEdgeLeft) ):
				#if( direction.dot(l_direction) > edge_contrast_threshold or ( !(direction.length_squared() >= segment_threshold) and !(l_direction.length_squared() >= segment_threshold) ) ):
					# Merging
					if(updated and pixel_group[i-1][j] != pixel_group[i][j-1]):
						var u_color = sobel_rows[i-1][j] as Color
						var u_direction = Vector2(u_color.r - 0.5, u_color.g - 0.5)
						var isEdgeAbove: bool = u_direction.length_squared() >= segment_threshold
						var isSameColorAboveAndLeft: bool = u_direction.dot(l_direction) > color_contrast_threshold
						if( (isEdgeLeft and isEdgeAbove and isSameColorAboveAndLeft) or (!isEdgeAbove and !isEdgeLeft) ):
						#if( l_direction.dot(u_direction) > edge_contrast_threshold or ( !(u_direction.length_squared() >= segment_threshold) and !(l_direction.length_squared() >= segment_threshold) ) ):
							var p_group1 = "p_"+str(pixel_group[i-1][j])
							var p_group2 = "p_"+str(pixel_group[i][j-1])
							
							for pixel in dict_pixels[p_group1]:
								var x = pixel.x
								var y = pixel.y
								pixel_group[y][x] = pixel_group[i][j-1]
								dict_pixels[p_group2].push_back(Vector2(x, y))
								
							dict_pixels.erase(p_group1)
										
					# Adding left group to current
					elif(!updated):
						pixel_group[i][j] = pixel_group[i][j-1]
						var group = "p_"+str(pixel_group[i][j])
						dict_pixels[group].push_back(Vector2(j, i))
						updated = true
			if(!updated):
				var array = PackedVector2Array()
				array.push_back(Vector2(j, i))
				var group = "p_"+str(index)
				dict_pixels[group] = array
				pixel_group[i][j] = index
				index += 1
	var current_group = 0
	var finished_groups = []
	var count = 0
	for i in range(pixel_group.size()):
		for j in range(pixel_group[i].size()):
			current_group = pixel_group[i][j]
			var group = "g_"+str(current_group)
			
			if(pixel_group[i][j] not in finished_groups):
				count = 0
				var array = PackedVector2Array()
				dict[group] = array
				finished_groups.append(current_group)
				var from = 0 
				var current_location = Vector2(j, i)
				var start_location = current_location
				while(true):
					var x = current_location.x
					var y = current_location.y
					if(from == 0 or from == 1): 
						if(y > 0 and current_group == pixel_group[y-1][x]):
							dict[group].push_back(Vector2(x, y))
							current_location = Vector2(x, y-1)
							from = 4
						elif(x < pixel_group[i].size()-1 and current_group == pixel_group[y][x+1]):
							if(from == 0):
								dict[group].push_back(Vector2(x, y+1))
								dict[group].push_back(Vector2(x, y))
							dict[group].push_back(Vector2(x+0.5, y))
							current_location = Vector2(x+1, y)
							from = 1
						elif(y < pixel_group.size()-1 and current_group == pixel_group[y+1][x]):
							if(from == 0):
								dict[group].push_back(Vector2(x, y))
							dict[group].push_back(Vector2(x+1, y))
							current_location = Vector2(x, y+1)
							from = 2
						else:
							dict[group].push_back(Vector2(x+1, y))
							dict[group].push_back(Vector2(x+1, y+1))
							if(from == 0):
								dict[group].push_back(Vector2(x, y+1))
								dict[group].push_back(Vector2(x, y))
								break
							else:
								current_location = Vector2(x-1, y)
							from = 3
							
					elif(from == 2):
						if(x < pixel_group[i].size()-1 and current_group == pixel_group[y][x+1]):
							dict[group].push_back(Vector2(x+1, y))
							current_location = Vector2(x+1, y)
							from = 1
						elif(y < pixel_group.size()-1 and current_group == pixel_group[y+1][x]):
							dict[group].push_back(Vector2(x+1, y+0.5))
							current_location = Vector2(x, y+1)
							from = 2
						elif(x > 0 and current_group == pixel_group[y][x-1]):
							dict[group].push_back(Vector2(x+1, y+1))
							current_location = Vector2(x-1, y)
							from = 3
						else:
							dict[group].push_back(Vector2(x+1, y+1))
							dict[group].push_back(Vector2(x, y+1))
							current_location = Vector2(x, y-1)
							from = 4
							
					elif(from == 3):
						if(y < pixel_group.size()-1 and current_group == pixel_group[y+1][x]):
							dict[group].push_back(Vector2(x+1, y+1))
							current_location = Vector2(x, y+1)
							from = 2
						elif(x > 0 and current_group == pixel_group[y][x-1]):
							dict[group].push_back(Vector2(x+0.5, y+1))
							current_location = Vector2(x-1, y)
							from = 3
						elif(y > 0 and current_group == pixel_group[y-1][x]):
							dict[group].push_back(Vector2(x, y+1))
							current_location = Vector2(x, y-1)
							from = 4
						else:
							if(current_location == start_location):
								break
							dict[group].push_back(Vector2(x, y+1))
							dict[group].push_back(Vector2(x, y))
							current_location = Vector2(x+1, y)
							from = 1
							
					elif(from == 4):
						if(x > 0 and current_group == pixel_group[y][x-1]):
							dict[group].push_back(Vector2(x, y+1))
							current_location = Vector2(x-1, y)
							from = 3
						elif(y > 0 and current_group == pixel_group[y-1][x]):
							dict[group].push_back(Vector2(x, y+0.5))
							current_location = Vector2(x, y-1)
							from = 4
						elif(x < pixel_group[i].size()-1 and current_group == pixel_group[y][x+1]):
							if(current_location == start_location):
								break
							dict[group].push_back(Vector2(x, y))
							current_location = Vector2(x+1, y)
							from = 1
						else:
							if(current_location == start_location):
								break
							dict[group].push_back(Vector2(x, y))
							dict[group].push_back(Vector2(x+1, y))
							current_location = Vector2(x, y+1)
							from = 2
			elif(dot_spacing > 0 and Vector2(j, i) not in dict[group] and count >= dot_spacing) and j % ceili(dot_spacing/ randf_range(1.0, 5.0) ) == 0:
				count = 0
				dict[group].push_back(Vector2(j, i))
			else:
				count += randi_range(1, 5)
				
	dict['pixels'] = pixel_group
	return dict 

func random_dots(image_x: int, image_y: int, dots_in_block: int, rows: Array) -> Array:
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	var verts = PackedVector3Array()
	var indices = PackedInt32Array()
	var colors = PackedColorArray()
	
	var vertsIndex = 0
	
	while (image_x - 1) % (dots_in_block + 1) != 0:
		image_x -= 1
	while (image_y - 1) % (dots_in_block + 1) != 0:
		image_y -= 1
	
	var blocks_in_row = (image_x - 1) / (dots_in_block + 1)
	var blocks_in_column = (image_y - 1) / (dots_in_block + 1)
	
	# First row dots
	var dots = []
	for i in range(0, image_x, dots_in_block + 1):
		dots.push_back(Vector3(i, 0, 0))
	dots.push_back(Vector3(image_x-1, 0, 0))
	
	# Middle dots
	var pos_y = 1
	for j in range(blocks_in_column):
		dots.push_back(Vector3(0, pos_y - 1, 0))
		var pos_x = 1
		for i in range(blocks_in_row):
			var x = randi_range(pos_x, pos_x + (dots_in_block - 1))
			var y = randi_range(pos_y, pos_y + (dots_in_block - 1))
			pos_x += dots_in_block + 1
			dots.push_back(Vector3(x, y, 0))
		dots.push_back(Vector3(image_x-1, pos_y + 1, 0))
		pos_y += dots_in_block + 1
		
	# Last row dots
	for i in range(0, image_x, dots_in_block + 1):
		dots.push_back(Vector3(i, image_y-1, 0))
	dots.push_back(Vector3(image_x-1, image_y-1, 0))
	
	var triangles = Geometry2D.triangulate_delaunay(dots)
	for k in range(0, triangles.size(), 3):
		var a = dots[triangles[k]]
		var b = dots[triangles[k + 1]]
		var c = dots[triangles[k + 2]]
		
		verts.push_back(Vector3(a.x, a.y, 0))
		verts.push_back(Vector3(b.x, b.y, 0))
		verts.push_back(Vector3(c.x, c.y, 0))
		
		if(color == 0):
			colors.push_back(rows[a.y-0.5][a.x-0.5])
			colors.push_back(rows[b.y-0.5][b.x-0.5])
			colors.push_back(rows[c.y-0.5][c.x-0.5])
			
		elif(color == 1):
			var color_x = floor((a.x + b.x + c.x) / 3)
			var color_y = floor((a.y + b.y + c.y) / 3)
			var color = rows[color_y][color_x]
			colors = add_color(colors, color)
		
		indices = add_index(indices, vertsIndex)
		vertsIndex = vertsIndex + 3
	
	# Add updated arrays to surface_array and create a mesh
	surface_array[Mesh.ARRAY_VERTEX] = verts
	surface_array[Mesh.ARRAY_INDEX] = indices
	surface_array[Mesh.ARRAY_COLOR] = colors
			
	return surface_array	

func sobel_edge(image_x: int, image_y: int, rows: Array, sobel_rows: Array) -> Array:
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	var verts = PackedVector3Array()
	var indices = PackedInt32Array()
	var colors = PackedColorArray()
	var dots = PackedVector2Array()
	
	var vertsIndex = 0
	
	var start_dots = Time.get_ticks_usec()
	
	dots.push_back(Vector2(0, 0))
	dots.push_back(Vector2(image_x-1, 0))
	dots.push_back(Vector2(0, image_y/2))
	
	# Dots on the image based on sobel data
	var count = 0
	for y in range(0, image_y):
		var i = 0
		for x in range(i, image_x):
			var color = sobel_rows[y][x]
			var direction = Vector2(color.r - 0.5, color.g - 0.5) * 2.0
			var dir_x = 0
			var dir_y = 0
			
			var threshold = edge_threshold
			if( direction.x > threshold ):
				dir_x = 1
			elif( direction.x < -threshold ):
				dir_x = -1
				
			if( direction.y > threshold ):
				dir_y = 1
			elif( direction.y < -threshold ):
				dir_y = -1
				
			if( dir_x != 0 or dir_y != 0 ):
				count = 0
				if( !in_same_direction(dir_x, dir_y, threshold, x, y, sobel_rows, image_x, image_y, direction) ):
					dots.push_back(Vector2(x, y))
			elif(dot_spacing > 0 and count >= dot_spacing and x % ceili(dot_spacing/ randf_range(1.0, 5.0) ) == 0):
				count = 0
				dots.push_back(Vector2(x, y))
			else:
				count += randi_range(1, 5)
				
				
	
	dots.push_back(Vector2(image_x-1, image_y/2))
	dots.push_back(Vector2(0, image_y-1))
	dots.push_back(Vector2(image_x-1, image_y-1))
		
	var end_dots = Time.get_ticks_usec()
	var duration_ms_dots = (end_dots - start_dots) / 1000.0
	
	var start_tri = Time.get_ticks_usec()
	# Set verts, colors and indices based on triangles found using triangulate_delaunay.
	var triangles = Geometry2D.triangulate_delaunay(dots)
	var end_tri = Time.get_ticks_usec()
	var duration_ms_tri = (end_tri - start_tri) / 1000.0
	for k in range(0, triangles.size(), 3):
		var a = dots[triangles[k]]
		var b = dots[triangles[k + 1]]
		var c = dots[triangles[k + 2]]
		
		verts.push_back(Vector3(a.x, a.y, 0))
		verts.push_back(Vector3(b.x, b.y, 0))
		verts.push_back(Vector3(c.x, c.y, 0))
		
		if(color == 0):
			colors.push_back(rows[a.y-0.5][a.x-0.5])
			colors.push_back(rows[b.y-0.5][b.x-0.5])
			colors.push_back(rows[c.y-0.5][c.x-0.5])
			
		elif(color == 1):
			var color_x = floor((a.x + b.x + c.x) / 3)
			var color_y = floor((a.y + b.y + c.y) / 3)
			var color = rows[color_y][color_x]
			colors = add_color(colors, color)
		
		indices = add_index(indices, vertsIndex)
		vertsIndex = vertsIndex + 3
	
	# Add updated arrays to surface_array and create a mesh
	surface_array[Mesh.ARRAY_VERTEX] = verts
	surface_array[Mesh.ARRAY_INDEX] = indices
	surface_array[Mesh.ARRAY_COLOR] = colors
			
	return surface_array

func segmenting(image_x: int, image_y: int, dots_in_block: int, rows: Array, sobel_rows: Array) -> Array:
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	var segments = segment_sobel_image( sobel_rows, dots_in_block )
	
	var verts = PackedVector3Array()
	var indices = PackedInt32Array()
	var colors = PackedColorArray()
	var dots = PackedVector2Array()
	
	var vertsIndex = 0
	var pixel_group = segments['pixels']
	# Set verts, colors and indices based on triangles found using triangulate_delaunay.
	for i in range(segments.keys().size()-1):
		var segment = segments.values()[i]
		var key = segments.keys()[i]
		var group_nr = int(key.replace("g_", ""))
		var triangles = []
		triangles = Geometry2D.triangulate_delaunay(segment)
		if(triangles.size() < 2):
			continue
		for k in range(0, triangles.size(), 3):
			var a = segment[triangles[k]]
			var b = segment[triangles[k + 1]]
			var c = segment[triangles[k + 2]]
			
			var center = Vector2((floori(a.x + b.x + c.x) / 3.0),  (floori(a.y + b.y + c.y) / 3.0))
			if(pixel_group[center.y][center.x] != group_nr):
				continue
			
			verts.push_back(Vector3(a.x, a.y, 0))
			verts.push_back(Vector3(b.x, b.y, 0))
			verts.push_back(Vector3(c.x, c.y, 0))
			
			if(color == 0):
				colors.push_back(rows[a.y-0.5][a.x-0.5])
				colors.push_back(rows[b.y-0.5][b.x-0.5])
				colors.push_back(rows[c.y-0.5][c.x-0.5])
				
			elif(color == 1):
				var color_x = floori((a.x + b.x + c.x) / 3.0)
				var color_y = floori((a.y + b.y + c.y) / 3.0)
				var color = rows[color_y][color_x]
				colors = add_color(colors, color)
			
			indices = add_index(indices, vertsIndex)
			vertsIndex = vertsIndex + 3
	
	# Add updated arrays to surface_array and create a mesh
	surface_array[Mesh.ARRAY_VERTEX] = verts
	surface_array[Mesh.ARRAY_INDEX] = indices
	surface_array[Mesh.ARRAY_COLOR] = colors
			
	return surface_array

func set_mesh_instance_mesh(new_value: bool):
	print("CPU Architecture: ", OS.get_processor_name())
	print("CPU Threads: ", OS.get_processor_count())
	print("Platform: ", OS.get_name())
	for child in get_children():
		if child is Polygon2D or child is Line2D:
			child.queue_free()
	var start = Time.get_ticks_usec()
	var texture_image = texture_image.duplicate() as Texture2D
	if texture_image as Texture2D:
		print('Vectorization start!')
		# Get image and image size
		var image = texture_image.get_image()
		var image_size = image.get_size()
		
		# Change image size based on dots_in_block (nr of pixels in one block)
		var dots_in_block = random_spacing
		var image_x = image_size.x
		var image_y = image_size.y
		
		image_x = roundi(image_x / down_scale_multiplier)
		image_y = roundi(image_y / down_scale_multiplier)
		
		if(generation_mode == 0):
			while (image_x - 1) % (dots_in_block + 1) != 0:
				image_x -= 1
			while (image_y - 1) % (dots_in_block + 1) != 0:
				image_y -= 1
			
		image.resize(image_x, image_y)
		print("Image size: ", image_size)
		# Get normal image pixel data after resizing
		var pixel_data = image.get_data()

		var sobel_data = null
		var sobel_image = null
		var sobel_texture = null
		# Get Sobel data
		if(generation_mode != 0):
			var resized_texture = ImageTexture.create_from_image(image)
			sobel_texture = await get_sobel_texture(resized_texture)
			sobel_image = sobel_texture.get_image()
			sobel_data = sobel_image.get_data()
		
		
		# Convert pixel data into array of PackedColorArrays
		var rows = []
		for y in range(image_y):
			var packed_row = PackedColorArray()
			for x in range(image_x):
				var pixel_index = (y * image_x + x) * 3
				var r = pixel_data[pixel_index]
				var g = pixel_data[pixel_index + 1]
				var b = pixel_data[pixel_index + 2]
				packed_row.push_back(Color8(r, g, b))
			rows.append(packed_row)
		
		# Convert sobel data into array of PackedColorArrays
		var sobel_rows = []
		if(generation_mode != 0):
			for y in range(image_y):
				var packed_row = PackedColorArray()
				for x in range(image_x):
					var pixel_index = (y * image_x + x) * 3
					var r = sobel_data[pixel_index]
					var g = sobel_data[pixel_index + 1]
					var b = sobel_data[pixel_index + 2]
					packed_row.push_back(Color8(r, g, b))
				sobel_rows.append(packed_row)
		
		# Mesh creation
		var newmesh = ArrayMesh.new()
		var surface_array = []
		
		var start_gen = Time.get_ticks_usec()
		if(generation_mode == 0):
			surface_array = random_dots(image_x, image_y, dots_in_block, rows)
		elif(generation_mode == 1):
			surface_array = sobel_edge(image_x, image_y, rows, sobel_rows)
		elif(generation_mode == 2): 
			surface_array = segmenting(image_x, image_y, dots_in_block, rows, sobel_rows)
			
		var end_gen = Time.get_ticks_usec()
		var duration_ms_gen = (end_gen - start_gen) / 1000.0
		
		newmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
		self.set_mesh(newmesh)
		print("Vectorized!")
		var end = Time.get_ticks_usec()
		var duration_ms = round( (end - start) / 1000.0 )
		print("Algorithm took: %.3f ms" % duration_ms)
