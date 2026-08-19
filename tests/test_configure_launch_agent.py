import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "configure_launch_agent.sh"
TEMPLATE = ROOT / "macos-app" / "AppResources" / "com.zhangshuo.codex-draft-inbox.plist"


class ConfigureLaunchAgentTests(unittest.TestCase):
    def test_legacy_launch_agent_is_moved_out_of_launch_agents(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            app = home / "Applications" / "Codex Draft Inbox.app"
            app.mkdir(parents=True)
            launch_agent = home / "Library" / "LaunchAgents" / "com.zhangshuo.codex-draft-inbox.plist"
            launch_agent.parent.mkdir(parents=True)
            launch_agent.write_bytes(TEMPLATE.read_bytes())
            environment = {
                **os.environ,
                "HOME": str(home),
                "CODEX_DRAFT_INBOX_SKIP_SYSTEM_COMMANDS": "1",
            }

            subprocess.run(
                [str(SCRIPT), str(app)],
                check=True,
                env=environment,
            )
            self.assertFalse(launch_agent.exists())
            backup = home / ".codex" / "draft-inbox" / "legacy-launch-agent.plist.bak"
            with backup.open("rb") as handle:
                configuration = plistlib.load(handle)
            self.assertEqual(configuration["Label"], "com.zhangshuo.codex-draft-inbox")


if __name__ == "__main__":
    unittest.main()
