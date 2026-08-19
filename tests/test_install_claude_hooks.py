from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "scripts" / "install_claude_hooks.py"
SPEC = importlib.util.spec_from_file_location("install_claude_hooks", SCRIPT_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InstallClaudeHooksTests(unittest.TestCase):
    def test_install_is_idempotent_and_preserves_other_hooks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings_path = root / "settings.json"
            script_path = root / "draft_inbox.py"
            script_path.write_text("# test\n", encoding="utf-8")
            settings_path.write_text(
                json.dumps(
                    {
                        "theme": "dark",
                        "hooks": {
                            "Stop": [
                                {
                                    "hooks": [
                                        {
                                            "type": "command",
                                            "command": "echo existing",
                                        }
                                    ]
                                }
                            ]
                        },
                    }
                ),
                encoding="utf-8",
            )

            MODULE.install_hooks(settings_path, script_path)
            MODULE.install_hooks(settings_path, script_path)

            payload = json.loads(settings_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["theme"], "dark")
            self.assertEqual(len(payload["hooks"]["Stop"]), 2)
            self.assertEqual(len(payload["hooks"]["SessionStart"]), 1)
            self.assertEqual(len(payload["hooks"]["UserPromptSubmit"]), 1)
            command = payload["hooks"]["Stop"][1]["hooks"][0]["command"]
            self.assertIn(str(script_path), command)
            self.assertTrue(command.endswith(" claude-event"))


if __name__ == "__main__":
    unittest.main()
