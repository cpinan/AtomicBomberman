# The room-code lookup directory. See directory/README.md.
#
# No game logic, no game traffic, no persistence beyond an in-memory map —
# this is the whole reason it can be this small.
FROM node:22-alpine

RUN addgroup -S directory && adduser -S directory -G directory
WORKDIR /srv

COPY package.json server.js ./
USER directory

ENV PORT=8420
EXPOSE 8420

CMD ["node", "server.js"]
