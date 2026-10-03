# Schemes for the dedicated server

Put `.SCH` files here from **your own copy** of Atomic Bomberman (the disc's
`SCHEMES` folder), then name one with `AB_SCHEME` — for example
`AB_SCHEME=/srv/schemes/BASIC.SCH` in `docker-compose.yml`. The image copies
this folder to `/srv/schemes/`.

None ship with the repository: the disc's schemes are the original's data,
not this project's, and `.gitignore` keeps any you add here out of git.
Without one the server plays the port's built-in pillar grid.
