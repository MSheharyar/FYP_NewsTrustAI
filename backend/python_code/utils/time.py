import re
from datetime import datetime, timezone
from typing import Any, List, Optional, Tuple

def extract_years(text: str) -> List[int]:
    years = re.findall(r"\b(19\d{2}|20\d{2})\b", text or "")
    return [int(y) for y in years]

def time_contradiction(text: str) -> Tuple[bool, str]:
    t = (text or "").strip()
    years = extract_years(t)

    if len(set(years)) >= 2:
        return True, f"Multiple different years detected: {sorted(set(years))}"

    m = re.search(r"\b(19\d{2}|20\d{2})\b.*\bin\b.*\b(19\d{2}|20\d{2})\b", t.lower())
    if m and m.group(1) != m.group(2):
        return True, f"Contradictory year phrase: {m.group(1)} ... in {m.group(2)}"

    return False, ""

def parse_dt(x: Any) -> Optional[datetime]:
    if not x:
        return None
    try:
        if isinstance(x, str) and x.endswith("Z"):
            x = x.replace("Z", "+00:00")
        dt = datetime.fromisoformat(x) if isinstance(x, str) else None
        if dt and dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None