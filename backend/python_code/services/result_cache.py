import re
import time
from collections import OrderedDict


def _normalize(text):
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", "", text.lower())).strip()


class ResultCache:
    def __init__(self, maxsize=512, ttl_seconds=21600):  # 6h default
        self.maxsize = maxsize
        self.ttl = ttl_seconds
        self._store = OrderedDict()  # key -> (timestamp, value)

    def get(self, text):
        key = _normalize(text)
        item = self._store.get(key)
        if item is None:
            return None
        ts, value = item
        if time.time() - ts > self.ttl:
            self._store.pop(key, None)
            return None
        self._store.move_to_end(key)
        return value

    def set(self, text, value):
        key = _normalize(text)
        self._store[key] = (time.time(), value)
        self._store.move_to_end(key)
        while len(self._store) > self.maxsize:
            self._store.popitem(last=False)
