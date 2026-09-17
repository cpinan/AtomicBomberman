# The dedicated Atomic Bomberman server.
#
# It draws nothing, loads no art, and needs no GPU — see scripts/net/server.gd.
# That is what lets it be this small: a headless Godot export and nothing else.
#
# NO GAME ART IS IN THIS IMAGE, and none can be. The asset pack is built from
# the user's own disc and is gitignored; the export preset excludes
# data/packs/* explicitly. The server only needs the simulation and the scheme,
# and it sends the scheme to clients as text.
FROM debian:bookworm-slim AS runtime

# Godot's headless export still links against these.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libfreetype6 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --system --create-home --shell /usr/sbin/nologin bomber
WORKDIR /srv

# Built by tools/build_server.sh, which runs the "Linux Server" export preset.
COPY --chown=bomber:bomber build/server/ab-server.x86_64 /srv/ab-server
COPY --chown=bomber:bomber server/schemes/ /srv/schemes/

RUN chmod +x /srv/ab-server
USER bomber

ENV AB_PORT=47600 \
    AB_SCHEME=/srv/schemes/basic.sch \
    AB_LEVEL=0 \
    AB_BOTS=0 \
    AB_WINS=0

EXPOSE 47600

# --dedicated is the mode that never opens a window. --headless keeps Godot
# from trying to find a display at all.
#
# AB_BOTS fills seats so that a server nobody has joined yet is still a game,
# and so the first person to arrive has something to play against — a bot gives
# up its seat when a human joins. AB_WINS overrides VALUELST resource 310's two
# wins per match. Both default to 0, meaning "leave it alone".
ENTRYPOINT ["/bin/sh", "-c", \
  "exec /srv/ab-server --headless -- --dedicated $AB_PORT --scheme $AB_SCHEME --level $AB_LEVEL \
   ${AB_BOTS:+--bots $AB_BOTS} ${AB_WINS:+--wins $AB_WINS}"]
