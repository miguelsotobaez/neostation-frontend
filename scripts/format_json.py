#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def format_file(json_file: Path) -> bool:
    original = json_file.read_text(encoding="utf-8")
    try:
        data = json.loads(original)
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON in {json_file.name}: {e}")
        return "error"

    formatted = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if original != formatted:
        json_file.write_text(formatted, encoding="utf-8")
        print(f"  formatted: {json_file.name}")
        return "changed"
    return "ok"


def main():
    systems_dir = Path(__file__).parent / "assets/systems"
    files = sorted(systems_dir.glob("*.json"))

    changed = 0
    errors = 0
    for json_file in files:
        result = format_file(json_file)
        if result == "changed":
            changed += 1
        elif result == "error":
            errors += 1

    print(f"\n{changed}/{len(files)} files reformatted.")
    if errors:
        print(f"{errors} file(s) with errors.")
        sys.exit(1)


if __name__ == "__main__":
    main()
