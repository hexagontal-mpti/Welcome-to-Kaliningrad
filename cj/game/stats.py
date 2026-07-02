from __future__ import annotations

import json
from pathlib import Path
from typing import Any


DEFAULT_STATS = {
    "games": 0,
    "wins": 0,
    "battle_time_seconds": 0.0,
    "territories_captured": 0,
}


class StatsStore:
    def __init__(self, config: dict[str, Any]) -> None:
        stats_cfg = config.get("stats", {})
        self.enabled = stats_cfg.get("enabled", True)
        self.path = Path(stats_cfg.get("file", "work/stats.json"))
        self.data = self._load()

    def start_game(self) -> None:
        self.data["games"] += 1
        self._save()

    def add_battle_time(self, seconds: float) -> None:
        self.data["battle_time_seconds"] += seconds

    def record_capture(self, owner: int | None, player_owner: int) -> None:
        if owner == player_owner:
            self.data["territories_captured"] += 1
            self._save()

    def record_game_end(self, winner: int | None, player_owner: int) -> None:
        if winner == player_owner:
            self.data["wins"] += 1
        self._save()

    def flush(self) -> None:
        self._save()

    def _load(self) -> dict[str, Any]:
        if not self.enabled or not self.path.exists():
            return dict(DEFAULT_STATS)
        with self.path.open("r", encoding="utf-8") as file:
            loaded = json.load(file)
        data = dict(DEFAULT_STATS)
        data.update(loaded)
        return data

    def _save(self) -> None:
        if not self.enabled:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w", encoding="utf-8") as file:
            json.dump(self.data, file, indent=2)
