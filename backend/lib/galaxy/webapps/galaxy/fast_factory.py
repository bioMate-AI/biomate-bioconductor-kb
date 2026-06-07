"""Module containing factory class for building uvicorn app for Galaxy.

Information on uvicorn, its various settings, and how to invoke it can
be found at https://www.uvicorn.org/.

Galaxy can be launched with uvicorn using the following invocation:

::

    uvicorn --app-dir lib --factory galaxy.webapps.galaxy.fast_factory:factory

Use the environment variable ``GALAXY_CONFIG_FILE`` to specify a Galaxy
configuration file. Galaxy configuration can be loading from a YAML
or an .ini file (reads app:main currently but can be overridden with
GALAXY_CONFIG_SECTION).

::

    GALAXY_CONFIG_FILE=config/galaxy.yml uvicorn --app-dir lib --factory galaxy.webapps.galaxy.fast_factory:factory

.. note::

    Information on additional ways to configure uvicorn can be found at
    https://www.uvicorn.org/.

.. warning::

    If an ini file is supplied via GALAXY_CONFIG_FILE, the server properties
    such as host and port are not read from the file like older forms of
    configuring Galaxy.

`Gunicorn <https://docs.gunicorn.org/en/stable/index.html>`__ is a server with
more complex management options.

This factory function can be executed as a uvicorn worker managed with gunicorn
with the following command-line.

::

    gunicorn 'galaxy.webapps.galaxy.fast_factory:factory()' --env GALAXY_CONFIG_FILE=config/galaxy.ini --pythonpath lib -w 4 -k uvicorn.workers.UvicornWorker --config lib/galaxy/web_stack/gunicorn_config.py

"""

from galaxy.main_config import (
    DEFAULT_CONFIG_SECTION,
    WebappConfigResolver,
    WebappSetupProps,
)
from galaxy.webapps.galaxy.buildapp import app_pair
from .fast_app import initialize_fast_app


def _seed_api_key_from_env(gx_app) -> None:
    """Ensure the api_keys row for $GALAXY_API_KEY exists for the admin user.

    The Node frontend forwards x-api-key=$GALAXY_API_KEY for every
    backend call. If the key isn't in api_keys table the call gets 401
    and every chat → workflow_generation request fails with
    'Workflow generation is currently unavailable — auth/permission
    boundary in a dependent service'. This used to be fixed manually
    after every container restart; this hook makes it idempotent at boot.

    No-op if GALAXY_API_KEY env var is unset, no user_id=1 exists, or
    the row is already present.
    """
    import os as _os
    import logging as _logging
    _log = _logging.getLogger(__name__)
    key = _os.environ.get("GALAXY_API_KEY", "").strip()
    if not key or len(key) != 32:
        return
    try:
        from sqlalchemy import select as _select, update as _update
        session = gx_app.model.context
        APIKeys = gx_app.model.APIKeys
        User = gx_app.model.User
        admin = session.scalars(_select(User).filter_by(id=1)).first()
        if not admin:
            _log.warning("[boot-seed] no user_id=1; skipping key seed")
            return
        # by_api_key in managers/users.py rejects with "expired" if the
        # provided key isn't the NEWEST non-deleted key for the user.
        # Soft-delete every other user_id=1 key so the env key is the sole
        # active one. Idempotent: re-runs delete nothing new.
        session.execute(
            _update(APIKeys)
            .where(APIKeys.user_id == 1)
            .where(APIKeys.key != key)
            .where(APIKeys.deleted == False)  # noqa: E712  (SQLAlchemy column compare)
            .values(deleted=True)
        )
        existing = session.scalars(_select(APIKeys).filter_by(key=key)).first()
        if existing:
            if existing.deleted:
                existing.deleted = False
            session.commit()
            _log.info("[boot-seed] GALAXY_API_KEY restored as sole active key for user_id=1 (id=%s)", existing.id)
            return
        new_key = APIKeys()
        new_key.user_id = 1
        new_key.key = key
        session.add(new_key)
        session.commit()
        _log.info("[boot-seed] GALAXY_API_KEY seeded as sole active key for user_id=1 "
                  "(prior keys soft-deleted to satisfy by_api_key's newest-key check)")
    except Exception as _exc:
        _log.warning("[boot-seed] could not seed GALAXY_API_KEY: %s", _exc)


def factory():
    props = WebappSetupProps(
        app_name="galaxy",
        default_section_name=DEFAULT_CONFIG_SECTION,
        env_config_file="GALAXY_CONFIG_FILE",
        env_config_section="GALAXY_CONFIG_SECTION",
        check_galaxy_root=True,
    )
    config_provider = WebappConfigResolver(props)
    config = config_provider.resolve_config()
    gx_wsgi_webapp, gx_app = app_pair(
        global_conf=config.global_conf, load_app_kwds=config.load_app_kwds, wsgi_preflight=config.wsgi_preflight
    )
    _seed_api_key_from_env(gx_app)
    return initialize_fast_app(gx_wsgi_webapp, gx_app)
