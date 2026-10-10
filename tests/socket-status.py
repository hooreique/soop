"""Check launcher socket ownership using real Linux processes and TCP sockets."""

import os
import subprocess
import sys
import tempfile

command = sys.argv[1:]
assert command, "pass the soop-grid command"

with tempfile.TemporaryDirectory(prefix="soop-socket-") as root:
    env = dict(
        os.environ,
        XDG_DATA_HOME=root,
        XDG_STATE_HOME=root,
        XDG_RUNTIME_DIR=root,
        SOOP_GRID_PAYLOAD_DIR=root,
        SOOP_GRID_SEED_VERSION="test",
    )
    prefix = root + "/soop/grid/wineprefix"

    def status(expected):
        result = subprocess.run(
            command + ["--status"], env=env, capture_output=True, text=True, timeout=10
        )
        assert result.returncode == expected, result.stdout + result.stderr
        return result.stdout

    code = (
        "import socket,sys,time; s=socket.socket(); "
        "s.bind((sys.argv[1],0)); s.listen(); "
        "print(s.getsockname()[1],flush=True); time.sleep(120)"
    )
    cases = [
        ("unrelated", prefix, "127.0.0.1", 1),
        ("./SOOPLiveLauncher.exe", prefix + "-other", "127.0.0.1", 1),
        ("./SOOPLiveLauncher.exe", prefix, "0.0.0.0", 1),
        ("./SOOPLiveLauncher.exe", prefix, "127.0.0.1", 0),
    ]
    for name, wineprefix, address, expected in cases:
        # argv[0] imitates the vendor executable, without needing Wine or a display.
        process = subprocess.Popen(
            [name, "-c", code, address],
            executable=sys.executable,
            env=dict(env, WINEPREFIX=wineprefix),
            stdout=subprocess.PIPE,
            text=True,
        )
        try:
            port = process.stdout.readline().strip()
            assert port, "listener did not start"
            output = status(expected)
            if expected == 0:
                assert port in output, output
            print(f"PASS: {name}, {wineprefix}, {address}: {output.strip()}")
        finally:
            process.terminate()
            process.wait(timeout=5)
        status(1)
