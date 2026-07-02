from __future__ import annotations

import random
from math import atan2, cos, hypot, pi, sin, sqrt
from typing import Any, Callable

from game.models import Country, GameEvent, Point, UnitGroup


PLAYER_OWNER = 0
Logger = Callable[[str], None]


class World:
    def __init__(self, config: dict[str, Any], logger: Logger | None = None) -> None:
        self.config = config
        self.logger = logger
        seed = config["game"].get("random_seed")
        self.random = random.Random(seed)
        self.play_width = config["window"]["width"]
        self.play_height = config["window"]["height"] - config["window"]["stats_height"]
        self.island: list[Point] = []
        self.countries: list[Country] = []
        self.unit_groups: list[UnitGroup] = []
        self.ai_streams: list[dict[str, float | int]] = []
        self.events: list[GameEvent] = []
        self.elapsed_seconds = 0.0
        self._growth_timer = 0.0
        self._ai_timer = 0.0
        self._generate_countries()
        self._schedule_next_ai()
        self._log(f"world generated: {len(self.countries)} territories")

    @property
    def player_units(self) -> int:
        stationary = sum(country.units for country in self.countries if country.owner == PLAYER_OWNER)
        moving = sum(group.units for group in self.unit_groups if group.owner == PLAYER_OWNER)
        return stationary + moving

    @property
    def active_owner_count(self) -> int:
        return len({country.owner for country in self.countries if country.owner is not None})

    @property
    def winner(self) -> int | None:
        occupied = [country for country in self.countries if country.owner is not None]
        if len(occupied) != len(self.countries):
            return None
        owners = {country.owner for country in occupied}
        return next(iter(owners)) if len(owners) == 1 else None

    @property
    def player_defeated(self) -> bool:
        return not any(country.owner == PLAYER_OWNER for country in self.countries)

    def country_at(self, x: float, y: float) -> Country | None:
        for country in reversed(self.countries):
            if country.contains(x, y):
                return country
        return None

    def country_by_id(self, country_id: int) -> Country | None:
        for country in self.countries:
            if country.id == country_id:
                return country
        return None

    def send_units(self, source: Country, target: Country) -> bool:
        if source.id == target.id or source.owner is None or source.units < 2:
            return False

        units_to_send = min(self.config["game"]["send_units_per_tick"], source.units - 1)

        self._set_country_units(source, source.units - units_to_send, "send")
        self.unit_groups.append(
            UnitGroup(
                source_id=source.id,
                target_id=target.id,
                owner=source.owner,
                x=source.x,
                y=source.y,
                units=units_to_send,
            )
        )
        self._log(f"send: owner {source.owner} #{source.id} -> #{target.id}, units={units_to_send}")
        return True

    def drain_events(self) -> list[GameEvent]:
        events = self.events
        self.events = []
        return events

    def update(self, delta_seconds: float) -> None:
        self.elapsed_seconds += delta_seconds
        self._update_growth(delta_seconds)
        self._update_unit_groups(delta_seconds)
        self._update_ai_streams(delta_seconds)
        self._update_ai(delta_seconds)

    def _update_growth(self, delta_seconds: float) -> None:
        game_cfg = self.config["game"]
        self._growth_timer += delta_seconds
        interval = game_cfg["units_growth_interval_seconds"]
        while self._growth_timer >= interval:
            self._growth_timer -= interval
            for country in self.countries:
                if country.owner is None:
                    continue
                if country.units >= game_cfg["auto_growth_unit_cap"]:
                    continue
                growth = self._growth_for_owner(country.owner)
                self._set_country_units(
                    country,
                    min(game_cfg["auto_growth_unit_cap"], country.units + growth),
                    "growth",
                )

    def _update_unit_groups(self, delta_seconds: float) -> None:
        speed = self.config["game"]["unit_group_speed_pixels_per_second"]
        distance = speed * delta_seconds
        arrived: list[UnitGroup] = []

        for group in self.unit_groups:
            target = self.country_by_id(group.target_id)
            if target is None:
                arrived.append(group)
            elif group.move_toward(target, distance):
                self._resolve_arrival(group, target)
                arrived.append(group)

        if arrived:
            arrived_ids = {id(group) for group in arrived}
            self.unit_groups = [group for group in self.unit_groups if id(group) not in arrived_ids]

    def _resolve_arrival(self, group: UnitGroup, target: Country) -> None:
        if target.owner == group.owner:
            self._set_country_units(target, target.units + group.units, "reinforce")
            self._log(f"reinforce: owner {group.owner} #{target.id}, +{group.units}")
            return

        remaining_units = target.units - group.units
        self._log(f"attack: owner {group.owner} -> #{target.id}, remaining target units={remaining_units}")
        if remaining_units <= 0:
            target.owner = group.owner
            target.color = self._color_for_owner(group.owner)
            self._set_country_units(target, max(1, abs(remaining_units)), "capture")
            self.events.append(GameEvent("capture", target.id, target.units, owner=group.owner))
            self._log(f"capture: owner {group.owner} captured #{target.id}")
        else:
            self._set_country_units(target, remaining_units, "attack")

    def _update_ai(self, delta_seconds: float) -> None:
        ai_cfg = self.config["ai"]
        if not ai_cfg["enabled"]:
            return

        self._ai_timer -= delta_seconds
        if self._ai_timer > 0:
            return

        self._run_ai_turn()
        self._schedule_next_ai()

    def _run_ai_turn(self) -> bool:
        ai_cfg = self.config["ai"]
        min_units = max(2, ai_cfg["min_units_to_send"] + self._ai_min_units_adjustment())
        candidates = [
            country
            for country in self.countries
            if country.owner not in (None, PLAYER_OWNER) and country.units >= min_units
        ]
        if not candidates:
            self._log("ai turn skipped: no source")
            return False

        source = self._choose_ai_source(candidates)
        targets = [country for country in self.countries if country.id != source.id]
        if not targets:
            self._log("ai turn skipped: no target")
            return False

        target = self._choose_ai_target(source, targets)
        self.ai_streams.append({"source_id": source.id, "target_id": target.id, "timer": 0.0})
        self._log(f"ai stream started: #{source.id} -> #{target.id}")
        return True

    def _schedule_next_ai(self) -> None:
        ai_cfg = self.config["ai"]
        interval = self.random.uniform(
            ai_cfg["send_interval_min_seconds"],
            ai_cfg["send_interval_max_seconds"],
        )
        if ai_cfg.get("mode") == "aggressive":
            interval *= ai_cfg["aggressive_interval_multiplier"]
        self._ai_timer = interval

    def _update_ai_streams(self, delta_seconds: float) -> None:
        if not self.ai_streams:
            return

        interval = self.config["game"]["send_stream_interval_seconds"]
        still_active: list[dict[str, float | int]] = []
        for stream in self.ai_streams:
            stream["timer"] = float(stream["timer"]) - delta_seconds
            active = True
            while active and float(stream["timer"]) <= 0:
                source = self.country_by_id(int(stream["source_id"]))
                target = self.country_by_id(int(stream["target_id"]))
                if source is None or target is None or source.owner in (None, PLAYER_OWNER) or source.units <= 1:
                    active = False
                    break
                if not self.send_units(source, target):
                    active = False
                    break
                stream["timer"] = float(stream["timer"]) + interval
            if active:
                still_active.append(stream)
        self.ai_streams = still_active

    def _generate_countries(self) -> None:
        game_cfg = self.config["game"]
        self.island = self._create_island_polygon(self.play_width, self.play_height)

        for country_id in range(game_cfg["country_count"]):
            owner = PLAYER_OWNER if country_id == game_cfg["player_country_index"] else country_id
            units = self._initial_units_for_owner(owner)
            country = self._create_country(country_id, owner, units)
            self.countries.append(country)

        first_neutral_id = game_cfg["country_count"]
        for index in range(game_cfg["neutral_territory_count"]):
            country_id = first_neutral_id + index
            country = self._create_country(
                country_id,
                owner=None,
                units=game_cfg["neutral_territory_cost"],
            )
            self.countries.append(country)

        self._assign_voronoi_territories()

    def _create_country(
        self,
        country_id: int,
        owner: int | None,
        units: int,
    ) -> Country:
        game_cfg = self.config["game"]
        country_cfg = self.config["country"]
        radius = country_cfg["initial_radius"]
        spawn_gap = self.random.randint(game_cfg["safe_spawn_gap_min"], game_cfg["safe_spawn_gap_max"])

        for _ in range(game_cfg["generation_attempts"]):
            x, y = self._random_point_in_island()
            if self._has_room(x, y, radius, spawn_gap):
                break
        else:
            x, y = self._random_point_in_island()

        country = Country(
            id=country_id,
            x=x,
            y=y,
            radius=radius,
            color=self._color_for_owner(owner) if owner is not None else country_cfg["neutral_color"],
            owner=owner,
            units=units,
            territory=[],
            spawn_gap=spawn_gap,
        )
        self._sync_country_radius(country)
        return country

    def _has_room(self, x: float, y: float, radius: int, spawn_gap: int) -> bool:
        for country in self.countries:
            required = radius + country.radius + max(spawn_gap, country.spawn_gap)
            if hypot(country.x - x, country.y - y) < required:
                return False
        return True

    def _color_for_owner(self, owner: int) -> str:
        country_cfg = self.config["country"]
        if owner == PLAYER_OWNER:
            return country_cfg["player_color"]
        colors = country_cfg["neutral_colors"]
        return colors[(owner - 1) % len(colors)]

    def _initial_units_for_owner(self, owner: int) -> int:
        game_cfg = self.config["game"]
        if owner == PLAYER_OWNER:
            units = self.random.randint(
                game_cfg["player_initial_units_min"],
                max(game_cfg["player_initial_units_min"], game_cfg["player_initial_units_max"]),
            )
            return max(1, int(units * game_cfg["player_unit_multiplier"]))
        return self.random.randint(
            game_cfg["bot_initial_units_min"],
            max(game_cfg["bot_initial_units_min"], game_cfg["bot_initial_units_max"]),
        )

    def _growth_for_owner(self, owner: int | None) -> int:
        if owner == PLAYER_OWNER:
            return self.config["game"]["player_units_per_growth"]
        return self.config["game"]["bot_units_per_growth"]

    def _ai_min_units_adjustment(self) -> int:
        ai_cfg = self.config["ai"]
        if ai_cfg.get("mode") == "aggressive":
            return ai_cfg["aggressive_min_units_bonus"]
        return 0

    def _choose_ai_source(self, candidates: list[Country]) -> Country:
        if self.config["ai"].get("mode") == "aggressive":
            return max(candidates, key=lambda country: country.units)
        return self.random.choice(candidates)

    def _choose_ai_target(self, source: Country, targets: list[Country]) -> Country:
        if self.config["ai"].get("mode") == "aggressive":
            enemy_targets = [country for country in targets if country.owner != source.owner]
            if enemy_targets:
                return min(enemy_targets, key=lambda country: country.units)
        source_neighbors = sorted(
            targets,
            key=lambda country: (country.x - source.x) ** 2 + (country.y - source.y) ** 2,
        )
        return self.random.choice(source_neighbors[: min(3, len(source_neighbors))])

    def _set_country_units(self, country: Country, units: int, reason: str) -> None:
        old_units = country.units
        old_radius = country.radius
        country.units = max(0, min(self.config["game"]["max_units_per_country"], units))
        self._sync_country_radius(country)
        if old_units != country.units or old_radius != country.radius:
            self.events.append(GameEvent("units", country.id, country.units - old_units, owner=country.owner))
            self._log(
                f"units {reason}: #{country.id} {old_units}->{country.units}, "
                f"radius {old_radius}->{country.radius}"
            )

    def _sync_country_radius(self, country: Country) -> None:
        country_cfg = self.config["country"]
        initial = country_cfg["initial_radius"]
        maximum = country_cfg["max_radius"]
        visual_units = country_cfg["visual_units_for_max_radius"]
        unit_ratio = min(country.units, visual_units) / visual_units
        target_radius = initial + (maximum - initial) * sqrt(unit_ratio)
        country.radius = max(initial, min(maximum, int(target_radius)))

    def _create_island_polygon(self, width: int, height: int) -> list[Point]:
        island_cfg = self.config["island"]
        center_x = width * island_cfg["center_x_ratio"]
        center_y = height * island_cfg["center_y_ratio"]
        radius_x = width * island_cfg["radius_x_ratio"]
        radius_y = height * island_cfg["radius_y_ratio"]
        points: list[Point] = []
        for index in range(island_cfg["vertex_count"]):
            angle = pi * 2 * index / island_cfg["vertex_count"]
            noise = self.random.uniform(island_cfg["noise_min"], island_cfg["noise_max"])
            x = center_x + cos(angle) * radius_x * noise
            y = center_y + sin(angle) * radius_y * noise
            points.append((x, y))
        return points

    def _random_point_in_island(self) -> Point:
        min_x = int(min(point[0] for point in self.island))
        max_x = int(max(point[0] for point in self.island))
        min_y = int(min(point[1] for point in self.island))
        max_y = int(max(point[1] for point in self.island))

        for _ in range(self.config["game"]["generation_attempts"]):
            x = self.random.uniform(min_x, max_x)
            y = self.random.uniform(min_y, max_y)
            if self._point_in_polygon((x, y), self.island):
                return x, y

        return self._polygon_centroid(self.island)

    def _assign_voronoi_territories(self) -> None:
        for country in self.countries:
            territory = list(self.island)
            for other in self.countries:
                if country.id == other.id:
                    continue
                territory = self._clip_to_nearest_capital(territory, country, other)
                if not territory:
                    break
            country.territory = territory

    def _clip_to_nearest_capital(self, polygon: list[Point], country: Country, other: Country) -> list[Point]:
        if not polygon:
            return []

        clipped: list[Point] = []
        previous = polygon[-1]
        previous_inside = self._is_nearer_to_country(previous, country, other)

        for current in polygon:
            current_inside = self._is_nearer_to_country(current, country, other)
            if current_inside != previous_inside:
                clipped.append(self._bisector_intersection(previous, current, country, other))
            if current_inside:
                clipped.append(current)
            previous = current
            previous_inside = current_inside

        return clipped

    def _is_nearer_to_country(self, point: Point, country: Country, other: Country) -> bool:
        x, y = point
        own_distance = (x - country.x) ** 2 + (y - country.y) ** 2
        other_distance = (x - other.x) ** 2 + (y - other.y) ** 2
        return own_distance <= other_distance

    def _bisector_intersection(self, start: Point, end: Point, country: Country, other: Country) -> Point:
        sx, sy = start
        ex, ey = end
        dx = ex - sx
        dy = ey - sy
        ax = other.x - country.x
        ay = other.y - country.y
        midpoint_dot = (other.x**2 + other.y**2 - country.x**2 - country.y**2) / 2
        denominator = ax * dx + ay * dy
        if abs(denominator) < 0.000001:
            return end
        t = (midpoint_dot - ax * sx - ay * sy) / denominator
        t = max(0.0, min(1.0, t))
        return sx + dx * t, sy + dy * t

    def _point_in_polygon(self, point: Point, polygon: list[Point]) -> bool:
        x, y = point
        inside = False
        previous_x, previous_y = polygon[-1]

        for current_x, current_y in polygon:
            crosses = (current_y > y) != (previous_y > y)
            if crosses:
                intersection_x = (previous_x - current_x) * (y - current_y) / (previous_y - current_y) + current_x
                if x < intersection_x:
                    inside = not inside
            previous_x, previous_y = current_x, current_y

        return inside

    def _polygon_centroid(self, polygon: list[Point]) -> Point:
        if not polygon:
            return self.play_width / 2, self.play_height / 2
        return (
            sum(point[0] for point in polygon) / len(polygon),
            sum(point[1] for point in polygon) / len(polygon),
        )

    def _territory_sort_key(self, country: Country) -> float:
        center = self._polygon_centroid(self.island)
        return atan2(country.y - center[1], country.x - center[0])

    def _log(self, message: str) -> None:
        if self.logger is not None:
            self.logger(f"[world] {message}")
