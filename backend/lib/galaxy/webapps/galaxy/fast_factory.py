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

    The key belongs to the configured ADMIN user (``admin_users``) — never to
    "user_id=1" by assumption. In a BioMate deployment user 1 is whichever
    BioMate user was provisioned first (on dev: the E2E fixture). The old code
    soft-deleted all of user 1's other keys on every boot, so that real user's
    own key was revoked by every Galaxy restart and every chat workflow request
    then failed with 401 "Provided API key is not valid" until their next login
    (dev 2026-11-03: key created 18:31:14, revoked by the 18:33:38 boot; 250+
    revoked fixture keys since September). Only the admin user's own keys are
    ever touched now.

    No-op if GALAXY_API_KEY is unset, if it IS the master_api_key (Galaxy
    authenticates the master key as the bootstrap admin without any api_keys
    row), or if no configured admin user exists.
    """
    import os as _os
    import logging as _logging
    _log = _logging.getLogger(__name__)
    key = _os.environ.get("GALAXY_API_KEY", "").strip()
    if not key or len(key) != 32:
        return
    master = (getattr(gx_app.config, "master_api_key", None) or "").strip()
    if master and key == master:
        _log.info("[boot-seed] GALAXY_API_KEY is the master_api_key — authenticated as the bootstrap admin; "
                  "nothing to seed, no user's keys touched")
        return
    try:
        from sqlalchemy import select as _select, update as _update
        session = gx_app.model.context
        APIKeys = gx_app.model.APIKeys
        User = gx_app.model.User
        admin_emails = list(getattr(gx_app.config, "admin_users_list", None) or [])
        admin = (session.scalars(_select(User).where(User.email.in_(admin_emails))).first()
                 if admin_emails else None)
        if not admin:
            _log.warning("[boot-seed] no configured admin user (%s) exists; skipping key seed — "
                         "no other user's keys are touched", ", ".join(admin_emails) or "admin_users unset")
            return
        # by_api_key in managers/users.py rejects with "expired" if the
        # provided key isn't the NEWEST non-deleted key for the user. Make the
        # env key the admin's sole active key — the ADMIN's keys only.
        session.execute(
            _update(APIKeys)
            .where(APIKeys.user_id == admin.id)
            .where(APIKeys.key != key)
            .where(APIKeys.deleted == False)  # noqa: E712  (SQLAlchemy column compare)
            .values(deleted=True)
        )
        existing = session.scalars(_select(APIKeys).filter_by(key=key)).first()
        if existing:
            existing.deleted = False
            existing.user_id = admin.id  # a legacy row may sit on another user (e.g. user 1)
            session.commit()
            _log.info("[boot-seed] GALAXY_API_KEY is the sole active key for admin user %s (id=%s)", admin.id, existing.id)
            return
        new_key = APIKeys()
        new_key.user_id = admin.id
        new_key.key = key
        session.add(new_key)
        session.commit()
        _log.info("[boot-seed] GALAXY_API_KEY seeded as sole active key for admin user %s", admin.id)
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
