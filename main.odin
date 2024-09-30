package odinrc

import d "../dengine/dengine"
import "base:runtime"
import "core:fmt"
import glfw "vendor:glfw"
import wgpu "vendor:wgpu"

print :: fmt.println
UVec2 :: [2]u32
IVec2 :: [2]int
Vec2 :: [2]f32
INITIAL_SIZE :: UVec2{800, 500}
Texture :: d.Texture
RgbaU8 :: [4]u8


main :: proc() {
	app: App
	app_create(&app)
	defer {
		app_destroy(&app)
	}

	for app_start_frame(&app) {
		app_update(&app)
		app_end_frame(&app)
	}
}


App :: struct {
	pl:                   d.Platform,
	ui_renderer:          d.UiRenderer,
	drawn_image:          DrawnImage,
	drawn_image_pipeline: d.RenderPipeline,
	draw_radius:          int,
}

app_update :: proc(app: ^App) {
	cursor_px_pos := cursor_pos_to_px_pos_in_image(app.pl.cursor_pos, app.pl.screen_size_f32)
	last_cursor_px_pos := cursor_pos_to_px_pos_in_image(
		app.pl.cursor_pos - app.pl.cursor_delta,
		app.pl.screen_size_f32,
	)

	d.start_window("Example Window")
	btn_text := "Hold to Record"

	d.button(btn_text, id = "record_btn")
	d.text("fovy_y")
	d.end_window()
	if .Pressed in app.pl.mouse_buttons[.Left] {
		draw_line_from_to(&app.drawn_image, cursor_px_pos, last_cursor_px_pos, {0, 0, 0, 255})
	} else if .Pressed in app.pl.mouse_buttons[.Right] {
		draw_line_from_to(&app.drawn_image, cursor_px_pos, last_cursor_px_pos, {0, 0, 0, 0})
	}
}


draw_line_from_to :: proc(img: ^DrawnImage, from: IVec2, to: IVec2, color: RgbaU8) {
	pxs := make([dynamic]IVec2, allocator = context.temp_allocator)
	diff := from - to

	p1 := from
	p2 := to
	if abs(diff.x) > abs(diff.y) { 	// horizontal sweep:
		if p1.x > p2.x {
			p1, p2 = p2, p1
		}
		for x in p1.x ..= p2.x {
			f := (f32(x) - f32(p1.x)) / (f32(p2.x) - f32(p1.x))
			y := int(f32(p1.y) + f * (f32(p2.y) - f32(p1.y)))
			append(&pxs, IVec2{x, y})
		}
	} else { 	// vertical sweep:
		if p1.y > p2.y {
			p1, p2 = p2, p1
		}
		for y in p1.y ..= p2.y {
			f := (f32(y) - f32(p1.y)) / (f32(p2.y) - f32(p1.y))
			x := int(f32(p1.x) + f * (f32(p2.x) - f32(p1.x)))
			append(&pxs, IVec2{x, y})
		}
	}

	RADIUS :: 4
	for px_on_line in pxs {
		for i in -RADIUS ..= RADIUS {
			for j in -RADIUS ..= RADIUS {
				if i * i + j * j <= RADIUS * RADIUS {
					px := px_on_line + IVec2{i, j}
					is_in_bounds :=
						px.x >= 0 &&
						px.x < DRAWN_IMAGE_SIZE &&
						px.y >= 0 &&
						px.y < DRAWN_IMAGE_SIZE
					if is_in_bounds {
						img.pixels[px.x + px.y * DRAWN_IMAGE_SIZE] = color
						img.dirty = true
					}
				}
			}
		}
	}


}

app_start_frame :: proc(app: ^App) -> bool {
	if !d.platform_start_frame(&app.pl) {
		return false
	}
	d.ui_renderer_start_frame(&app.ui_renderer, app.pl.screen_size_f32, &app.pl)
	return true
}

app_end_frame :: proc(app: ^App) {
	if app.pl.screen_resized {
		d.platform_resize(&app.pl)
	}
	d.platform_reset_input_at_end_of_frame(&app.pl)
	// PREPARE
	d.platform_prepare(&app.pl)
	if app.drawn_image.dirty {
		drawn_image_write_texture(app.drawn_image, app.pl.queue)
	}
	d.ui_renderer_end_frame_and_prepare_buffers(
		&app.ui_renderer,
		app.pl.delta_secs,
		app.pl.asset_manager,
	)
	// RENDER
	globals_bind_group := app.pl.globals.bind_group
	surface_texture, surface_view, command_encoder := d.platform_start_render(&app.pl)
	hdr_pass := d.platform_start_hdr_pass(app.pl, command_encoder)
	d.ui_renderer_render(
		&app.ui_renderer,
		hdr_pass,
		globals_bind_group,
		app.pl.screen_size,
		app.pl.asset_manager,
	)

	wgpu.RenderPassEncoderSetPipeline(hdr_pass, app.drawn_image_pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(hdr_pass, 0, globals_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(hdr_pass, 1, app.drawn_image.texture.bind_group)
	wgpu.RenderPassEncoderDraw(hdr_pass, 4, 1, 0, 0)

	wgpu.RenderPassEncoderEnd(hdr_pass)
	wgpu.RenderPassEncoderRelease(hdr_pass)

	d.platform_end_render(&app.pl, surface_texture, surface_view, command_encoder)
	// END
	free_all(context.temp_allocator)
}

app_create :: proc(app: ^App) {
	PLATFORM_SETTINGS :: d.PlatformSettings {
		title              = "Dplatform",
		initial_size       = {1024, 512},
		clear_color        = d.Color_Dark_Gray,
		shaders_dir_path   = "./shaders",
		default_font_path  = "./assets/marko_one_regular",
		power_preference   = .LowPower,
		present_mode       = .Fifo,
		tonemapping        = .Disabled,
		debug_fps_in_title = true,
		hot_reload_shaders = true,
	}
	d.platform_create(&app.pl, PLATFORM_SETTINGS)
	// print(app.pl.shader_registry)
	d.ui_renderer_create(&app.ui_renderer, &app.pl, {1, 1, 1, 1}, 16)
	app.drawn_image = drawn_image_create(app.pl)
	drawn_image_write_texture(app.drawn_image, app.pl.queue)
	app.drawn_image_pipeline.config = drawn_image_pipeline_config(
		app.pl.device,
		app.pl.globals.bind_group_layout,
	)
	d.render_pipeline_create_panic(&app.drawn_image_pipeline, &app.pl.shader_registry)
}

app_destroy :: proc(app: ^App) {
	d.platform_destroy(&app.pl)
	d.ui_renderer_destroy(&app.ui_renderer)
}

DrawnImage :: struct {
	size:    UVec2,
	pixels:  [dynamic]RgbaU8,
	dirty:   bool,
	texture: Texture,
}
DRAWN_IMAGE_SIZE :: 1024
drawn_image_create :: proc(platform: d.Platform) -> DrawnImage {
	size := UVec2{DRAWN_IMAGE_SIZE, DRAWN_IMAGE_SIZE}
	pixels := make([dynamic]RgbaU8, int(size.x * size.y))
	for &pix, i in pixels {
		if i % 3 == 2 {
			pix = {50, 120, 244, 255}
		} else if i % 13 == 0 {
			pix = {50, 255, 0, 255}
		}
	}
	texture := d.texture_create(
		platform.device,
		size,
		d.TextureSettings {
			label = "",
			format = wgpu.TextureFormat.RGBA8Unorm,
			address_mode = .ClampToEdge,
			mag_filter = .Nearest,
			min_filter = .Nearest,
			usage = {.TextureBinding, .CopyDst},
		},
	)
	return DrawnImage{size = size, pixels = pixels, dirty = true, texture = texture}
}

drawn_image_write_texture :: proc(img: DrawnImage, queue: wgpu.Queue) {
	COPY_BYTES_PER_ROW_ALIGNMENT: u32 : 256 // Buffer-Texture copies must have [`bytes_per_row`] aligned to this number.
	block_size: u32 = 4
	bytes_per_row :=
		((img.size.x * block_size + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &
			~(COPY_BYTES_PER_ROW_ALIGNMENT - 1))
	image_copy := wgpu.ImageCopyTexture {
		texture  = img.texture.texture,
		mipLevel = 0,
		origin   = {0, 0, 0},
		aspect   = .All,
	}
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = img.size.y,
	}
	wgpu.QueueWriteTexture(
		queue,
		&image_copy,
		raw_data(img.pixels),
		uint(len(img.pixels) * 4),
		&data_layout,
		&wgpu.Extent3D{width = img.size.x, height = img.size.y, depthOrArrayLayers = 1},
	)
}

drawn_image_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> d.RenderPipelineConfig {
	return d.RenderPipelineConfig {
		debug_name = "drawn_image",
		vs_shader = "drawn_image",
		vs_entry_point = "vs_main",
		fs_shader = "drawn_image",
		fs_entry_point = "fs_main",
		topology = .TriangleStrip,
		vertex = {},
		instance = {},
		bind_group_layouts = {globals_layout, d.rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = d.ALPHA_BLENDING,
		format = d.HDR_FORMAT,
	}
}


NOT_IN_IMAGE :: IVec2{-1, -1}
cursor_pos_to_px_pos_in_image :: proc(cursor_pos: Vec2, screen_size: Vec2) -> IVec2 {
	screen_px_per_img_px := screen_size.y / DRAWN_IMAGE_SIZE
	top_left_img_corner_in_screen := Vec2{screen_size.x / 2 - screen_size.y / 2, 0}
	px_pos_in_img := (cursor_pos - top_left_img_corner_in_screen) / screen_px_per_img_px
	rounded := IVec2{int(px_pos_in_img.x), int(px_pos_in_img.y)}
	return rounded
}
