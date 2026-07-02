from __future__ import annotations

from dataclasses import dataclass
from math import hypot

Point = tuple[float, float]


@dataclass
class Country:
    id: int
    x: float
    y: float
    radius: int
    color: str
    owner: int | None
    units: int
    territory: list[Point]
    spawn_gap: int

    def contains(self, px: float, py: float) -> bool:
        return hypot(self.x - px, self.y - py) <= self.radius


@dataclass
class UnitGroup:
    source_id: int
    target_id: int
    owner: int
    x: float
    y: float
    units: int

    def move_toward(self, target: Country, distance: float) -> bool:
        dx = target.x - self.x
        dy = target.y - self.y
        remaining = hypot(dx, dy)
        if remaining <= distance or remaining <= target.radius:
            self.x = target.x
            self.y = target.y
            return True

        self.x += dx / remaining * distance
        self.y += dy / remaining * distance
        return False


@dataclass
class GameEvent:
    kind: str
    country_id: int
    value: int
    owner: int | None = None
