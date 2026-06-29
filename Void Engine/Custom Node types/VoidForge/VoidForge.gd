@tool
extends Control

const DATA_FILE = "user://voidforge_data.json"

# --- PURE BLACK & RED THEME ---
const C_BG = Color("#0a0a0a")
const C_PANEL = Color("#141414")
const C_COLUMN = Color("#1a1a1a")
const C_CARD = Color("#222222")
const C_CARD_HOVER = Color("#2a2a2a")
const C_RED = Color("#ff1744")
const C_RED_DARK = Color("#b00020")
const C_RED_GLOW = Color("#ff5252")
const C_TEXT = Color("#f5f5f5")
const C_TEXT_DIM = Color("#888888")
const C_BORDER = Color("#330000")
const C_BORDER_HOT = Color("#ff1744")

const C_LOCKED = Color("#3a3a3a")
const C_AVAILABLE = Color("#ff1744")
const C_COMPLETED = Color("#2d7a2d")

const NODE_TYPES = {
	"Quest":     {"color": "#c41e3a", "icon": "⚔"},
	"Unlock":    {"color": "#ff1744", "icon": "🔓"},
	"Item":      {"color": "#7a1f2e", "icon": "💎"},
	"Boss":      {"color": "#660000", "icon": "💀"},
	"Area":      {"color": "#a31835", "icon": "🗺"},
	"Skill":     {"color": "#e8344f", "icon": "⭐"},
	"Choice":    {"color": "#9c27b0", "icon": "🔀"},
	"Dialogue":  {"color": "#3f51b5", "icon": "💬"},
	"Cutscene":  {"color": "#673ab7", "icon": "🎬"},
	"Story":     {"color": "#ff6f00", "icon": "📖"},
	"Chapter":   {"color": "#bf360c", "icon": "📕"},
	"Ending":    {"color": "#000000", "icon": "🏁"},
	"NPC":       {"color": "#00838f", "icon": "👤"},
	"Lore":      {"color": "#4a148c", "icon": "📜"},
	"Event":     {"color": "#f57f17", "icon": "⚡"},
	"Checkpoint":{"color": "#1b5e20", "icon": "🚩"},
	"Comment":   {"color": "#fdd835", "icon": "💭"},
	"Frame":     {"color": "#673ab7", "icon": "🟪"}
}

const SEASONS = {
	"Q1 / Winter":  {"color": "#4fc3f7", "icon": "❄", "months": "Jan – Mar"},
	"Q2 / Spring":  {"color": "#81c784", "icon": "🌱", "months": "Apr – Jun"},
	"Q3 / Summer":  {"color": "#ffb74d", "icon": "☀", "months": "Jul – Sep"},
	"Q4 / Fall":    {"color": "#ff7043", "icon": "🍂", "months": "Oct – Dec"},
	"Holiday":      {"color": "#e53935", "icon": "🎄", "months": "Late Dec"},
	"Launch":       {"color": "#ff1744", "icon": "🚀", "months": "Custom"},
	"Patch":        {"color": "#7986cb", "icon": "🔧", "months": "Anytime"},
	"DLC":          {"color": "#ab47bc", "icon": "📦", "months": "Custom"}
}

func styled_box(bg: Color, radius: int = 6, border_c: Color = Color.TRANSPARENT, border_w: int = 0, shadow: bool = false) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_color = border_c
	s.border_width_left = border_w
	s.border_width_right = border_w
	s.border_width_top = border_w
	s.border_width_bottom = border_w
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if shadow:
		s.shadow_color = Color(C_RED.r, 0, 0, 0.25)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 2)
	return s

# ==========================================
# INNER CLASSES
# ==========================================
class KanbanColumn extends PanelContainer:
	var column_name: String
	var main_app: Control
	func _can_drop_data(_p, d): return typeof(d) == TYPE_DICTIONARY and d.get("type") == "task"
	func _drop_data(_p, d): main_app.change_task_status(d["task_id"], column_name)

class KanbanCard extends PanelContainer:
	var task_id: String
	var task_title: String
	func _get_drag_data(_p):
		var lbl = Label.new()
		lbl.text = "  " + task_title + "  "
		var s = StyleBoxFlat.new()
		s.bg_color = Color("#ff1744")
		s.corner_radius_top_left = 6
		s.corner_radius_top_right = 6
		s.corner_radius_bottom_left = 6
		s.corner_radius_bottom_right = 6
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		lbl.add_theme_stylebox_override("normal", s)
		set_drag_preview(lbl)
		return {"type": "task", "task_id": task_id}

class DocsTree extends Tree:
	var main_app: Control
	func _get_drag_data(at):
		var item = get_item_at_position(at)
		if not item: return null
		var lbl = Label.new()
		lbl.text = "  Move: " + item.get_text(0) + "  "
		set_drag_preview(lbl)
		return {"type": "doc", "doc_id": item.get_metadata(0)}
	func _can_drop_data(_a, d): return typeof(d) == TYPE_DICTIONARY and d.get("type") == "doc"
	func _drop_data(at, d):
		var target = get_item_at_position(at)
		var new_parent = "root"
		if target:
			var tid = target.get_metadata(0)
			if main_app.data.documents[tid].type == "folder" and get_drop_section_at_position(at) == 0:
				new_parent = tid
			else:
				new_parent = main_app.data.documents[tid].parent
		var temp = new_parent
		while temp != "root" and temp != "":
			if temp == d["doc_id"]: return
			temp = main_app.data.documents[temp].parent
		main_app.data.documents[d["doc_id"]].parent = new_parent
		main_app.save_data()
		main_app.build_docs_tree()

# ==========================================
# DATA
# ==========================================
var data = {
	"columns": ["To Do", "In Progress", "Done"],
	"tasks": {}, "nodes": {}, "connections": [],
	"documents": {"root": {"title": "Root", "type": "folder", "parent": "", "content": ""}},
	"releases": {}
}

var tabs: TabContainer
var kanban_container: HBoxContainer
var flowchart: GraphEdit
var flowchart_popup: PopupMenu
var docs_tree: DocsTree
var docs_editor: TextEdit
var docs_context_menu: PopupMenu
var docs_right_clicked_id: String = ""
var current_doc_id: String = ""

var releases_scroll: ScrollContainer
var releases_container: VBoxContainer
var releases_year_filter: OptionButton
var releases_stat_label: Label
var current_year_filter: int = -1

# ==========================================
# INIT
# ==========================================
func _ready():
	set_anchors_preset(PRESET_FULL_RECT)
	custom_minimum_size = Vector2(800, 600)
	
	var bg = Panel.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", styled_box(C_BG, 0))
	add_child(bg)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)
	
	var app_bar = PanelContainer.new()
	var bar_style = styled_box(Color("#000000"), 0)
	bar_style.border_color = C_RED
	bar_style.border_width_bottom = 2
	app_bar.add_theme_stylebox_override("panel", bar_style)
	main_vbox.add_child(app_bar)
	
	var bar_inner = HBoxContainer.new()
	app_bar.add_child(bar_inner)
	
	var title = Label.new()
	title.text = "VoidForge"
	title.add_theme_color_override("font_color", C_RED)
	title.add_theme_font_size_override("font_size", 16)
	bar_inner.add_child(title)
	
	tabs = TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", styled_box(C_BG, 0))
	tabs.add_theme_stylebox_override("tab_selected", styled_box(C_RED, 4))
	tabs.add_theme_stylebox_override("tab_unselected", styled_box(C_PANEL, 4))
	tabs.add_theme_stylebox_override("tab_hovered", styled_box(C_RED_DARK, 4))
	tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	tabs.add_theme_color_override("font_unselected_color", C_TEXT_DIM)
	tabs.add_theme_color_override("font_hovered_color", Color.WHITE)
	main_vbox.add_child(tabs)
	
	_init_kanban_ui()
	_init_releases_ui()
	_init_flowchart_ui()
	_init_docs_ui()
	
	load_data()
	refresh_ui()

func get_uid() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi() % 9999)

func save_data():
	var f = FileAccess.open(DATA_FILE, FileAccess.WRITE)
	if f == null:
		push_error("VoidForge: Could not open data file for writing. Error: " + str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func load_data():
	if FileAccess.file_exists(DATA_FILE):
		var f = FileAccess.open(DATA_FILE, FileAccess.READ)
		if f == null: return
		var p = JSON.parse_string(f.get_as_text())
		f.close()
		if p != null:
			for k in data.keys():
				if not p.has(k): p[k] = data[k]
			data = p

func refresh_ui():
	build_kanban()
	build_releases()
	build_flowchart()
	build_docs_tree()

# ==========================================
# 1. KANBAN (Compact & Dynamic)
# ==========================================
func _init_kanban_ui():
	var scroll = ScrollContainer.new()
	scroll.name = "  Tasks  "
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs.add_child(scroll)
	
	var wrapper = VBoxContainer.new()
	wrapper.size_flags_horizontal = SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)
	scroll.add_child(wrapper)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.size_flags_vertical = SIZE_SHRINK_BEGIN
	wrapper.add_child(margin)
	
	kanban_container = HBoxContainer.new()
	kanban_container.add_theme_constant_override("separation", 12)
	kanban_container.size_flags_vertical = SIZE_SHRINK_BEGIN
	margin.add_child(kanban_container)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(spacer)

func build_kanban():
	for c in kanban_container.get_children(): c.queue_free()
	
	for col_name in data.columns:
		var col_wrap = VBoxContainer.new()
		col_wrap.custom_minimum_size.x = 240
		col_wrap.size_flags_vertical = SIZE_FILL
		col_wrap.add_theme_constant_override("separation", 0)
		kanban_container.add_child(col_wrap)
		
		var col_panel = PanelContainer.new()
		col_panel.size_flags_vertical = SIZE_SHRINK_BEGIN
		col_panel.size_flags_horizontal = SIZE_EXPAND_FILL
		var col_style = styled_box(C_COLUMN, 8, C_BORDER, 1)
		col_style.content_margin_left = 8
		col_style.content_margin_right = 8
		col_style.content_margin_top = 6
		col_style.content_margin_bottom = 6
		col_panel.add_theme_stylebox_override("panel", col_style)
		col_wrap.add_child(col_panel)
		
		var col_spacer = Control.new()
		col_spacer.size_flags_vertical = SIZE_EXPAND_FILL
		col_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col_wrap.add_child(col_spacer)
		
		var col_vbox = VBoxContainer.new()
		col_vbox.add_theme_constant_override("separation", 6)
		col_panel.add_child(col_vbox)
		
		var header_hbox = HBoxContainer.new()
		col_vbox.add_child(header_hbox)
		
		var name_edit = LineEdit.new()
		name_edit.text = col_name
		name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		name_edit.add_theme_stylebox_override("focus", styled_box(C_BG, 4, C_RED, 1))
		name_edit.add_theme_color_override("font_color", C_RED)
		name_edit.add_theme_font_size_override("font_size", 13)
		name_edit.text_submitted.connect(_rename_column.bind(col_name))
		header_hbox.add_child(name_edit)
		
		var del_col = Button.new()
		del_col.text = "⋯"
		del_col.flat = true
		del_col.add_theme_color_override("font_color", C_TEXT_DIM)
		del_col.pressed.connect(_delete_column.bind(col_name))
		header_hbox.add_child(del_col)
		
		var drop_zone = KanbanColumn.new()
		drop_zone.column_name = col_name
		drop_zone.main_app = self
		drop_zone.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		drop_zone.custom_minimum_size.y = 10
		drop_zone.size_flags_vertical = SIZE_SHRINK_BEGIN
		col_vbox.add_child(drop_zone)
		
		var card_box = VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 6)
		drop_zone.add_child(card_box)
		
		for t_id in data.tasks.keys():
			if data.tasks[t_id].status == col_name:
				_build_card(card_box, t_id, data.tasks[t_id])
		
		var add_btn = Button.new()
		add_btn.text = "  + Add a card"
		add_btn.flat = true
		add_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_btn.add_theme_color_override("font_color", C_TEXT_DIM)
		add_btn.add_theme_color_override("font_hover_color", C_RED)
		add_btn.pressed.connect(_add_task.bind(col_name))
		col_vbox.add_child(add_btn)
	
	var add_wrap = VBoxContainer.new()
	add_wrap.custom_minimum_size.x = 240
	add_wrap.size_flags_vertical = SIZE_FILL
	add_wrap.add_theme_constant_override("separation", 0)
	kanban_container.add_child(add_wrap)
	
	var add_col_panel = PanelContainer.new()
	add_col_panel.size_flags_vertical = SIZE_SHRINK_BEGIN
	add_col_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	add_col_panel.add_theme_stylebox_override("panel", styled_box(Color(1, 0, 0, 0.05), 8, C_BORDER, 1))
	add_wrap.add_child(add_col_panel)
	
	var add_spacer = Control.new()
	add_spacer.size_flags_vertical = SIZE_EXPAND_FILL
	add_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_wrap.add_child(add_spacer)
	
	var add_col_btn = Button.new()
	add_col_btn.text = "+ Add another list"
	add_col_btn.flat = true
	add_col_btn.add_theme_color_override("font_color", C_TEXT)
	add_col_btn.add_theme_color_override("font_hover_color", C_RED)
	add_col_btn.pressed.connect(func(): data.columns.append("New List"); save_data(); refresh_ui())
	add_col_panel.add_child(add_col_btn)

func _build_card(parent, t_id, task):
	var card = KanbanCard.new()
	card.task_id = t_id
	card.task_title = task.title
	var card_style = styled_box(C_CARD, 5, C_BORDER, 1, true)
	card_style.content_margin_left = 8
	card_style.content_margin_right = 8
	card_style.content_margin_top = 6
	card_style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", card_style)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)
	
	var title_edit = LineEdit.new()
	title_edit.text = task.title
	title_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	title_edit.add_theme_stylebox_override("focus", styled_box(C_BG, 4, C_RED, 1))
	title_edit.add_theme_color_override("font_color", C_TEXT)
	title_edit.add_theme_font_size_override("font_size", 12)
	title_edit.text_changed.connect(func(txt): data.tasks[t_id].title = txt; save_data())
	vb.add_child(title_edit)
	
	var bottom = HBoxContainer.new()
	vb.add_child(bottom)
	
	var date_lbl = Label.new()
	date_lbl.text = "🕐 " + task.get("date", "TBD")
	date_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	date_lbl.add_theme_font_size_override("font_size", 10)
	date_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	bottom.add_child(date_lbl)
	
	var del = Button.new()
	del.text = "✕"
	del.flat = true
	del.add_theme_color_override("font_color", C_TEXT_DIM)
	del.add_theme_color_override("font_hover_color", C_RED)
	del.add_theme_font_size_override("font_size", 10)
	del.pressed.connect(func(): data.tasks.erase(t_id); save_data(); refresh_ui())
	bottom.add_child(del)
	
	parent.add_child(card)

func _rename_column(new_text: String, old_name: String):
	if old_name == new_text or new_text == "": return
	var idx = data.columns.find(old_name)
	if idx != -1: data.columns[idx] = new_text
	for t in data.tasks.keys():
		if data.tasks[t].status == old_name: data.tasks[t].status = new_text
	save_data(); refresh_ui()

func _delete_column(col_name: String):
	data.columns.erase(col_name); save_data(); refresh_ui()

func _add_task(col_name: String):
	data.tasks[get_uid()] = {"title": "New Task", "status": col_name, "date": "TBD", "script": ""}
	save_data(); refresh_ui()

func change_task_status(t_id, new_status):
	data.tasks[t_id].status = new_status; save_data(); refresh_ui()

# ==========================================
# 2. RELEASES
# ==========================================
func _init_releases_ui():
	var vb = VBoxContainer.new()
	vb.name = "  Releases  "
	vb.add_theme_constant_override("separation", 0)
	tabs.add_child(vb)
	
	var header = PanelContainer.new()
	var hd_style = StyleBoxFlat.new()
	hd_style.bg_color = Color("#0d0608")
	hd_style.border_color = C_RED
	hd_style.border_width_bottom = 2
	hd_style.content_margin_left = 24
	hd_style.content_margin_right = 24
	hd_style.content_margin_top = 16
	hd_style.content_margin_bottom = 16
	header.add_theme_stylebox_override("panel", hd_style)
	vb.add_child(header)
	
	var hd_inner = HBoxContainer.new()
	hd_inner.add_theme_constant_override("separation", 20)
	header.add_child(hd_inner)
	
	var title_vb = VBoxContainer.new()
	title_vb.size_flags_horizontal = SIZE_EXPAND_FILL
	title_vb.add_theme_constant_override("separation", 2)
	hd_inner.add_child(title_vb)
	
	var hd_title = Label.new()
	hd_title.text = "🚀  RELEASE ROADMAP"
	hd_title.add_theme_color_override("font_color", C_RED)
	hd_title.add_theme_font_size_override("font_size", 20)
	title_vb.add_child(hd_title)
	
	releases_stat_label = Label.new()
	releases_stat_label.text = "0 releases planned"
	releases_stat_label.add_theme_color_override("font_color", C_TEXT_DIM)
	releases_stat_label.add_theme_font_size_override("font_size", 11)
	title_vb.add_child(releases_stat_label)
	
	var filter_vb = VBoxContainer.new()
	filter_vb.add_theme_constant_override("separation", 2)
	hd_inner.add_child(filter_vb)
	
	var filter_lbl = Label.new()
	filter_lbl.text = "FILTER BY YEAR"
	filter_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	filter_lbl.add_theme_font_size_override("font_size", 10)
	filter_vb.add_child(filter_lbl)
	
	releases_year_filter = OptionButton.new()
	releases_year_filter.custom_minimum_size.x = 140
	releases_year_filter.item_selected.connect(_on_year_filter_changed)
	filter_vb.add_child(releases_year_filter)
	
	var add_btn = Button.new()
	add_btn.text = "  + NEW RELEASE  "
	add_btn.add_theme_color_override("font_color", Color.WHITE)
	add_btn.add_theme_font_size_override("font_size", 13)
	var ab_style = styled_box(C_RED, 4)
	ab_style.content_margin_top = 10
	ab_style.content_margin_bottom = 10
	add_btn.add_theme_stylebox_override("normal", ab_style)
	add_btn.add_theme_stylebox_override("hover", styled_box(C_RED_GLOW, 4))
	add_btn.add_theme_stylebox_override("pressed", styled_box(C_RED_DARK, 4))
	add_btn.pressed.connect(_add_release)
	hd_inner.add_child(add_btn)
	
	releases_scroll = ScrollContainer.new()
	releases_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	releases_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(releases_scroll)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	releases_scroll.add_child(margin)
	
	releases_container = VBoxContainer.new()
	releases_container.add_theme_constant_override("separation", 32)
	margin.add_child(releases_container)

func _add_release():
	var current_year = Time.get_date_dict_from_system().year
	data.releases[get_uid()] = {
		"title": "Untitled Release",
		"season": "Q1 / Winter",
		"year": current_year,
		"target_date": "",
		"description": "",
		"task_ids": []
	}
	save_data()
	build_releases()

func _on_year_filter_changed(idx):
	current_year_filter = releases_year_filter.get_item_id(idx)
	build_releases()

func _refresh_year_filter():
	var prev_id = current_year_filter
	releases_year_filter.clear()
	releases_year_filter.add_item("All Years", -1)
	
	var years = {}
	for r_id in data.releases.keys():
		var yr = data.releases[r_id].get("year", 0)
		if yr > 0: years[yr] = true
	
	var sorted_years = years.keys()
	sorted_years.sort()
	for y in sorted_years:
		releases_year_filter.add_item(str(y), y)
	
	for i in range(releases_year_filter.item_count):
		if releases_year_filter.get_item_id(i) == prev_id:
			releases_year_filter.select(i)
			return
	releases_year_filter.select(0)
	current_year_filter = -1

func _get_release_progress(release) -> Dictionary:
	var total = release.task_ids.size()
	if total == 0: return {"done": 0, "total": 0, "pct": 0.0}
	var done = 0
	for t_id in release.task_ids:
		if data.tasks.has(t_id) and data.tasks[t_id].status == "Done":
			done += 1
	return {"done": done, "total": total, "pct": float(done) / float(total)}

func build_releases():
	for c in releases_container.get_children(): c.queue_free()
	_refresh_year_filter()
	
	var total_count = data.releases.size()
	var upcoming = 0
	var current_year = Time.get_date_dict_from_system().year
	for r_id in data.releases.keys():
		if data.releases[r_id].get("year", 0) >= current_year: upcoming += 1
	releases_stat_label.text = "%d total  •  %d upcoming" % [total_count, upcoming]
	
	var grouped = {}
	for r_id in data.releases.keys():
		var r = data.releases[r_id]
		var yr = r.get("year", 0)
		if current_year_filter != -1 and yr != current_year_filter: continue
		if not grouped.has(yr): grouped[yr] = {}
		var s = r.get("season", "Q1 / Winter")
		if not grouped[yr].has(s): grouped[yr][s] = []
		grouped[yr][s].append(r_id)
	
	if grouped.is_empty():
		var empty_panel = PanelContainer.new()
		empty_panel.add_theme_stylebox_override("panel", styled_box(C_PANEL, 12, C_BORDER, 1))
		releases_container.add_child(empty_panel)
		var empty_vb = VBoxContainer.new()
		empty_vb.add_theme_constant_override("separation", 8)
		empty_panel.add_child(empty_vb)
		var empty_icon = Label.new()
		empty_icon.text = "🚀"
		empty_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_icon.add_theme_font_size_override("font_size", 36)
		empty_vb.add_child(empty_icon)
		var empty_lbl = Label.new()
		empty_lbl.text = "No releases planned yet"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", C_TEXT)
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_vb.add_child(empty_lbl)
		var empty_sub = Label.new()
		empty_sub.text = "Click + NEW RELEASE to start your roadmap"
		empty_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_sub.add_theme_color_override("font_color", C_TEXT_DIM)
		empty_sub.add_theme_font_size_override("font_size", 11)
		empty_vb.add_child(empty_sub)
		return
	
	var sorted_years = grouped.keys()
	sorted_years.sort()
	
	for yr in sorted_years:
		var year_section = VBoxContainer.new()
		year_section.add_theme_constant_override("separation", 16)
		releases_container.add_child(year_section)
		
		var year_header = HBoxContainer.new()
		year_header.add_theme_constant_override("separation", 16)
		year_section.add_child(year_header)
		
		var year_lbl = Label.new()
		year_lbl.text = str(yr)
		year_lbl.add_theme_color_override("font_color", C_RED)
		year_lbl.add_theme_font_size_override("font_size", 32)
		year_header.add_child(year_lbl)
		
		var year_line = Panel.new()
		year_line.size_flags_horizontal = SIZE_EXPAND_FILL
		year_line.size_flags_vertical = SIZE_SHRINK_CENTER
		year_line.custom_minimum_size.y = 2
		var line_style = StyleBoxFlat.new()
		line_style.bg_color = C_BORDER
		year_line.add_theme_stylebox_override("panel", line_style)
		year_header.add_child(year_line)
		
		var year_count_lbl = Label.new()
		var y_count = 0
		for s in grouped[yr]: y_count += grouped[yr][s].size()
		year_count_lbl.text = str(y_count) + " RELEASE" + ("S" if y_count != 1 else "")
		year_count_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		year_count_lbl.add_theme_font_size_override("font_size", 11)
		year_header.add_child(year_count_lbl)
		
		for season_name in SEASONS.keys():
			if not grouped[yr].has(season_name): continue
			
			var season_info = SEASONS[season_name]
			var s_color = Color(season_info.color)
			
			var season_box = VBoxContainer.new()
			season_box.add_theme_constant_override("separation", 12)
			year_section.add_child(season_box)
			
			var s_header = HBoxContainer.new()
			s_header.add_theme_constant_override("separation", 10)
			season_box.add_child(s_header)
			
			var s_pill = PanelContainer.new()
			var pill_style = styled_box(s_color.darkened(0.3), 14, s_color, 1)
			pill_style.content_margin_left = 14
			pill_style.content_margin_right = 14
			pill_style.content_margin_top = 4
			pill_style.content_margin_bottom = 4
			s_pill.add_theme_stylebox_override("panel", pill_style)
			s_header.add_child(s_pill)
			
			var s_pill_lbl = Label.new()
			s_pill_lbl.text = season_info.icon + "  " + season_name
			s_pill_lbl.add_theme_color_override("font_color", Color.WHITE)
			s_pill_lbl.add_theme_font_size_override("font_size", 12)
			s_pill.add_child(s_pill_lbl)
			
			var s_months = Label.new()
			s_months.text = season_info.months
			s_months.add_theme_color_override("font_color", C_TEXT_DIM)
			s_months.add_theme_font_size_override("font_size", 11)
			s_header.add_child(s_months)
			
			var grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 18)
			grid.add_theme_constant_override("v_separation", 18)
			season_box.add_child(grid)
			
			for r_id in grouped[yr][season_name]:
				_build_release_card(grid, r_id, data.releases[r_id])

func _build_release_card(parent, r_id, release):
	if not release.has("task_ids"): release["task_ids"] = []
	if not release.has("target_date"): release["target_date"] = ""
	if not release.has("description"): release["description"] = ""
	if not release.has("year"): release["year"] = Time.get_date_dict_from_system().year
	if not release.has("season"): release["season"] = "Q1 / Winter"
	
	var season_info = SEASONS.get(release.season, SEASONS["Q1 / Winter"])
	var s_color = Color(season_info.color)
	var progress = _get_release_progress(release)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 0)
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = C_CARD
	card_style.border_color = s_color
	card_style.border_width_left = 4
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_right = 8
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_bottom_left = 8
	card_style.content_margin_left = 18
	card_style.content_margin_right = 18
	card_style.content_margin_top = 16
	card_style.content_margin_bottom = 16
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 6
	card_style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	
	var icon_lbl = Label.new()
	icon_lbl.text = season_info.icon
	icon_lbl.add_theme_font_size_override("font_size", 24)
	top.add_child(icon_lbl)
	
	var title_edit = LineEdit.new()
	title_edit.text = release.title
	title_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	title_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	title_edit.add_theme_stylebox_override("focus", styled_box(C_BG, 4, s_color, 1))
	title_edit.add_theme_color_override("font_color", C_TEXT)
	title_edit.add_theme_font_size_override("font_size", 17)
	title_edit.text_changed.connect(func(t): data.releases[r_id].title = t; save_data())
	top.add_child(title_edit)
	
	var status_pill = PanelContainer.new()
	var current_year = Time.get_date_dict_from_system().year
	var status_text = "UPCOMING"
	var status_color = Color("#4fc3f7")
	if progress.pct >= 1.0 and progress.total > 0:
		status_text = "READY"
		status_color = Color("#4caf50")
	elif progress.done > 0:
		status_text = "IN PROGRESS"
		status_color = Color("#ff9800")
	elif release.year < current_year:
		status_text = "OVERDUE"
		status_color = C_RED
	
	var pill_style = styled_box(status_color.darkened(0.4), 10, status_color, 1)
	pill_style.content_margin_left = 8
	pill_style.content_margin_right = 8
	pill_style.content_margin_top = 2
	pill_style.content_margin_bottom = 2
	status_pill.add_theme_stylebox_override("panel", pill_style)
	top.add_child(status_pill)
	
	var status_lbl = Label.new()
	status_lbl.text = status_text
	status_lbl.add_theme_color_override("font_color", Color.WHITE)
	status_lbl.add_theme_font_size_override("font_size", 9)
	status_pill.add_child(status_lbl)
	
	var del = Button.new()
	del.text = "✕"
	del.flat = true
	del.add_theme_color_override("font_color", C_TEXT_DIM)
	del.add_theme_color_override("font_hover_color", C_RED)
	del.pressed.connect(func(): data.releases.erase(r_id); save_data(); build_releases())
	top.add_child(del)
	
	var meta_row = HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	vb.add_child(meta_row)
	
	var season_opt = OptionButton.new()
	var sel_idx = 0
	var i = 0
	for sn in SEASONS.keys():
		season_opt.add_item(SEASONS[sn].icon + " " + sn, i)
		if sn == release.season: sel_idx = i
		i += 1
	season_opt.select(sel_idx)
	season_opt.item_selected.connect(func(idx): 
		data.releases[r_id].season = SEASONS.keys()[idx]
		save_data(); build_releases())
	meta_row.add_child(season_opt)
	
	var year_spin = SpinBox.new()
	year_spin.min_value = 2020
	year_spin.max_value = 2100
	year_spin.value = release.year
	year_spin.custom_minimum_size.x = 90
	year_spin.value_changed.connect(func(v): 
		data.releases[r_id].year = int(v)
		save_data(); build_releases())
	meta_row.add_child(year_spin)
	
	var date_edit = LineEdit.new()
	date_edit.text = release.target_date
	date_edit.placeholder_text = "📅 Target date..."
	date_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	date_edit.add_theme_stylebox_override("normal", styled_box(C_BG, 4, C_BORDER, 1))
	date_edit.add_theme_color_override("font_color", C_TEXT)
	date_edit.text_changed.connect(func(t): data.releases[r_id].target_date = t; save_data())
	meta_row.add_child(date_edit)
	
	var desc = TextEdit.new()
	desc.text = release.description
	desc.placeholder_text = "What ships in this release..."
	desc.custom_minimum_size.y = 55
	desc.add_theme_stylebox_override("normal", styled_box(C_BG, 4, C_BORDER, 1))
	desc.add_theme_color_override("font_color", C_TEXT)
	desc.add_theme_font_size_override("font_size", 11)
	desc.text_changed.connect(func(): data.releases[r_id].description = desc.text; save_data())
	vb.add_child(desc)
	
	if release.task_ids.size() > 0:
		var prog_row = HBoxContainer.new()
		prog_row.add_theme_constant_override("separation", 8)
		vb.add_child(prog_row)
		
		var prog_icon = Label.new()
		prog_icon.text = "📊"
		prog_icon.add_theme_font_size_override("font_size", 12)
		prog_row.add_child(prog_icon)
		
		var prog_lbl = Label.new()
		prog_lbl.text = "%d / %d tasks done" % [progress.done, progress.total]
		prog_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		prog_lbl.add_theme_font_size_override("font_size", 10)
		prog_row.add_child(prog_lbl)
		
		var pct_lbl = Label.new()
		pct_lbl.text = "%d%%" % int(progress.pct * 100)
		pct_lbl.add_theme_color_override("font_color", s_color)
		pct_lbl.add_theme_font_size_override("font_size", 10)
		pct_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prog_row.add_child(pct_lbl)
		
		var pb = ProgressBar.new()
		pb.min_value = 0
		pb.max_value = 100
		pb.value = progress.pct * 100
		pb.show_percentage = false
		pb.custom_minimum_size.y = 6
		var pb_bg = styled_box(C_BG, 3)
		var pb_fg = styled_box(s_color, 3)
		pb.add_theme_stylebox_override("background", pb_bg)
		pb.add_theme_stylebox_override("fill", pb_fg)
		vb.add_child(pb)
	
	var task_row = HBoxContainer.new()
	task_row.add_theme_constant_override("separation", 6)
	vb.add_child(task_row)
	
	var task_opt = OptionButton.new()
	task_opt.add_item("🎯  Link a task...", -1)
	for t_id in data.tasks.keys():
		if not release.task_ids.has(t_id):
			task_opt.add_item(data.tasks[t_id].title, task_opt.item_count)
			task_opt.set_item_metadata(task_opt.item_count - 1, t_id)
	task_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	task_row.add_child(task_opt)
	
	var add_task_btn = Button.new()
	add_task_btn.text = "  + Link  "
	add_task_btn.add_theme_color_override("font_color", s_color)
	add_task_btn.pressed.connect(func():
		var sel = task_opt.selected
		if sel <= 0: return
		var t_id = task_opt.get_item_metadata(sel)
		if t_id and not data.releases[r_id].task_ids.has(t_id):
			data.releases[r_id].task_ids.append(t_id)
			save_data()
			build_releases()
	)
	task_row.add_child(add_task_btn)
	
	if release.task_ids.size() > 0:
		var chips = HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		vb.add_child(chips)
		
		for t_id in release.task_ids:
			if not data.tasks.has(t_id): continue
			var task = data.tasks[t_id]
			var is_done = task.status == "Done"
			
			var chip = PanelContainer.new()
			var chip_bg = s_color.darkened(0.6) if not is_done else Color("#2d7a2d").darkened(0.5)
			var chip_border = s_color if not is_done else Color("#4caf50")
			var chip_style = styled_box(chip_bg, 12, chip_border, 1)
			chip_style.content_margin_left = 10
			chip_style.content_margin_right = 6
			chip_style.content_margin_top = 4
			chip_style.content_margin_bottom = 4
			chip.add_theme_stylebox_override("panel", chip_style)
			chips.add_child(chip)
			
			var chip_row = HBoxContainer.new()
			chip_row.add_theme_constant_override("separation", 4)
			chip.add_child(chip_row)
			
			var check = Label.new()
			check.text = "✓" if is_done else "○"
			check.add_theme_color_override("font_color", Color.WHITE)
			check.add_theme_font_size_override("font_size", 10)
			chip_row.add_child(check)
			
			var chip_lbl = Label.new()
			chip_lbl.text = task.title
			chip_lbl.add_theme_color_override("font_color", Color.WHITE)
			chip_lbl.add_theme_font_size_override("font_size", 10)
			chip_row.add_child(chip_lbl)
			
			var chip_x = Button.new()
			chip_x.text = "✕"
			chip_x.flat = true
			chip_x.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
			chip_x.add_theme_color_override("font_hover_color", Color.WHITE)
			chip_x.add_theme_font_size_override("font_size", 9)
			chip_x.pressed.connect(func():
				data.releases[r_id].task_ids.erase(t_id)
				save_data()
				build_releases()
			)
			chip_row.add_child(chip_x)

# ==========================================
# 3. GAME PROGRESSION MAP (FLOWCHART)
# ==========================================
func _init_flowchart_ui():
	flowchart = GraphEdit.new()
	flowchart.name = "  Progression  "
	flowchart.right_disconnects = true
	flowchart.show_grid = true
	tabs.add_child(flowchart)
	
	flowchart_popup = PopupMenu.new()
	var i = 0
	for type_name in NODE_TYPES.keys():
		flowchart_popup.add_item(NODE_TYPES[type_name].icon + "  " + type_name, i)
		i += 1
	flowchart_popup.id_pressed.connect(_on_flowchart_popup)
	add_child(flowchart_popup)
	
	flowchart.popup_request.connect(func(_pos):
		flowchart_popup.position = DisplayServer.mouse_get_position()
		flowchart_popup.popup()
	)
	flowchart.connection_request.connect(_on_graph_connect)
	flowchart.disconnection_request.connect(_on_graph_disconnect)

func _on_flowchart_popup(id: int):
	var type_keys = NODE_TYPES.keys()
	var type_name = type_keys[id]
	var n_id = "node_" + get_uid()
	var mouse_local = flowchart.get_local_mouse_position()
	var graph_pos = (mouse_local + flowchart.scroll_offset) / flowchart.zoom
	
	if type_name == "Frame":
		data.nodes[n_id] = {
			"title": "Comment",
			"node_type": "Frame",
			"x": graph_pos.x - 50, "y": graph_pos.y - 50,
			"w": 500, "h": 300,
			"frame_color": "#673ab7"
		}
	else:
		data.nodes[n_id] = {
			"title": "New " + type_name,
			"node_type": type_name,
			"x": graph_pos.x, "y": graph_pos.y,
			"w": 280, "h": 200,
			"status": "Available",
			"objective": "",
			"reward": "",
			"notes": ""
		}
	save_data()
	build_flowchart()

func _auto_update_locks():
	for n_id in data.nodes.keys():
		var nd = data.nodes[n_id]
		var nt = nd.get("node_type", "")
		if nt == "Comment" or nt == "Frame": continue
		if nd.status == "Completed": continue
		var parents = []
		for c in data.connections:
			if c.to == n_id: parents.append(c.from)
		if parents.is_empty():
			if nd.status == "Locked": nd.status = "Available"
		else:
			var all_done = true
			for p in parents:
				if not data.nodes.has(p) or data.nodes[p].status != "Completed":
					all_done = false; break
			if all_done and nd.status == "Locked":
				nd.status = "Available"
	for c in flowchart.get_children():
		if c is GraphNode and data.nodes.has(c.name):
			_apply_status_visuals(c, data.nodes[c.name])

func _apply_status_visuals(node: GraphNode, nd: Dictionary):
	var nt = nd.get("node_type", "")
	if nt == "Comment" or nt == "Frame": return
	
	var status_color = C_AVAILABLE
	match nd.status:
		"Locked": status_color = C_LOCKED
		"Available": status_color = C_AVAILABLE
		"Completed": status_color = C_COMPLETED
	var body_color = C_PANEL if nd.status != "Locked" else Color(0.08, 0.05, 0.05)
	var body = StyleBoxFlat.new()
	body.bg_color = body_color
	body.border_color = status_color
	body.border_width_left = 2
	body.border_width_right = 2
	body.border_width_bottom = 2
	body.corner_radius_bottom_left = 4
	body.corner_radius_bottom_right = 4
	body.content_margin_left = 8
	body.content_margin_right = 8
	body.content_margin_top = 6
	body.content_margin_bottom = 6
	node.add_theme_stylebox_override("panel", body)
	node.add_theme_stylebox_override("panel_selected", body)

func _cycle_status(n_id):
	var current = data.nodes[n_id].status
	var next_status = "Locked"
	match current:
		"Locked": next_status = "Available"
		"Available": next_status = "Completed"
		"Completed": next_status = "Locked"
	data.nodes[n_id].status = next_status
	save_data()
	_auto_update_locks()
	build_flowchart()

func build_flowchart():
	flowchart.clear_connections()
	for c in flowchart.get_children():
		if c is GraphNode:
			flowchart.remove_child(c)
			c.queue_free()
	
	# Spawn FRAMES FIRST so they render behind regular nodes
	for n_id in data.nodes.keys():
		if data.nodes[n_id].get("node_type", "") == "Frame":
			_spawn_graph_node(n_id)
	
	# Then spawn all other nodes on top
	for n_id in data.nodes.keys():
		if data.nodes[n_id].get("node_type", "") != "Frame":
			_spawn_graph_node(n_id)
	
	for conn in data.connections:
		if data.nodes.has(conn.from) and data.nodes.has(conn.to):
			flowchart.connect_node(conn.from, conn.from_port, conn.to, conn.to_port)

func _spawn_graph_node(n_id: String):
	var nd = data.nodes[n_id]
	if not nd.has("node_type"): nd["node_type"] = "Quest"
	if not nd.has("status"): nd["status"] = "Available"
	if not nd.has("objective"): nd["objective"] = ""
	if not nd.has("reward"): nd["reward"] = ""
	if not nd.has("notes"): nd["notes"] = ""
	if not nd.has("w"): nd["w"] = 280
	if not nd.has("h"): nd["h"] = 200
	
	# === FRAME NODE — UE-style group comment box ===
	if nd.node_type == "Frame":
		_spawn_frame_node(n_id, nd)
		return
	
	# === COMMENT NODE — sticky-note style ===
	if nd.node_type == "Comment":
		_spawn_comment_node(n_id, nd)
		return
	
	var type_info = NODE_TYPES.get(nd.node_type, NODE_TYPES["Quest"])
	var type_color = Color(type_info.color)
	
	var node = GraphNode.new()
	node.name = n_id
	node.title = type_info.icon + "  " + nd.title
	node.position_offset = Vector2(nd.x, nd.y)
	node.size = Vector2(nd.w, nd.h)
	node.resizable = true
	
	var tb = StyleBoxFlat.new()
	tb.bg_color = type_color
	tb.corner_radius_top_left = 4
	tb.corner_radius_top_right = 4
	tb.content_margin_left = 10
	tb.content_margin_right = 10
	tb.content_margin_top = 6
	tb.content_margin_bottom = 6
	node.add_theme_stylebox_override("titlebar", tb)
	node.add_theme_stylebox_override("titlebar_selected", tb)
	
	flowchart.add_child(node)
	
	var port_row = HBoxContainer.new()
	port_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port_row.custom_minimum_size.y = 30
	node.add_child(port_row)
	
	var in_lbl = Label.new()
	in_lbl.text = "← Requires"
	in_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	in_lbl.add_theme_color_override("font_color", Color("#00ff66"))
	in_lbl.add_theme_font_size_override("font_size", 11)
	in_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	port_row.add_child(in_lbl)
	
	var out_lbl = Label.new()
	out_lbl.text = "Unlocks →"
	out_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out_lbl.add_theme_color_override("font_color", Color("#ff1744"))
	out_lbl.add_theme_font_size_override("font_size", 11)
	out_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	out_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	port_row.add_child(out_lbl)
	
	var top = HBoxContainer.new()
	node.add_child(top)
	
	var le = LineEdit.new()
	le.text = nd.title
	le.placeholder_text = "Name..."
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	le.add_theme_stylebox_override("normal", styled_box(C_BG, 3, C_BORDER, 1))
	le.add_theme_color_override("font_color", C_TEXT)
	le.text_changed.connect(func(t): data.nodes[n_id].title = t; node.title = type_info.icon + "  " + t; save_data())
	top.add_child(le)
	
	var db = Button.new()
	db.text = "✕"
	db.flat = true
	db.add_theme_color_override("font_color", C_RED)
	db.pressed.connect(func(): data.nodes.erase(n_id); _clean_connections(n_id); save_data(); build_flowchart())
	top.add_child(db)
	
	var meta_row = HBoxContainer.new()
	node.add_child(meta_row)
	
	var status_color = C_AVAILABLE
	match nd.status:
		"Locked": status_color = C_LOCKED
		"Available": status_color = C_AVAILABLE
		"Completed": status_color = C_COMPLETED
	
	var status_btn = Button.new()
	var status_icons = {"Locked": "🔒 LOCKED", "Available": "⚡ AVAILABLE", "Completed": "✅ DONE"}
	status_btn.text = status_icons[nd.status]
	status_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	var sbtn_style = styled_box(status_color, 3)
	sbtn_style.content_margin_top = 4
	sbtn_style.content_margin_bottom = 4
	status_btn.add_theme_stylebox_override("normal", sbtn_style)
	status_btn.add_theme_stylebox_override("hover", styled_box(status_color.lightened(0.1), 3))
	status_btn.add_theme_stylebox_override("pressed", sbtn_style)
	status_btn.add_theme_color_override("font_color", Color.WHITE)
	status_btn.pressed.connect(func(): _cycle_status(n_id))
	meta_row.add_child(status_btn)
	
	var type_opt = OptionButton.new()
	var idx = 0
	var sel_idx = 0
	for tn in NODE_TYPES.keys():
		type_opt.add_item(NODE_TYPES[tn].icon + " " + tn, idx)
		if tn == nd.node_type: sel_idx = idx
		idx += 1
	type_opt.select(sel_idx)
	type_opt.item_selected.connect(func(i): 
		data.nodes[n_id].node_type = NODE_TYPES.keys()[i]
		save_data(); build_flowchart())
	meta_row.add_child(type_opt)
	
	var obj_lbl = Label.new()
	obj_lbl.text = "🎯 Objective:"
	obj_lbl.add_theme_color_override("font_color", C_RED)
	obj_lbl.add_theme_font_size_override("font_size", 10)
	node.add_child(obj_lbl)
	
	var obj_edit = TextEdit.new()
	obj_edit.text = nd.objective
	obj_edit.custom_minimum_size.y = 40
	obj_edit.add_theme_stylebox_override("normal", styled_box(C_BG, 3, C_BORDER, 1))
	obj_edit.add_theme_color_override("font_color", C_TEXT)
	obj_edit.add_theme_font_size_override("font_size", 11)
	obj_edit.text_changed.connect(func(): data.nodes[n_id].objective = obj_edit.text; save_data())
	node.add_child(obj_edit)
	
	var rew_lbl = Label.new()
	rew_lbl.text = "🎁 Reward:"
	rew_lbl.add_theme_color_override("font_color", C_RED)
	rew_lbl.add_theme_font_size_override("font_size", 10)
	node.add_child(rew_lbl)
	
	var rew_edit = LineEdit.new()
	rew_edit.text = nd.reward
	rew_edit.add_theme_stylebox_override("normal", styled_box(C_BG, 3, C_BORDER, 1))
	rew_edit.add_theme_color_override("font_color", C_TEXT)
	rew_edit.text_changed.connect(func(t): data.nodes[n_id].reward = t; save_data())
	node.add_child(rew_edit)
	
	var notes_lbl = Label.new()
	notes_lbl.text = "📝 Notes:"
	notes_lbl.add_theme_color_override("font_color", Color("#fdd835"))
	notes_lbl.add_theme_font_size_override("font_size", 10)
	node.add_child(notes_lbl)
	
	var notes_edit = TextEdit.new()
	notes_edit.text = nd.notes
	notes_edit.placeholder_text = "Dev notes, reminders, comments..."
	notes_edit.custom_minimum_size.y = 50
	var notes_style = styled_box(Color("#1a1810"), 3, Color("#fdd835").darkened(0.5), 1)
	notes_edit.add_theme_stylebox_override("normal", notes_style)
	notes_edit.add_theme_color_override("font_color", Color("#fff8c4"))
	notes_edit.add_theme_font_size_override("font_size", 11)
	notes_edit.text_changed.connect(func(): data.nodes[n_id].notes = notes_edit.text; save_data())
	node.add_child(notes_edit)
	
	_apply_status_visuals(node, nd)
	
	node.set_slot(0, true, 0, Color("#00ff66"), true, 0, Color("#ff1744"))
	
	node.dragged.connect(func(_f, to): data.nodes[n_id].x = to.x; data.nodes[n_id].y = to.y; save_data())
	node.resize_request.connect(func(new_size):
		data.nodes[n_id].w = new_size.x
		data.nodes[n_id].h = new_size.y
		node.size = new_size
		save_data()
	)

# === STICKY-NOTE STYLE COMMENT NODE ===
func _spawn_comment_node(n_id: String, nd: Dictionary):
	var node = GraphNode.new()
	node.name = n_id
	node.title = "💭  " + nd.title
	node.position_offset = Vector2(nd.x, nd.y)
	node.size = Vector2(nd.w, nd.h)
	node.resizable = true
	
	var tb = StyleBoxFlat.new()
	tb.bg_color = Color("#fdd835")
	tb.corner_radius_top_left = 4
	tb.corner_radius_top_right = 4
	tb.content_margin_left = 10
	tb.content_margin_right = 10
	tb.content_margin_top = 6
	tb.content_margin_bottom = 6
	node.add_theme_stylebox_override("titlebar", tb)
	node.add_theme_stylebox_override("titlebar_selected", tb)
	
	var body = StyleBoxFlat.new()
	body.bg_color = Color("#3d3820")
	body.border_color = Color("#fdd835")
	body.border_width_left = 2
	body.border_width_right = 2
	body.border_width_bottom = 2
	body.corner_radius_bottom_left = 4
	body.corner_radius_bottom_right = 4
	body.content_margin_left = 10
	body.content_margin_right = 10
	body.content_margin_top = 8
	body.content_margin_bottom = 8
	node.add_theme_stylebox_override("panel", body)
	node.add_theme_stylebox_override("panel_selected", body)
	
	flowchart.add_child(node)
	
	var top = HBoxContainer.new()
	node.add_child(top)
	
	var le = LineEdit.new()
	le.text = nd.title
	le.placeholder_text = "Comment title..."
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	le.add_theme_stylebox_override("normal", styled_box(Color("#2a2516"), 3, Color("#fdd835").darkened(0.4), 1))
	le.add_theme_color_override("font_color", Color("#fff8c4"))
	le.text_changed.connect(func(t): data.nodes[n_id].title = t; node.title = "💭  " + t; save_data())
	top.add_child(le)
	
	var db = Button.new()
	db.text = "✕"
	db.flat = true
	db.add_theme_color_override("font_color", Color("#fdd835"))
	db.pressed.connect(func(): data.nodes.erase(n_id); _clean_connections(n_id); save_data(); build_flowchart())
	top.add_child(db)
	
	var comment_edit = TextEdit.new()
	comment_edit.text = nd.notes
	comment_edit.placeholder_text = "Write your comment, idea, reminder, or note here..."
	comment_edit.custom_minimum_size.y = 100
	comment_edit.size_flags_vertical = SIZE_EXPAND_FILL
	var c_style = styled_box(Color("#2a2516"), 3, Color("#fdd835").darkened(0.4), 1)
	c_style.content_margin_left = 8
	c_style.content_margin_right = 8
	c_style.content_margin_top = 6
	c_style.content_margin_bottom = 6
	comment_edit.add_theme_stylebox_override("normal", c_style)
	comment_edit.add_theme_color_override("font_color", Color("#fff8c4"))
	comment_edit.add_theme_font_size_override("font_size", 12)
	comment_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	comment_edit.text_changed.connect(func(): data.nodes[n_id].notes = comment_edit.text; save_data())
	node.add_child(comment_edit)
	
	node.dragged.connect(func(_f, to): data.nodes[n_id].x = to.x; data.nodes[n_id].y = to.y; save_data())
	node.resize_request.connect(func(new_size):
		data.nodes[n_id].w = new_size.x
		data.nodes[n_id].h = new_size.y
		node.size = new_size
		save_data()
	)

# === UE5-STYLE COMMENT FRAME — translucent box that groups nodes ===
func _spawn_frame_node(n_id: String, nd: Dictionary):
	if not nd.has("frame_color"): nd["frame_color"] = "#673ab7"
	if not nd.has("w"): nd["w"] = 500
	if not nd.has("h"): nd["h"] = 300
	
	var frame_color = Color(nd.frame_color)
	
	var node = GraphNode.new()
	node.name = n_id
	node.title = nd.title
	node.position_offset = Vector2(nd.x, nd.y)
	node.size = Vector2(nd.w, nd.h)
	node.resizable = true
	
	# Solid colored titlebar
	var tb = StyleBoxFlat.new()
	tb.bg_color = frame_color
	tb.corner_radius_top_left = 4
	tb.corner_radius_top_right = 4
	tb.content_margin_left = 10
	tb.content_margin_right = 10
	tb.content_margin_top = 6
	tb.content_margin_bottom = 6
	node.add_theme_stylebox_override("titlebar", tb)
	node.add_theme_stylebox_override("titlebar_selected", tb)
	
	# TRANSLUCENT body so you can see nodes through it
	var body = StyleBoxFlat.new()
	body.bg_color = Color(frame_color.r, frame_color.g, frame_color.b, 0.15)
	body.border_color = frame_color
	body.border_width_left = 2
	body.border_width_right = 2
	body.border_width_bottom = 2
	body.corner_radius_bottom_left = 4
	body.corner_radius_bottom_right = 4
	body.content_margin_left = 6
	body.content_margin_right = 6
	body.content_margin_top = 4
	body.content_margin_bottom = 4
	node.add_theme_stylebox_override("panel", body)
	node.add_theme_stylebox_override("panel_selected", body)
	
	flowchart.add_child(node)
	
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	node.add_child(top)
	
	var le = LineEdit.new()
	le.text = nd.title
	le.placeholder_text = "Comment title..."
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	var le_style = StyleBoxFlat.new()
	le_style.bg_color = Color(0, 0, 0, 0.3)
	le_style.corner_radius_top_left = 3
	le_style.corner_radius_top_right = 3
	le_style.corner_radius_bottom_left = 3
	le_style.corner_radius_bottom_right = 3
	le_style.content_margin_left = 6
	le_style.content_margin_right = 6
	le_style.content_margin_top = 3
	le_style.content_margin_bottom = 3
	le.add_theme_stylebox_override("normal", le_style)
	le.add_theme_color_override("font_color", Color.WHITE)
	le.add_theme_font_size_override("font_size", 12)
	le.text_changed.connect(func(t): data.nodes[n_id].title = t; node.title = t; save_data())
	top.add_child(le)
	
	var cp = ColorPickerButton.new()
	cp.color = frame_color
	cp.custom_minimum_size = Vector2(30, 24)
	cp.edit_alpha = false
	cp.color_changed.connect(func(c): 
		data.nodes[n_id].frame_color = c.to_html(false)
		save_data()
		build_flowchart()
	)
	top.add_child(cp)
	
	var db = Button.new()
	db.text = "✕"
	db.flat = true
	db.add_theme_color_override("font_color", Color.WHITE)
	db.add_theme_color_override("font_hover_color", C_RED)
	db.pressed.connect(func(): data.nodes.erase(n_id); save_data(); build_flowchart())
	top.add_child(db)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(spacer)
	
	node.dragged.connect(func(_f, to): data.nodes[n_id].x = to.x; data.nodes[n_id].y = to.y; save_data())
	node.resize_request.connect(func(new_size):
		data.nodes[n_id].w = new_size.x
		data.nodes[n_id].h = new_size.y
		node.size = new_size
		save_data()
	)

func _clean_connections(n_id):
	for i in range(data.connections.size() - 1, -1, -1):
		var c = data.connections[i]
		if c.from == n_id or c.to == n_id: data.connections.remove_at(i)

func _on_graph_connect(from, fp, to, tp):
	if String(from) == String(to): return
	if data.nodes.has(String(from)):
		var ft = data.nodes[String(from)].get("node_type", "")
		if ft == "Comment" or ft == "Frame": return
	if data.nodes.has(String(to)):
		var tt = data.nodes[String(to)].get("node_type", "")
		if tt == "Comment" or tt == "Frame": return
	for c in data.connections:
		if c.from == String(from) and c.to == String(to): return
	flowchart.connect_node(from, fp, to, tp)
	data.connections.append({"from": String(from), "from_port": fp, "to": String(to), "to_port": tp})
	save_data()
	_auto_update_locks()

func _on_graph_disconnect(from, fp, to, tp):
	flowchart.disconnect_node(from, fp, to, tp)
	for i in range(data.connections.size() - 1, -1, -1):
		var c = data.connections[i]
		if c.from == String(from) and c.to == String(to) and c.from_port == fp and c.to_port == tp:
			data.connections.remove_at(i)
	save_data()
	_auto_update_locks()

# ==========================================
# 4. DOCUMENTS
# ==========================================
func _init_docs_ui():
	var split = HSplitContainer.new()
	split.name = "  Documents  "
	split.split_offset = 280
	tabs.add_child(split)
	
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)
	
	var toolbar = HBoxContainer.new()
	left.add_child(toolbar)
	
	var af = Button.new()
	af.text = "📂 Folder"
	af.pressed.connect(func(): _add_document("folder"))
	toolbar.add_child(af)
	
	var afi = Button.new()
	afi.text = "📄 File"
	afi.pressed.connect(func(): _add_document("file"))
	toolbar.add_child(afi)
	
	docs_tree = DocsTree.new()
	docs_tree.main_app = self
	docs_tree.size_flags_vertical = SIZE_EXPAND_FILL
	docs_tree.hide_root = true
	docs_tree.allow_rmb_select = true
	docs_tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
	docs_tree.item_selected.connect(_on_doc_selected)
	docs_tree.item_edited.connect(_on_doc_renamed)
	docs_tree.item_mouse_selected.connect(_on_doc_clicked)
	left.add_child(docs_tree)
	
	docs_context_menu = PopupMenu.new()
	docs_context_menu.add_item("✏️ Rename", 0)
	docs_context_menu.add_item("🗑️ Delete", 1)
	docs_context_menu.id_pressed.connect(_on_context_menu)
	add_child(docs_context_menu)
	
	var ed_panel = PanelContainer.new()
	ed_panel.add_theme_stylebox_override("panel", styled_box(C_COLUMN, 6, C_BORDER, 1))
	split.add_child(ed_panel)
	
	docs_editor = TextEdit.new()
	docs_editor.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	docs_editor.add_theme_color_override("font_color", C_TEXT)
	docs_editor.text_changed.connect(_on_doc_text_changed)
	ed_panel.add_child(docs_editor)

func _on_doc_clicked(_pos, mouse_btn):
	if mouse_btn == MOUSE_BUTTON_RIGHT:
		var item = docs_tree.get_selected()
		if not item: return
		docs_right_clicked_id = item.get_metadata(0)
		docs_context_menu.position = DisplayServer.mouse_get_position()
		docs_context_menu.popup()

func _on_context_menu(id):
	if docs_right_clicked_id == "": return
	if id == 0:
		var item = docs_tree.get_selected()
		if item:
			item.set_editable(0, true)
			item.set_text(0, data.documents[docs_right_clicked_id].title)
			docs_tree.edit_selected(true)
	elif id == 1:
		data.documents.erase(docs_right_clicked_id)
		var orphans = []
		for k in data.documents.keys():
			if data.documents[k].parent == docs_right_clicked_id: orphans.append(k)
		for k in orphans: data.documents.erase(k)
		current_doc_id = ""
		docs_editor.text = ""
		save_data(); build_docs_tree()

func build_docs_tree():
	docs_tree.clear()
	var root = docs_tree.create_item()
	var items = {"root": root}
	for d_id in data.documents.keys():
		var doc = data.documents[d_id]
		if doc.type == "folder" and d_id != "root":
			var parent_item = items.get(doc.parent, root)
			var item = docs_tree.create_item(parent_item)
			item.set_text(0, "📂 " + doc.title)
			item.set_metadata(0, d_id)
			item.set_editable(0, false)
			items[d_id] = item
	for d_id in data.documents.keys():
		var doc = data.documents[d_id]
		if doc.type == "file":
			var parent_item = items.get(doc.parent, root)
			var item = docs_tree.create_item(parent_item)
			item.set_text(0, "📄 " + doc.title)
			item.set_metadata(0, d_id)
			item.set_editable(0, false)
			items[d_id] = item

func _add_document(type):
	var parent_id = "root"
	var sel = docs_tree.get_selected()
	if sel:
		var sid = sel.get_metadata(0)
		if data.documents[sid].type == "folder": parent_id = sid
		else: parent_id = data.documents[sid].parent
	var d_id = "doc_" + get_uid()
	data.documents[d_id] = {"title": "New " + type, "type": type, "parent": parent_id, "content": ""}
	save_data(); build_docs_tree()

func _on_doc_selected():
	var s = docs_tree.get_selected()
	if not s: return
	current_doc_id = s.get_metadata(0)
	if data.documents[current_doc_id].type == "file":
		docs_editor.editable = true
		docs_editor.text = data.documents[current_doc_id].content
	else:
		docs_editor.editable = false
		docs_editor.text = "📁 Folder: " + data.documents[current_doc_id].title

func _on_doc_renamed():
	var s = docs_tree.get_selected()
	if not s: return
	var d_id = s.get_metadata(0)
	var raw = s.get_text(0).replace("📂 ", "").replace("📄 ", "")
	data.documents[d_id].title = raw
	s.set_editable(0, false)
	save_data(); build_docs_tree()

func _on_doc_text_changed():
	if current_doc_id != "" and data.documents.has(current_doc_id):
		data.documents[current_doc_id].content = docs_editor.text
		save_data()
