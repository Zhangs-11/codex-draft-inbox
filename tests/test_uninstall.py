from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "uninstall.sh"


class UninstallTests(unittest.TestCase):
    def test_uninstall_preserves_data_and_other_claude_hooks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            app = home / "Applications" / "Codex Draft Inbox.app"
            launch_agent = home / "Library" / "LaunchAgents" / "com.zhangshuo.codex-draft-inbox.plist"
            state = home / ".codex" / "draft-inbox" / "pending.json"
            settings = home / ".claude" / "settings.json"
            app.mkdir(parents=True)
            launch_agent.parent.mkdir(parents=True)
            launch_agent.write_text("test", encoding="utf-8")
            state.parent.mkdir(parents=True)
            state.write_text("{}", encoding="utf-8")
            settings.parent.mkdir(parents=True)
            settings.write_text(
                json.dumps(
                    {
                        "hooks": {
                            "Stop": [
                                {"hooks": [{"command": "echo keep"}]},
                                {"hooks": [{"command": "python3 /tmp/draft_inbox.py claude-event"}]},
                            ]
                        }
                    }
                ),
                encoding="utf-8",
            )
            environment = {
                **os.environ,
                "HOME": str(home),
                "CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS": "1",
            }

            subprocess.run([str(SCRIPT)], check=True, env=environment, capture_output=True)

            self.assertFalse(app.exists())
            self.assertFalse(launch_agent.exists())
            self.assertTrue(state.exists())
            payload = json.loads(settings.read_text(encoding="utf-8"))
            self.assertEqual(payload["hooks"]["Stop"], [{"hooks": [{"command": "echo keep"}]}])

    def test_purge_data_requires_explicit_flag(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            state_root = home / ".codex" / "draft-inbox"
            state_root.mkdir(parents=True)
            (state_root / "pending.json").write_text("{}", encoding="utf-8")
            environment = {
                **os.environ,
                "HOME": str(home),
                "CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS": "1",
            }

            subprocess.run(
                [str(SCRIPT), "--purge-data"],
                check=True,
                env=environment,
                capture_output=True,
            )

            self.assertFalse(state_root.exists())


if __name__ == "__main__":
    unittest.main()
