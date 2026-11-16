extends Texture2D

# ENHANCED : a picture that keeps the original size (so every position, region and
# collision of the game stays in the original pixels) and draws either the original or its
# xBRZ enlargement (assets_hd, factor times larger, linear filtering), as `on` says. The
# switch is immediate, nothing is loaded again. For the detail to show, the canvas must be
# drawn at the window's resolution (content scale mode canvas_items, main.gd _set_enhanced).

static var on := false

var base: Texture2D
var hd: CanvasTexture
var factor := 1.0


func _init(original: Texture2D, large: Texture2D) -> void:
	base = original
	factor = float(large.get_width()) / original.get_width()
	hd = CanvasTexture.new()
	hd.diffuse_texture = large
	hd.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _get_width() -> int:
	return base.get_width()


func _get_height() -> int:
	return base.get_height()


func _has_alpha() -> bool:
	return base.has_alpha()


func _is_pixel_opaque(_x: int, _y: int) -> bool:
	return true


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	var rid := hd.get_rid() if on else base.get_rid()
	RenderingServer.canvas_item_add_texture_rect(to_canvas_item, Rect2(pos, base.get_size()), rid, false, modulate, transpose)


func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	var rid := hd.get_rid() if on else base.get_rid()
	RenderingServer.canvas_item_add_texture_rect(to_canvas_item, rect, rid, tile, modulate, transpose)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	if on:
		var region := Rect2(src_rect.position * factor, src_rect.size * factor)
		RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, rect, hd.get_rid(), region, modulate, transpose, clip_uv)
	else:
		RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, rect, base.get_rid(), src_rect, modulate, transpose, clip_uv)
