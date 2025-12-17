#!/usr/bin/env python3
"""
Colorhymn Viewer - Textual TUI for colorized log viewing.
Optimized for: copy/paste, high density, small text.
"""

import json
import subprocess
import sys
from pathlib import Path

from textual.app import App, ComposeResult
from textual.widgets import Static, Header, Footer, Input
from textual.containers import ScrollableContainer, Vertical
from textual.binding import Binding
from rich.text import Text


class LogLine(Static):
    """A single log line with selectable, colorized text."""

    DEFAULT_CSS = """
    LogLine {
        height: auto;
        width: 100%;
        padding: 0;
        margin: 0;
    }
    """

    def __init__(self, tokens: list, line_num: int):
        self.tokens = tokens
        self.line_num = line_num
        super().__init__()

    def compose(self) -> ComposeResult:
        text = Text()
        for token in self.tokens:
            token_type, value, color = token
            text.append(value, style=color)

        # Add line number prefix
        prefix = Text(f"{self.line_num:5d} ", style="dim")
        yield Static(prefix + text, markup=False)


class LogViewer(ScrollableContainer):
    """Scrollable container for log lines."""

    DEFAULT_CSS = """
    LogViewer {
        height: 100%;
        width: 100%;
        scrollbar-gutter: stable;
    }
    """


class ColorhymnApp(App):
    """Main Colorhymn TUI application."""

    CSS = """
    Screen {
        background: $surface;
    }

    Header {
        height: 1;
        dock: top;
    }

    Footer {
        height: 1;
        dock: bottom;
    }

    #info-bar {
        height: 1;
        dock: top;
        background: $primary-background;
        color: $text-muted;
        padding: 0 1;
    }

    #log-container {
        height: 100%;
    }

    Static {
        height: auto;
        padding: 0;
        margin: 0;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("g", "scroll_top", "Top"),
        Binding("G", "scroll_bottom", "Bottom"),
        Binding("/", "search", "Search"),
        Binding("j", "scroll_down", "Down"),
        Binding("k", "scroll_up", "Up"),
        Binding("ctrl+d", "page_down", "Page Down"),
        Binding("ctrl+u", "page_up", "Page Up"),
    ]

    def __init__(self, file_path: str):
        super().__init__()
        self.file_path = file_path
        self.data = None
        self.title = f"Colorhymn - {Path(file_path).name}"

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(id="info-bar")
        yield LogViewer(id="log-container")
        yield Footer()

    def on_mount(self) -> None:
        self.load_file()

    def load_file(self) -> None:
        """Load and colorize file via Colorhymn."""
        try:
            # Call mix colorize
            result = subprocess.run(
                ["mix", "colorize", self.file_path],
                capture_output=True,
                text=True,
                cwd=str(Path(__file__).parent.parent),
                timeout=30
            )

            if result.returncode != 0:
                self.notify(f"Error: {result.stderr}", severity="error")
                return

            # Parse JSON (skip any compile warnings)
            json_start = result.stdout.find('{')
            if json_start == -1:
                self.notify("No JSON output from colorhymn", severity="error")
                return

            self.data = json.loads(result.stdout[json_start:])
            self.render_log()

        except subprocess.TimeoutExpired:
            self.notify("Colorhymn timed out", severity="error")
        except json.JSONDecodeError as e:
            self.notify(f"JSON parse error: {e}", severity="error")
        except Exception as e:
            self.notify(f"Error: {e}", severity="error")

    def render_log(self) -> None:
        """Render colorized log lines."""
        if not self.data:
            return

        meta = self.data["metadata"]

        # Update info bar
        info_bar = self.query_one("#info-bar", Static)
        info_text = Text()
        info_text.append(f" {meta['filename']} ", style="bold")
        info_text.append(f"│ {meta['line_count']} lines ", style="dim")
        info_text.append(f"│ temp: ", style="dim")

        # Color-code temperature
        temp_colors = {
            "cool": "cyan",
            "neutral": "white",
            "elevated": "yellow",
            "uneasy": "yellow",
            "troubled": "orange1",
            "warm": "orange1",
            "critical": "red"
        }
        temp_color = temp_colors.get(meta["temperature"], "white")
        info_text.append(meta["temperature"], style=temp_color)

        info_text.append(f" │ mood: ", style="dim")
        mood_color = temp_colors.get(meta["mood"], "white")
        info_text.append(meta["mood"], style=mood_color)

        info_bar.update(info_text)

        # Render lines
        container = self.query_one("#log-container", LogViewer)

        for i, line_tokens in enumerate(self.data["lines"], 1):
            if line_tokens:  # Skip empty token lists
                text = Text()
                text.append(f"{i:5d} ", style="dim")
                for token in line_tokens:
                    token_type, value, color = token
                    text.append(value, style=color)
                container.mount(Static(text, markup=False))
            else:
                # Empty line
                container.mount(Static(Text(f"{i:5d} ", style="dim"), markup=False))

    def action_scroll_top(self) -> None:
        container = self.query_one("#log-container")
        container.scroll_home()

    def action_scroll_bottom(self) -> None:
        container = self.query_one("#log-container")
        container.scroll_end()

    def action_scroll_down(self) -> None:
        container = self.query_one("#log-container")
        container.scroll_relative(y=1)

    def action_scroll_up(self) -> None:
        container = self.query_one("#log-container")
        container.scroll_relative(y=-1)

    def action_page_down(self) -> None:
        container = self.query_one("#log-container")
        container.scroll_page_down()

    def action_page_up(self) -> None:
        container = self.query_one("#log-container")
        container.scroll_page_up()

    def action_search(self) -> None:
        self.notify("Search not yet implemented", severity="warning")


def main():
    if len(sys.argv) < 2:
        print("Usage: colorhymn_viewer.py <logfile>", file=sys.stderr)
        sys.exit(1)

    app = ColorhymnApp(sys.argv[1])
    app.run()


if __name__ == "__main__":
    main()
