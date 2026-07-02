from __future__ import annotations

import tkinter as tk
import traceback
from time import perf_counter

from game.actions import GameActions
from game.config import load_config
from game.models import GameEvent
from game.models import Country
from game.stats import StatsStore
from game.world import PLAYER_OWNER


class CountryballsApp:
    def __init__(self, config_path: str) -> None:
        self.config = load_config(config_path)
        self.debug_enabled = self.config.get("debug", {}).get("enabled", False)
        self.actions = GameActions(self.config, logger=self._debug)
        self.stats = StatsStore(self.config)
        self.last_frame_time = perf_counter()
        self.float_texts: list[dict[str, float | str]] = []
        self.country_pulses: dict[int, float] = {}
        self.last_winner: int | None = None
        self.button_actions = {
            "pause": self.actions.toggle_pause,
            "restart": self._restart,
            "menu": self._return_to_menu,
        }

        window_cfg = self.config["window"]
        self.root = tk.Tk()
        self.root.title(window_cfg["title"])
        self.root.resizable(False, False)

        self.canvas = tk.Canvas(
            self.root,
            width=window_cfg["width"],
            height=window_cfg["height"],
            bg=window_cfg["background"],
            highlightthickness=0,
        )
        self.canvas.pack()
        self.menu_frame = tk.Frame(self.root, bg="#eef6f0")
        self.menu_content = self.menu_frame
        self.menu_vars: dict[str, tk.Variable] = {}
        self.menu_page = "main"
        self.screen = "menu" if self.config.get("menu", {}).get("start_screen", True) else "game"
        if self.screen == "menu":
            self._show_main_menu()
        else:
            self.stats.start_game()

        self.root.bind("<ButtonPress-1>", self._on_mouse_down)
        self.root.bind("<B1-Motion>", self._on_mouse_drag)
        self.root.bind("<ButtonRelease-1>", self._on_mouse_up)
        self.root.bind("<space>", self._toggle_pause)
        self.root.bind("<r>", self._restart)
        self.root.bind("<R>", self._restart)
        self.root.bind("<Escape>", self._clear_selection)
        self.root.bind("<MouseWheel>", self._on_mouse_wheel)

    def run(self) -> None:
        self._schedule_next_frame()
        self.root.mainloop()

    def _schedule_next_frame(self) -> None:
        frame_delay_ms = int(1000 / self.config["game"]["fps"])
        self.root.after(frame_delay_ms, self._tick)

    def _tick(self) -> None:
        try:
            now = perf_counter()
            delta = now - self.last_frame_time
            self.last_frame_time = now

            if self.screen == "game":
                self.actions.tick(delta)
                if not self.actions.paused and self.actions.world.winner is None:
                    self.stats.add_battle_time(delta)
                self._handle_world_events()
                self._update_animations(delta)
                self._handle_winner()

            self._draw()
        except Exception:
            if self.debug_enabled:
                traceback.print_exc()
            self.actions.paused = True
        finally:
            self._schedule_next_frame()

    def _on_mouse_down(self, event: tk.Event) -> None:
        stats_top = self.config["window"]["height"] - self.config["window"]["stats_height"]
        if self.screen != "game":
            return
        if event.y >= stats_top:
            self._handle_stats_click(event.x, event.y)
            return

        if self.config["controls"]["mode"] == "drag_stream":
            self.actions.start_drag(event.x, event.y)
        else:
            self.actions.click_world(event.x, event.y)

    def _on_mouse_drag(self, event: tk.Event) -> None:
        if self.screen == "game" and self.config["controls"]["mode"] == "drag_stream":
            self.actions.update_drag(event.x, event.y)

    def _on_mouse_up(self, _event: tk.Event) -> None:
        if self.screen == "game" and self.config["controls"]["mode"] == "drag_stream":
            self.actions.finish_drag()

    def _handle_stats_click(self, x: float, y: float) -> None:
        _ = y
        width = self.config["window"]["width"]
        if width - 342 <= x <= width - 242:
            self.button_actions["menu"]()
        elif width - 230 <= x <= width - 130:
            self.button_actions["pause"]()
        elif width - 118 <= x <= width - 18:
            self.button_actions["restart"]()

    def _toggle_pause(self, _event: tk.Event | None = None) -> None:
        self.actions.toggle_pause()

    def _restart(self, _event: tk.Event | None = None) -> None:
        self.stats.flush()
        self.actions.restart()
        if self.screen == "game":
            self.stats.start_game()
        self.float_texts = []
        self.country_pulses = {}
        self.last_winner = None
        self.last_frame_time = perf_counter()

    def _clear_selection(self, _event: tk.Event | None = None) -> None:
        if self.screen == "menu":
            if self.menu_page != "main":
                self._show_main_menu()
            return
        self._return_to_menu()

    def _return_to_menu(self) -> None:
        self.stats.flush()
        self.actions.paused = True
        self.actions.clear_selection()
        self.actions.active_streams = []
        self.actions.world.ai_streams = []
        self.screen = "menu"
        self._show_main_menu()
        self.actions.clear_selection()

    def _selected_country(self) -> Country | None:
        return self.actions.selected_country()

    def _draw(self) -> None:
        self.canvas.delete("all")
        if self.screen != "game":
            self._draw_menu_background()
            return
        self._draw_island()
        self._draw_territories()
        self._draw_unit_groups()
        self._draw_active_stream_arrows()
        self._draw_drag_arrows()
        for country in self.actions.world.countries:
            self._draw_country(country)
        self._draw_float_texts()
        self._draw_stats_bar()
        self._draw_overlay_text()

    def _draw_island(self) -> None:
        island_cfg = self.config["island"]
        points = [coordinate for point in self.actions.world.island for coordinate in point]
        shadow_points = [
            coordinate + (7 if index % 2 == 0 else 9)
            for index, coordinate in enumerate(points)
        ]
        self.canvas.create_polygon(
            shadow_points,
            fill=island_cfg["coast_shadow_color"],
            outline="",
            smooth=True,
        )
        self.canvas.create_polygon(
            points,
            fill=island_cfg["fill_color"],
            outline=island_cfg["outline_color"],
            width=3,
            smooth=True,
        )

    def _draw_territories(self) -> None:
        outline = self.config["country"]["territory_outline_color"]
        for country in self.actions.world.countries:
            fill = self._territory_color(country.owner)
            points = [coordinate for point in country.territory for coordinate in point]
            self.canvas.create_polygon(
                points,
                fill=fill,
                outline=outline,
                width=1,
                smooth=False,
            )

    def _draw_active_stream_arrows(self) -> None:
        for stream in self.actions.active_streams:
            source = self.actions.world.country_by_id(int(stream["source_id"]))
            target = self.actions.world.country_by_id(int(stream["target_id"]))
            if source is None or target is None:
                continue
            self._draw_arrow_between(source, target, self.config["graphics"]["chain_arrow_color"], dashed=True, width=2)
        for stream in self.actions.world.ai_streams:
            source = self.actions.world.country_by_id(int(stream["source_id"]))
            target = self.actions.world.country_by_id(int(stream["target_id"]))
            if source is None or target is None:
                continue
            self._draw_arrow_between(source, target, self.config["graphics"]["arrow_color"], dashed=True, width=2)

    def _draw_drag_arrows(self) -> None:
        chain = self.actions.drag_chain
        for index in range(len(chain) - 1):
            source = self.actions.world.country_by_id(chain[index])
            target = self.actions.world.country_by_id(chain[index + 1])
            if source is not None and target is not None:
                self._draw_arrow_between(source, target, self.config["graphics"]["chain_arrow_color"], dashed=False)

        source = self.actions.current_chain_source()
        cursor = self.actions.drag_cursor
        if source is None or cursor is None:
            return

        target = self.actions.drag_target()
        if target is not None and chain and target.id == chain[-1]:
            target = None
        end_x, end_y = (target.x, target.y) if target is not None else cursor
        self._draw_arrow_coordinates(source, end_x, end_y, target)

    def _draw_arrow_between(self, source: Country, target: Country, color: str, dashed: bool, width: int | None = None) -> None:
        self._draw_arrow_coordinates(source, target.x, target.y, target, color=color, dashed=dashed, width=width)

    def _draw_arrow_coordinates(
        self,
        source: Country,
        end_x: float,
        end_y: float,
        target: Country | None,
        color: str | None = None,
        dashed: bool = True,
        width: int | None = None,
    ) -> None:
        dx = end_x - source.x
        dy = end_y - source.y
        distance = (dx * dx + dy * dy) ** 0.5
        if distance <= 1:
            return

        start_x = source.x + dx / distance * (source.radius + 8)
        start_y = source.y + dy / distance * (source.radius + 8)
        end_padding = (target.radius + 10) if target is not None else 0
        line_end_x = end_x - dx / distance * end_padding
        line_end_y = end_y - dy / distance * end_padding
        graphics_cfg = self.config["graphics"]
        color = color or (graphics_cfg["arrow_target_color"] if target is not None else graphics_cfg["arrow_color"])
        line_width = width or graphics_cfg["arrow_width"]

        self.canvas.create_line(
            start_x + 2,
            start_y + 3,
            line_end_x + 2,
            line_end_y + 3,
            fill="#f8fafc",
            width=line_width + 3,
            arrow=tk.LAST,
            arrowshape=(20, 24, 8),
            capstyle=tk.ROUND,
            smooth=True,
        )
        self.canvas.create_line(
            start_x,
            start_y,
            line_end_x,
            line_end_y,
            fill=color,
            width=line_width,
            arrow=tk.LAST,
            arrowshape=(20, 24, 8),
            capstyle=tk.ROUND,
            dash=(graphics_cfg["arrow_dash"], 8) if dashed else None,
            smooth=True,
        )

    def _draw_country(self, country: Country) -> None:
        cfg = self.config["country"]
        is_selected = country.id == self.actions.selected_country_id
        is_target = country.id == self.actions.drag_target_id
        is_chain = country.id in self.actions.drag_chain
        if is_target:
            outline = cfg["target_outline_color"]
        elif is_chain:
            outline = cfg["chain_outline_color"]
        elif is_selected:
            outline = cfg["selected_outline_color"]
        else:
            outline = cfg["outline_color"]
        outline_width = 6 if is_target else 5 if is_selected or is_chain else 2
        pulse = self.country_pulses.get(country.id, 0.0)
        pulse_scale = 1.0 + 0.08 * (pulse / self.config["graphics"]["pulse_seconds"]) if pulse > 0 else 1.0
        draw_radius = country.radius * pulse_scale
        x0 = country.x - draw_radius
        y0 = country.y - draw_radius
        x1 = country.x + draw_radius
        y1 = country.y + draw_radius

        self.canvas.create_oval(
            x0 + 5,
            y0 + 7,
            x1 + 5,
            y1 + 7,
            fill=self.config["graphics"]["capital_shadow_color"],
            outline="",
        )
        self.canvas.create_oval(x0, y0, x1, y1, fill=country.color, outline=outline, width=outline_width)
        if country.owner == PLAYER_OWNER and self.config["country"]["player_flag_enabled"]:
            self._draw_player_flag(country)
        highlight_color = self._blend_with_color(country.color, "#ffffff", 0.34)
        self.canvas.create_oval(
            country.x - country.radius * 0.68,
            country.y - country.radius * 0.78,
            country.x + country.radius * 0.45,
            country.y - country.radius * 0.02,
            fill=highlight_color,
            outline="",
        )
        self._draw_countryball_eyes(country)
        self.canvas.create_text(
            country.x,
            country.y + country.radius * 0.35,
            text=str(country.units),
            fill="#111111",
            font=("Arial", 14, "bold"),
        )

    def _draw_player_flag(self, country: Country) -> None:
        width = country.radius * 1.15
        height = country.radius * 0.5
        x0 = country.x - width / 2
        y0 = country.y - height / 2
        self.canvas.create_rectangle(
            x0,
            y0,
            x0 + width,
            y0 + height / 2,
            fill=self.config["country"]["player_flag_primary"],
            outline="",
        )
        self.canvas.create_rectangle(
            x0,
            y0 + height / 2,
            x0 + width,
            y0 + height,
            fill=self.config["country"]["player_flag_secondary"],
            outline="",
        )

    def _draw_countryball_eyes(self, country: Country) -> None:
        eye_radius = max(4, int(country.radius * 0.16))
        offset_x = country.radius * 0.28
        offset_y = country.radius * 0.22
        for direction in (-1, 1):
            cx = country.x + offset_x * direction
            cy = country.y - offset_y
            self.canvas.create_oval(
                cx - eye_radius,
                cy - eye_radius,
                cx + eye_radius,
                cy + eye_radius,
                fill="#ffffff",
                outline="#222222",
                width=1,
            )
            self.canvas.create_oval(
                cx - 2,
                cy - 2,
                cx + 2,
                cy + 2,
                fill="#111111",
                outline="#111111",
            )

    def _draw_unit_groups(self) -> None:
        for group in self.actions.world.unit_groups:
            color = self._owner_color(group.owner)
            radius = 10
            self.canvas.create_oval(
                group.x - radius + 3,
                group.y - radius + 4,
                group.x + radius + 3,
                group.y + radius + 4,
                fill=self.config["graphics"]["unit_shadow_color"],
                outline="",
            )
            self.canvas.create_oval(
                group.x - radius,
                group.y - radius,
                group.x + radius,
                group.y + radius,
                fill=color,
                outline="#222222",
                width=2,
            )

    def _draw_stats_bar(self) -> None:
        window_cfg = self.config["window"]
        top = window_cfg["height"] - window_cfg["stats_height"]
        self.canvas.create_rectangle(0, top, window_cfg["width"], window_cfg["height"], fill="#1f2933", outline="")

        stats = (
            f"Time: {int(self.actions.world.elapsed_seconds)}s"
            f"   Owners: {self.actions.world.active_owner_count}"
            f"   Territories: {len(self.actions.world.countries)}"
            f"   Your units: {self.actions.world.player_units}"
            f"   Wins: {self.stats.data['wins']}/{self.stats.data['games']}"
            f"   Captured: {self.stats.data['territories_captured']}"
        )
        self.canvas.create_text(
            18,
            top + window_cfg["stats_height"] / 2,
            text=stats,
            fill="#ffffff",
            anchor="w",
            font=("Arial", 13, "bold"),
        )
        self._draw_stats_button(window_cfg["width"] - 342, top + 9, 100, "Menu")
        self._draw_stats_button(window_cfg["width"] - 230, top + 9, 100, "Pause" if not self.actions.paused else "Resume")
        self._draw_stats_button(window_cfg["width"] - 118, top + 9, 100, "Restart")

    def _draw_stats_button(self, x: int, y: int, width: int, text: str) -> None:
        self.canvas.create_rectangle(
            x,
            y,
            x + width,
            y + 30,
            fill="#f4f0e8",
            outline="#111111",
            width=2,
        )
        self.canvas.create_text(
            x + width / 2,
            y + 15,
            text=text,
            fill="#111111",
            font=("Arial", 11, "bold"),
        )

    def _draw_float_texts(self) -> None:
        for item in self.float_texts:
            lifetime = self.config["graphics"]["float_text_seconds"]
            alpha_progress = float(item["time"]) / lifetime
            y = float(item["y"]) - (1.0 - alpha_progress) * 18
            self.canvas.create_text(
                float(item["x"]),
                y,
                text=str(item["text"]),
                fill=str(item["color"]),
                font=("Arial", 12, "bold"),
            )

    def _draw_overlay_text(self) -> None:
        winner = self.actions.world.winner
        if self.actions.world.player_defeated:
            text = "Game over. Press R to restart."
        elif winner is None:
            return
        else:
            text = "You won! Press R to restart." if winner == PLAYER_OWNER else "Game over. Press R to restart."
        self.canvas.create_text(
            self.config["window"]["width"] / 2,
            40,
            text=text,
            fill="#111111",
            font=("Arial", 22, "bold"),
        )

    def _owner_color(self, owner: int | None) -> str:
        if owner == PLAYER_OWNER:
            return self.config["country"]["player_color"]
        if owner is None:
            return self.config["country"]["neutral_color"]
        colors = self.config["country"]["neutral_colors"]
        return colors[(owner - 1) % len(colors)]

    def _territory_color(self, owner: int | None) -> str:
        return self._blend_with_background(self._owner_color(owner), self.config["graphics"]["territory_background_blend"])

    def _blend_with_background(self, color: str, background_ratio: float) -> str:
        background = self.config["island"]["fill_color"]
        return self._blend_with_color(color, background, background_ratio)

    def _blend_with_color(self, color: str, target: str, target_ratio: float) -> str:
        cr, cg, cb = self._hex_to_rgb(color)
        br, bg, bb = self._hex_to_rgb(target)
        ratio = max(0.0, min(1.0, target_ratio))
        red = int(cr * (1 - ratio) + br * ratio)
        green = int(cg * (1 - ratio) + bg * ratio)
        blue = int(cb * (1 - ratio) + bb * ratio)
        return f"#{red:02x}{green:02x}{blue:02x}"

    def _hex_to_rgb(self, color: str) -> tuple[int, int, int]:
        value = color.lstrip("#")
        return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)

    def _handle_world_events(self) -> None:
        for event in self.actions.world.drain_events():
            self._handle_world_event(event)

    def _handle_world_event(self, event: GameEvent) -> None:
        country = self.actions.world.country_by_id(event.country_id)
        if country is None:
            return
        if event.kind == "capture":
            self.stats.record_capture(event.owner, PLAYER_OWNER)
            self.country_pulses[event.country_id] = self.config["graphics"]["pulse_seconds"]
        if event.kind == "units" and event.value != 0:
            color = "#166534" if event.value > 0 else "#991b1b"
            sign = "+" if event.value > 0 else ""
            self.float_texts.append(
                {
                    "x": country.x,
                    "y": country.y - country.radius - 10,
                    "time": self.config["graphics"]["float_text_seconds"],
                    "text": f"{sign}{event.value}",
                    "color": color,
                }
            )
            self.country_pulses[event.country_id] = self.config["graphics"]["pulse_seconds"]

    def _update_animations(self, delta: float) -> None:
        self.float_texts = [
            {**item, "time": float(item["time"]) - delta}
            for item in self.float_texts
            if float(item["time"]) - delta > 0
        ]
        self.country_pulses = {
            country_id: time_left - delta
            for country_id, time_left in self.country_pulses.items()
            if time_left - delta > 0
        }

    def _handle_winner(self) -> None:
        winner = self.actions.world.winner
        if winner is not None and self.last_winner is None:
            self.last_winner = winner
            self.stats.record_game_end(winner, PLAYER_OWNER)

    def _draw_menu_background(self) -> None:
        window_cfg = self.config["window"]
        self.canvas.create_rectangle(0, 0, window_cfg["width"], window_cfg["height"], fill="#dcebf2", outline="")
        self.canvas.create_oval(120, 120, 880, 620, fill="#edf3df", outline="#6d8f77", width=3)
        self.canvas.create_text(
            window_cfg["width"] / 2,
            90,
            text="Countryballs Conquest",
            fill="#14213d",
            font=("Arial", 30, "bold"),
        )

    def _show_main_menu(self) -> None:
        self.screen = "menu"
        self.menu_page = "main"
        self._clear_menu()
        self._menu_title("Countryballs Conquest")
        self._menu_button("Play", self._show_play_menu)
        self._menu_button("Settings", self._show_settings_menu)
        self._menu_button("Quick Start", self._start_game_from_menu)
        self._menu_label(
            f"Games: {self.stats.data['games']}   Wins: {self.stats.data['wins']}   "
            f"Captured: {self.stats.data['territories_captured']}"
        )

    def _show_play_menu(self) -> None:
        self.screen = "menu"
        self.menu_page = "play"
        self._clear_menu()
        self._menu_title("Play Setup")
        self._scale("Opponents", "game.opponent_count", 1, 9)
        self._scale("Player start units", "game.player_initial_units_max", 5, 60)
        self._scale("Bot start units", "game.bot_initial_units_max", 5, 60)
        self._scale("Neutral territories", "game.neutral_territory_count", 0, 8)
        self._menu_button("Start Game", self._start_game_from_menu)
        self._menu_button("Back", self._show_main_menu)

    def _show_settings_menu(self) -> None:
        self.screen = "menu"
        self.menu_page = "settings"
        self._clear_menu()
        self._menu_title("Settings")
        self._scale("Initial unit spread min", "game.initial_unit_spread_min", 1, 30)
        self._scale("Initial unit spread max", "game.initial_unit_spread_max", 5, 80)
        self._scale("Territory count min", "game.initial_territory_count_min", 2, 12)
        self._scale("Territory count max", "game.initial_territory_count_max", 3, 16)
        self._scale("Flight speed", "game.unit_group_speed_pixels_per_second", 60, 320)
        self._scale("Player growth", "game.player_units_per_growth", 1, 5)
        self._scale("Bot growth", "game.bot_units_per_growth", 1, 5)
        self._scale("Player unit multiplier", "game.player_unit_multiplier", 1, 3, resolution=0.1)
        self._option("AI mode", "ai.mode", ("medium", "aggressive"))
        self._check("Flag skins", "country.player_flag_enabled")
        self._color_entry("Player color", "country.player_color")
        self._color_entry("Flag primary", "country.player_flag_primary")
        self._color_entry("Flag secondary", "country.player_flag_secondary")
        self._menu_button("Apply", self._apply_menu_config)
        self._menu_button("Back", self._show_main_menu)

    def _start_game_from_menu(self) -> None:
        self._apply_menu_config()
        self.screen = "game"
        self.menu_frame.place_forget()
        self._restart()

    def _apply_menu_config(self) -> None:
        for path, var in self.menu_vars.items():
            self._set_config_value(path, var.get())
        self.config["game"]["country_count"] = int(self.config["game"]["opponent_count"]) + 1
        self.config["game"]["player_initial_units_min"] = min(
            int(self.config["game"]["player_initial_units_min"]),
            int(self.config["game"]["player_initial_units_max"]),
        )
        self.config["game"]["bot_initial_units_min"] = min(
            int(self.config["game"]["bot_initial_units_min"]),
            int(self.config["game"]["bot_initial_units_max"]),
        )

    def _clear_menu(self) -> None:
        for child in self.menu_frame.winfo_children():
            child.destroy()
        self.menu_vars = {}
        self.menu_frame.place(relx=0.5, rely=0.52, anchor="center", width=500, height=520)
        holder = tk.Canvas(self.menu_frame, bg="#eef6f0", highlightthickness=0)
        scrollbar = tk.Scrollbar(self.menu_frame, orient=tk.VERTICAL, command=holder.yview)
        self.menu_content = tk.Frame(holder, bg="#eef6f0")
        window_id = holder.create_window((0, 0), window=self.menu_content, anchor="nw", width=480)
        holder.configure(yscrollcommand=scrollbar.set)
        holder.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        def update_scroll_region(_event: tk.Event) -> None:
            holder.configure(scrollregion=holder.bbox("all"))

        def update_inner_width(event: tk.Event) -> None:
            holder.itemconfigure(window_id, width=event.width)

        self.menu_content.bind("<Configure>", update_scroll_region)
        holder.bind("<Configure>", update_inner_width)

    def _menu_title(self, text: str) -> None:
        tk.Label(self.menu_content, text=text, bg="#eef6f0", fg="#14213d", font=("Arial", 22, "bold")).pack(pady=(18, 12))

    def _menu_label(self, text: str) -> None:
        tk.Label(self.menu_content, text=text, bg="#eef6f0", fg="#334155", font=("Arial", 11)).pack(pady=8)

    def _menu_button(self, text: str, command: object) -> None:
        tk.Button(self.menu_content, text=text, command=command, font=("Arial", 12, "bold"), width=22).pack(pady=6)

    def _scale(self, label: str, path: str, from_: float, to: float, resolution: float = 1) -> None:
        value = self._get_config_value(path)
        var = tk.DoubleVar(value=value) if resolution != 1 else tk.IntVar(value=int(value))
        self.menu_vars[path] = var
        tk.Label(self.menu_content, text=label, bg="#eef6f0", fg="#1f2937", font=("Arial", 10, "bold")).pack(anchor="w", padx=24)
        tk.Scale(
            self.menu_content,
            from_=from_,
            to=to,
            resolution=resolution,
            orient=tk.HORIZONTAL,
            variable=var,
            bg="#eef6f0",
            highlightthickness=0,
        ).pack(fill="x", padx=24)

    def _option(self, label: str, path: str, options: tuple[str, ...]) -> None:
        var = tk.StringVar(value=str(self._get_config_value(path)))
        self.menu_vars[path] = var
        tk.Label(self.menu_content, text=label, bg="#eef6f0", fg="#1f2937", font=("Arial", 10, "bold")).pack(anchor="w", padx=24)
        tk.OptionMenu(self.menu_content, var, *options).pack(fill="x", padx=24, pady=2)

    def _check(self, label: str, path: str) -> None:
        var = tk.BooleanVar(value=bool(self._get_config_value(path)))
        self.menu_vars[path] = var
        tk.Checkbutton(self.menu_content, text=label, variable=var, bg="#eef6f0", fg="#1f2937").pack(anchor="w", padx=24)

    def _color_entry(self, label: str, path: str) -> None:
        var = tk.StringVar(value=str(self._get_config_value(path)))
        self.menu_vars[path] = var
        tk.Label(self.menu_content, text=label, bg="#eef6f0", fg="#1f2937", font=("Arial", 10, "bold")).pack(anchor="w", padx=24)
        tk.Entry(self.menu_content, textvariable=var).pack(fill="x", padx=24, pady=2)

    def _on_mouse_wheel(self, event: tk.Event) -> None:
        if self.screen != "menu":
            return
        for child in self.menu_frame.winfo_children():
            if isinstance(child, tk.Canvas):
                child.yview_scroll(int(-1 * (event.delta / 120)), "units")
                break

    def _get_config_value(self, path: str) -> object:
        current = self.config
        for part in path.split("."):
            current = current[part]
        return current

    def _set_config_value(self, path: str, value: object) -> None:
        current = self.config
        parts = path.split(".")
        for part in parts[:-1]:
            current = current[part]
        current[parts[-1]] = value

    def _debug(self, message: str) -> None:
        if self.debug_enabled:
            print(message)
