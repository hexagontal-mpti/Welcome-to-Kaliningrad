from __future__ import annotations

from typing import Any, Callable

from game.models import Country
from game.world import PLAYER_OWNER, World


Logger = Callable[[str], None]


class GameActions:
    def __init__(self, config: dict[str, Any], logger: Logger | None = None) -> None:
        self.config = config
        self.logger = logger
        self.world = World(config, logger=logger)
        self.selected_country_id: int | None = None
        self.drag_source_id: int | None = None
        self.drag_target_id: int | None = None
        self.drag_cursor: tuple[float, float] | None = None
        self.drag_chain: list[int] = []
        self.active_streams: list[dict[str, float | int]] = []
        self.paused = False

    def tick(self, delta_seconds: float) -> None:
        if self.paused or self.world.winner is not None or self.world.player_defeated:
            return
        self.world.update(delta_seconds)
        self._tick_stream(delta_seconds)

    def click_world(self, x: float, y: float) -> None:
        if self.config["controls"]["mode"] == "drag_stream":
            return
        if self.paused:
            self._log("click ignored: game is paused")
            return
        if self.world.winner is not None:
            self._log("click ignored: game already ended")
            return

        clicked = self.world.country_at(x, y)
        if clicked is None:
            self.clear_selection()
            return

        if clicked.owner == PLAYER_OWNER:
            self.select_country(clicked.id)
            return

        self.send_selected_to(clicked.id)

    def select_country(self, country_id: int) -> bool:
        country = self.world.country_by_id(country_id)
        if country is None or country.owner != PLAYER_OWNER:
            return False

        self.selected_country_id = country.id
        self._log(f"selected country #{country.id}")
        return True

    def send_selected_to(self, target_country_id: int) -> bool:
        if self.paused:
            self._log("send blocked: game is paused")
            return False

        source = self.selected_country()
        target = self.world.country_by_id(target_country_id)
        if source is None or target is None:
            return False

        sent = self.world.send_units(source, target)
        if sent:
            self._log(f"player sent units from #{source.id} to #{target.id}")
        return sent

    def start_drag(self, x: float, y: float) -> bool:
        if self.config["controls"]["mode"] != "drag_stream":
            self.click_world(x, y)
            return False
        if self.paused or self.world.winner is not None or self.world.player_defeated:
            self._log("drag ignored: paused or finished")
            return False

        source = self.world.country_at(x, y)
        if source is None or source.owner != PLAYER_OWNER:
            self.clear_drag()
            return False

        self.drag_source_id = source.id
        self.selected_country_id = source.id
        self.drag_cursor = (x, y)
        self.drag_target_id = None
        self.drag_chain = [source.id]
        self._log(f"drag started from #{source.id}")
        return True

    def update_drag(self, x: float, y: float) -> None:
        if self.drag_source_id is None:
            return
        self.drag_cursor = (x, y)
        target_id = self._target_country_id_at(x, y)
        self.drag_target_id = target_id
        if target_id is not None:
            self._maybe_extend_drag_chain(target_id)

    def finish_drag(self) -> bool:
        if not self.drag_chain:
            return False

        streams = self._drag_streams_to_target()
        target_id = self.drag_target_id
        self.clear_drag(keep_selection=True)
        if not streams:
            self._log("drag finished without target")
            return False

        for source_id, next_target_id in streams:
            self.active_streams.append(
                {
                    "source_id": source_id,
                    "target_id": next_target_id,
                    "timer": 0.0,
                }
            )
            self._log(f"stream started: #{source_id} -> #{next_target_id}")
        return True

    def clear_drag(self, keep_selection: bool = False) -> None:
        self.drag_source_id = None
        self.drag_target_id = None
        self.drag_cursor = None
        self.drag_chain = []
        if not keep_selection:
            self.active_streams = []

    def toggle_pause(self) -> None:
        if self.world.winner is None and not self.world.player_defeated:
            self.paused = not self.paused
            if self.paused:
                self.clear_drag()
            self._log(f"pause set to {self.paused}")

    def restart(self) -> None:
        self.world = World(self.config, logger=self.logger)
        self.selected_country_id = None
        self.drag_source_id = None
        self.drag_target_id = None
        self.drag_cursor = None
        self.drag_chain = []
        self.active_streams = []
        self.paused = False
        self._log("game restarted")

    def clear_selection(self) -> None:
        if self.selected_country_id is not None:
            self._log("selection cleared")
        self.selected_country_id = None
        self.clear_drag()

    def selected_country(self) -> Country | None:
        if self.selected_country_id is None:
            return None

        country = self.world.country_by_id(self.selected_country_id)
        if country is None or country.owner != PLAYER_OWNER:
            self.selected_country_id = None
            return None
        return country

    def drag_source(self) -> Country | None:
        if self.drag_source_id is None:
            return None
        country = self.world.country_by_id(self.drag_source_id)
        if country is None or country.owner != PLAYER_OWNER:
            self.clear_drag()
            return None
        return country

    def current_chain_source(self) -> Country | None:
        if not self.drag_chain:
            return self.drag_source()
        country = self.world.country_by_id(self.drag_chain[-1])
        if country is None or country.owner != PLAYER_OWNER:
            return self.drag_source()
        return country

    def drag_target(self) -> Country | None:
        if self.drag_target_id is None:
            return None
        return self.world.country_by_id(self.drag_target_id)

    def _target_country_id_at(self, x: float, y: float) -> int | None:
        controls_cfg = self.config["controls"]
        snap_radius = controls_cfg["target_snap_radius"]
        target = None
        best_distance = float("inf")

        for country in self.world.countries:
            if country.id == self.drag_source_id and not controls_cfg["allow_self_target"]:
                continue
            distance = ((country.x - x) ** 2 + (country.y - y) ** 2) ** 0.5
            if country.contains(x, y) or distance <= country.radius + snap_radius:
                if distance < best_distance:
                    target = country
                    best_distance = distance

        return target.id if target is not None else None

    def _maybe_extend_drag_chain(self, target_id: int) -> None:
        controls_cfg = self.config["controls"]
        if not controls_cfg["chain_through_owned_capitals"]:
            return
        if not self.drag_chain or target_id == self.drag_chain[-1]:
            return
        target = self.world.country_by_id(target_id)
        if target is None or target.owner != PLAYER_OWNER:
            return
        self.drag_chain.append(target_id)
        self.drag_source_id = target_id
        self.selected_country_id = target_id
        self._log(f"drag chained through #{target_id}")

    def _drag_streams_to_target(self) -> list[tuple[int, int]]:
        if self.drag_target_id is None or not self.drag_chain:
            return []
        target_id = self.drag_target_id
        if target_id in self.drag_chain:
            return []
        return [(source_id, target_id) for source_id in self.drag_chain]

    def _tick_stream(self, delta_seconds: float) -> None:
        if not self.active_streams:
            return

        interval = self.config["game"]["send_stream_interval_seconds"]
        still_active: list[dict[str, float | int]] = []
        for stream in self.active_streams:
            stream["timer"] = float(stream["timer"]) - delta_seconds
            active = True
            while active and float(stream["timer"]) <= 0:
                source = self.world.country_by_id(int(stream["source_id"]))
                target = self.world.country_by_id(int(stream["target_id"]))
                if source is None or target is None or source.owner != PLAYER_OWNER or source.units <= 1:
                    active = False
                    self._log("stream stopped")
                    break
                if not self.world.send_units(source, target):
                    active = False
                    self._log("stream stopped: send failed")
                    break
                stream["timer"] = float(stream["timer"]) + interval
            if active:
                still_active.append(stream)
        self.active_streams = still_active

    def _log(self, message: str) -> None:
        if self.logger is not None:
            self.logger(f"[actions] {message}")
