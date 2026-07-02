import unittest

from game.actions import GameActions
from game.config import load_config
from game.world import PLAYER_OWNER, World


class WorldTests(unittest.TestCase):
    def make_world(self) -> World:
        config = load_config("config.json")
        config["game"]["random_seed"] = 7
        return World(config)

    def test_growth_adds_units_to_countries(self) -> None:
        world = self.make_world()
        occupied = [country for country in world.countries if country.owner is not None]
        before = [country.units for country in occupied]

        world.update(1.1)

        after = [country.units for country in occupied]
        self.assertEqual([value + 1 for value in before], after)

    def test_player_can_capture_country(self) -> None:
        world = self.make_world()
        source = world.countries[0]
        target = world.countries[1]
        source.owner = PLAYER_OWNER
        source.units = 100
        target.units = 1

        sent = world.send_units(source, target)
        self.assertTrue(sent)

        group = world.unit_groups[0]
        world._resolve_arrival(group, target)

        self.assertEqual(target.owner, PLAYER_OWNER)
        self.assertGreater(target.units, 0)

    def test_send_units_reduces_source_radius(self) -> None:
        world = self.make_world()
        source = world.countries[0]
        target = world.countries[1]
        source.owner = PLAYER_OWNER
        world._set_country_units(source, 30, "test")
        radius_before = source.radius

        world.send_units(source, target)

        self.assertLess(source.radius, radius_before)

    def test_send_units_reduces_generated_source_radius(self) -> None:
        world = self.make_world()
        source = world.countries[0]
        target = world.countries[1]
        radius_before = source.radius

        world.send_units(source, target)

        self.assertLess(source.radius, radius_before)

    def test_reinforcement_increases_target_radius(self) -> None:
        world = self.make_world()
        target = world.countries[0]
        world._set_country_units(target, 10, "test")
        radius_before = target.radius

        group = world.unit_groups
        self.assertEqual(group, [])
        world._resolve_arrival(
            type("Group", (), {"owner": target.owner, "units": 10})(),
            target,
        )

        self.assertGreater(target.radius, radius_before)

    def test_attack_reduces_target_radius_without_capture(self) -> None:
        world = self.make_world()
        target = world.countries[1]
        world._set_country_units(target, 30, "test")
        radius_before = target.radius

        world._resolve_arrival(
            type("Group", (), {"owner": PLAYER_OWNER, "units": 5})(),
            target,
        )

        self.assertLess(target.radius, radius_before)

    def test_winner_can_ignore_neutral_territories(self) -> None:
        world = self.make_world()
        for country in world.countries:
            if country.owner is not None:
                country.owner = PLAYER_OWNER

        self.assertIsNone(world.winner)
        for country in world.countries:
            country.owner = PLAYER_OWNER
        self.assertEqual(world.winner, PLAYER_OWNER)

    def test_player_defeated_when_no_player_capitals_remain(self) -> None:
        world = self.make_world()
        for country in world.countries:
            if country.owner == PLAYER_OWNER:
                country.owner = 1

        self.assertTrue(world.player_defeated)

    def test_config_creates_neutral_territories(self) -> None:
        world = self.make_world()
        neutral = [country for country in world.countries if country.owner is None]

        self.assertEqual(len(neutral), 3)
        self.assertTrue(all(country.units == 10 for country in neutral))

    def test_capitals_spawn_inside_island(self) -> None:
        world = self.make_world()

        self.assertTrue(all(world._point_in_polygon((country.x, country.y), world.island) for country in world.countries))

    def test_voronoi_territories_are_static_after_capture(self) -> None:
        world = self.make_world()
        target = world.countries[1]
        territory_before = list(target.territory)
        world._resolve_arrival(
            type("Group", (), {"owner": PLAYER_OWNER, "units": target.units + 5})(),
            target,
        )

        self.assertEqual(target.territory, territory_before)
        self.assertEqual(target.owner, PLAYER_OWNER)

    def test_voronoi_territories_are_not_empty(self) -> None:
        world = self.make_world()

        self.assertTrue(all(len(country.territory) >= 3 for country in world.countries))

    def test_actions_block_sending_while_paused(self) -> None:
        config = load_config("config.json")
        config["game"]["random_seed"] = 7
        actions = GameActions(config)
        source = actions.world.countries[0]
        target = actions.world.countries[1]

        actions.select_country(source.id)
        actions.toggle_pause()

        self.assertFalse(actions.send_selected_to(target.id))
        self.assertEqual(len(actions.world.unit_groups), 0)

    def test_drag_stream_targets_country_and_sends_multiple_groups(self) -> None:
        config = load_config("config.json")
        config["game"]["random_seed"] = 7
        actions = GameActions(config)
        source = actions.world.countries[0]
        target = actions.world.countries[1]
        actions.world._set_country_units(source, 30, "test")

        self.assertTrue(actions.start_drag(source.x, source.y))
        actions.update_drag(target.x, target.y)
        self.assertEqual(actions.drag_target_id, target.id)
        self.assertTrue(actions.finish_drag())

        actions.tick(0.0)
        actions.tick(config["game"]["send_stream_interval_seconds"])

        self.assertEqual(len(actions.world.unit_groups), 2)
        self.assertEqual(source.units, 28)

    def test_drag_stream_stops_at_one_unit(self) -> None:
        config = load_config("config.json")
        config["game"]["random_seed"] = 7
        actions = GameActions(config)
        source = actions.world.countries[0]
        target = actions.world.countries[1]
        actions.world._set_country_units(source, 2, "test")

        actions.start_drag(source.x, source.y)
        actions.update_drag(target.x, target.y)
        actions.finish_drag()
        actions.tick(0.0)
        actions.tick(config["game"]["send_stream_interval_seconds"])

        self.assertEqual(source.units, 1)
        self.assertEqual(actions.active_streams, [])

    def test_drag_chain_creates_multiple_sources_to_one_target(self) -> None:
        config = load_config("config.json")
        config["game"]["random_seed"] = 7
        actions = GameActions(config)
        source = actions.world.countries[0]
        relay = actions.world.countries[1]
        target = actions.world.countries[2]
        relay.owner = PLAYER_OWNER
        relay.color = source.color

        actions.start_drag(source.x, source.y)
        actions.update_drag(relay.x, relay.y)
        actions.update_drag(target.x, target.y)
        self.assertEqual(actions.drag_chain, [source.id, relay.id])
        self.assertTrue(actions.finish_drag())

        self.assertEqual(len(actions.active_streams), 2)
        self.assertEqual({stream["target_id"] for stream in actions.active_streams}, {target.id})

    def test_multiple_drag_streams_do_not_cancel_existing_streams(self) -> None:
        config = load_config("config.json")
        config["game"]["random_seed"] = 7
        actions = GameActions(config)
        source = actions.world.countries[0]
        target_a = actions.world.countries[1]
        target_b = actions.world.countries[2]

        actions.start_drag(source.x, source.y)
        actions.update_drag(target_a.x, target_a.y)
        actions.finish_drag()
        actions.start_drag(source.x, source.y)
        actions.update_drag(target_b.x, target_b.y)
        actions.finish_drag()

        self.assertEqual(len(actions.active_streams), 2)

    def test_aggressive_ai_starts_stream_to_weak_enemy(self) -> None:
        config = load_config("config.json")
        config["game"]["random_seed"] = 7
        config["ai"]["mode"] = "aggressive"
        world = World(config)
        source = world.countries[1]
        source.units = 50
        weak = world.countries[2]
        weak.units = 1

        world._run_ai_turn()

        self.assertEqual(world.ai_streams[0]["target_id"], weak.id)

    def test_ai_random_turn_starts_stream(self) -> None:
        world = self.make_world()

        sent = world._run_ai_turn()

        self.assertTrue(sent)
        self.assertEqual(len(world.ai_streams), 1)

    def test_send_units_sends_single_unit_groups(self) -> None:
        world = self.make_world()
        source = world.countries[0]
        target = world.countries[1]
        before = source.units

        self.assertTrue(world.send_units(source, target))

        self.assertEqual(source.units, before - 1)
        self.assertEqual(world.unit_groups[-1].units, 1)


if __name__ == "__main__":
    unittest.main()
