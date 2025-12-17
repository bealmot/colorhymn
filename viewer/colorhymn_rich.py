#!/usr/bin/env python3
"""
Colorhymn Rich Viewer - Simple terminal viewer using Rich.
For quick viewing without Textual. Supports piping and less.
"""

import json
import subprocess
import sys
from pathlib import Path

try:
    from rich.console import Console
    from rich.text import Text
except ImportError:
    # Fallback: output raw ANSI from Elixir
    print("Rich not installed. Using raw ANSI output.", file=sys.stderr)
    RICH_AVAILABLE = False
else:
    RICH_AVAILABLE = True


def colorize_file(file_path: str) -> dict:
    """Call Colorhymn and get JSON output."""
    colorhymn_dir = Path(__file__).parent.parent

    result = subprocess.run(
        ["mix", "colorize", file_path],
        capture_output=True,
        text=True,
        cwd=str(colorhymn_dir),
        timeout=30
    )

    # Find JSON in output (skip compile warnings)
    json_start = result.stdout.find('{')
    if json_start == -1:
        raise ValueError(f"No JSON output: {result.stderr}")

    return json.loads(result.stdout[json_start:])


def render_rich(data: dict, console: Console) -> None:
    """Render with Rich."""
    meta = data["metadata"]

    # Header
    header = Text()
    header.append(f"━━━ {meta['filename']} ", style="bold")
    header.append(f"│ {meta['line_count']} lines ", style="dim")
    header.append(f"│ temp: ")

    temp_style = {
        "cool": "cyan", "neutral": "white", "elevated": "yellow",
        "uneasy": "yellow", "troubled": "orange1", "warm": "orange1",
        "critical": "red"
    }.get(meta["temperature"], "white")
    header.append(meta["temperature"], style=temp_style)

    header.append(f" │ mood: ")
    mood_style = temp_style  # Same mapping
    header.append(meta["mood"], style=mood_style)
    header.append(" ━━━")

    console.print(header)
    console.print()

    # Lines
    for i, line_tokens in enumerate(data["lines"], 1):
        text = Text()
        text.append(f"{i:5d} ", style="dim")

        for token in line_tokens:
            _, value, color = token
            text.append(value, style=color)

        console.print(text)


def render_ansi(data: dict) -> None:
    """Render with raw ANSI (fallback)."""
    meta = data["metadata"]
    print(f"━━━ {meta['filename']} │ {meta['line_count']} lines │ temp: {meta['temperature']} │ mood: {meta['mood']} ━━━\n")

    for i, line_tokens in enumerate(data["lines"], 1):
        parts = [f"\033[2m{i:5d}\033[0m "]
        for token in line_tokens:
            _, value, color = token
            # Convert hex to simple ANSI (approximate)
            parts.append(f"\033[38;2;{int(color[1:3], 16)};{int(color[3:5], 16)};{int(color[5:7], 16)}m{value}\033[0m")
        print("".join(parts))


def main():
    if len(sys.argv) < 2:
        print("Usage: colorhymn_rich.py <logfile>", file=sys.stderr)
        print("       cat logfile | colorhymn_rich.py --stdin", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]

    try:
        data = colorize_file(file_path)

        if RICH_AVAILABLE:
            console = Console(force_terminal=True)
            render_rich(data, console)
        else:
            render_ansi(data)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
