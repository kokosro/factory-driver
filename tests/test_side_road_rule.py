"""ROAD-6 generator boundaries; run with python3 tests/test_side_road_rule.py."""
import copy
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/world"))
from skeleton import polyline_near_junctions, widen_side_tracks


class SideRoadRuleTest(unittest.TestCase):
    def test_whole_chord_and_boundary(self):
        disks = [{"x": 0.0, "z": 0.0}, {"x": 600.0, "z": 0.0}]
        self.assertTrue(polyline_near_junctions([[0, 0], [250, 0]], disks))
        self.assertFalse(polyline_near_junctions([[0, 0], [250.001, 0]], disks))
        # Endpoints individually near junctions, but the middle leaves both disks.
        self.assertFalse(polyline_near_junctions([[0, 0], [600, 0]], disks))
        disks[1]["x"] = 400.0
        self.assertTrue(polyline_near_junctions([[0, 0], [400, 0]], disks))
        self.assertFalse(polyline_near_junctions([[900, 0], [900, 0]], disks))

    def test_selection_and_exclusions(self):
        def segment(sid, points, cls="track", width=3.0):
            return dict(id=sid, points=points, **{"class": cls}, width_m=width, width_source="class")
        skeleton = {"loops": [{"segments": ["loop"]}],
                    "junctions": [{"x": 0, "z": 0, "segments": ["loop", "endpoint"]}],
                    "segments": [segment("loop", [[0, 0], [10, 0]]),
                                 segment("endpoint", [[0, 0], [1000, 0]]),
                                 segment("314755146-2", [[900, 0], [1000, 0]]),
                                 segment("near", [[0, 0], [200, 0]]),
                                 segment("far", [[800, 0], [900, 0]]),
                                 segment("uncovered", [[0, 0], [200, 0]]),
                                 segment("service", [[0, 0], [200, 0]], cls="service"),
                                 segment("wide", [[0, 0], [200, 0]], width=5.0)]}
        coverage = {"segments": [{"id": s["id"], "covered": s["id"] != "uncovered"} for s in skeleton["segments"]]}
        original = copy.deepcopy(skeleton)
        reasons = widen_side_tracks(skeleton, coverage)
        self.assertEqual(reasons, {"endpoint": ["endpoint"], "314755146-2": ["mandatory"], "near": ["proximity"]})
        for before, after in zip(original["segments"], skeleton["segments"]):
            if after["id"] in reasons:
                self.assertEqual(after["width_m"], 5.0)
                self.assertEqual(after["width_source"], "road6")
            else:
                self.assertEqual(before, after)
        repeat = copy.deepcopy(original)
        self.assertEqual(widen_side_tracks(repeat, coverage), reasons)
        self.assertEqual(repeat, skeleton)


if __name__ == "__main__":
    unittest.main()
