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
    def _write_executable(self, path: Path, body: str) -> None:
        path.write_text("#!/bin/sh\nset -eu\n" + body, encoding="utf-8")
        path.chmod(0o755)

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

    def test_launch_retries_after_old_process_exits_and_verifies_new_process(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            app = home / "Applications" / "Codex Draft Inbox.app"
            app.mkdir(parents=True)
            state = root / "process-state"
            attempts = root / "open-attempts"
            state.write_text("old", encoding="utf-8")
            attempts.write_text("0", encoding="utf-8")

            pgrep = root / "pgrep"
            pkill = root / "pkill"
            kill = root / "kill"
            open_app = root / "open"
            sleep = root / "sleep"
            self._write_executable(
                pgrep,
                f'case "$(cat {state!s})" in old) echo 101;; launched) echo 202;; esac\n',
            )
            self._write_executable(pkill, f'printf stopped > {state!s}\n')
            self._write_executable(
                kill,
                f'[ "$(cat {state!s})" = old ]\n',
            )
            self._write_executable(
                open_app,
                f'count=$(cat {attempts!s}); count=$((count + 1)); printf %s "$count" > {attempts!s}\n'
                f'if [ "$count" -lt 2 ]; then exit 1; fi\nprintf launched > {state!s}\n',
            )
            self._write_executable(sleep, ":\n")
            environment = {
                **os.environ,
                "HOME": str(home),
                "CODEX_DRAFT_INBOX_PGREP": str(pgrep),
                "CODEX_DRAFT_INBOX_PKILL": str(pkill),
                "CODEX_DRAFT_INBOX_KILL": str(kill),
                "CODEX_DRAFT_INBOX_OPEN": str(open_app),
                "CODEX_DRAFT_INBOX_SLEEP": str(sleep),
            }

            subprocess.run([str(SCRIPT), str(app)], check=True, env=environment)

            self.assertEqual(attempts.read_text(encoding="utf-8"), "2")
            self.assertEqual(state.read_text(encoding="utf-8"), "launched")

    def test_launch_failure_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            app = home / "Applications" / "Codex Draft Inbox.app"
            app.mkdir(parents=True)
            failing = root / "failing"
            sleep = root / "sleep"
            self._write_executable(failing, "exit 1\n")
            self._write_executable(sleep, ":\n")
            environment = {
                **os.environ,
                "HOME": str(home),
                "CODEX_DRAFT_INBOX_PGREP": str(failing),
                "CODEX_DRAFT_INBOX_PKILL": str(failing),
                "CODEX_DRAFT_INBOX_KILL": str(failing),
                "CODEX_DRAFT_INBOX_OPEN": str(failing),
                "CODEX_DRAFT_INBOX_SLEEP": str(sleep),
            }

            result = subprocess.run([str(SCRIPT), str(app)], check=False, env=environment)

            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
