"""Ulauncher extension: file search through GNOME's tracker index (what the Files app and the overview search use)."""
import os
import shutil
import subprocess
from urllib.parse import unquote, urlparse

from ulauncher.api.client.EventListener import EventListener
from ulauncher.api.client.Extension import Extension
from ulauncher.api.shared.action.OpenAction import OpenAction
from ulauncher.api.shared.action.RenderResultListAction import RenderResultListAction
from ulauncher.api.shared.event import KeywordQueryEvent
from ulauncher.api.shared.item.ExtensionResultItem import ExtensionResultItem

HOME = os.path.expanduser("~")


def tracker_cmd():
    for name in ("tracker3", "tracker"):
        if shutil.which(name):
            return name
    return None


def search_files(term, limit):
    cmd = tracker_cmd()
    if not cmd or not term.strip():
        return []
    try:
        out = subprocess.run([cmd, "search", "--files", "--disable-color", "--limit", str(limit), term],
                             capture_output=True, text=True, timeout=5).stdout
    except (subprocess.SubprocessError, OSError):
        return []
    paths = []
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("file://"):
            path = unquote(urlparse(line).path)
            if os.path.exists(path):
                paths.append(path)
    return paths


def pretty_dir(path):
    d = os.path.dirname(path)
    return "~" + d[len(HOME):] if d.startswith(HOME) else d


class FilesExtension(Extension):
    def __init__(self):
        super().__init__()
        self.subscribe(KeywordQueryEvent, QueryListener())


class QueryListener(EventListener):
    def on_event(self, event, extension):
        term = (event.get_argument() or "").strip()
        try:
            limit = max(1, min(int(extension.preferences.get("limit", "12")), 50))
        except ValueError:
            limit = 12
        icon = "images/icon.png"
        if not term:
            return RenderResultListAction([ExtensionResultItem(
                icon=icon, name="Search files", description="Type part of a file name", on_enter=None)])
        if not tracker_cmd():
            return RenderResultListAction([ExtensionResultItem(
                icon=icon, name="File index not available", description="Install the 'tracker' package", on_enter=None)])
        items = []
        for path in search_files(term, limit):
            items.append(ExtensionResultItem(icon=icon, name=os.path.basename(path), description=pretty_dir(path),
                                             on_enter=OpenAction(path)))
        if not items:
            items.append(ExtensionResultItem(icon=icon, name="No files match '%s'" % term,
                                             description="Indexed folders: Desktop, Documents, Downloads, Music, Pictures, Videos",
                                             on_enter=None))
        return RenderResultListAction(items)


if __name__ == "__main__":
    FilesExtension().run()
