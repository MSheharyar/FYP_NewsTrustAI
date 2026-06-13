import importlib
import pytest


def test_auth_disabled_requires_explicit_dev_flag(monkeypatch):
    """REQUIRE_AUTH=false alone is not enough; APP_ENV must be 'local'/'dev'."""
    monkeypatch.setenv("REQUIRE_AUTH", "false")
    monkeypatch.setenv("APP_ENV", "production")
    import middleware.auth as auth
    importlib.reload(auth)
    with pytest.raises(RuntimeError):
        auth.assert_auth_config_is_safe()


def test_auth_disabled_ok_in_local(monkeypatch):
    monkeypatch.setenv("REQUIRE_AUTH", "false")
    monkeypatch.setenv("APP_ENV", "local")
    import middleware.auth as auth
    importlib.reload(auth)
    auth.assert_auth_config_is_safe()  # must not raise
