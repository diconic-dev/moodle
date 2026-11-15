# Moodle

<p align="center"><a href="https://moodle.org" target="_blank" title="Moodle Website">
  <img src="https://raw.githubusercontent.com/moodle/moodle/main/.github/moodlelogo.svg" alt="The Moodle Logo">
</a></p>

[Moodle][1] is the World's Open Source Learning Platform, widely used around the world by countless universities, schools, companies, and all manner of organisations and individuals.

Moodle is designed to allow educators, administrators and learners to create personalised learning environments with a single robust, secure and integrated system.

## Docker

This repository provides separate Docker Compose flows for development and
production. The application image contains PHP-FPM and Moodle; the production
web image contains nginx and the static Moodle assets. Database and uploaded
files are stored in named Docker volumes.

### Development

Create the local environment file and start the stack:

```bash
cp .env.example .env
# Edit .env and set MOODLE_DB_PASSWORD and MOODLE_DB_ROOT_PASSWORD.
docker compose up -d --build
```

Open [http://localhost:8080](http://localhost:8080). The development stack
builds the application locally and mounts the source tree into nginx, which
is convenient for development.

Check service status and logs with:

```bash
docker compose ps
docker compose logs -f app
```

### Production

Production pulls immutable release images from GitHub Container Registry; the
server does not need the source code or Dockerfile.

1. Copy the environment template and set production values:

   ```bash
   cp .env.example .env
   ```

   Set at least:

   ```env
   MOODLE_DB_PASSWORD=<strong-database-password>
   MOODLE_DB_ROOT_PASSWORD=<strong-root-password>
   MOODLE_WWWROOT=https://moodle.example.com
   MOODLE_IMAGE_TAG=5.3.1
   MOODLE_REVERSEPROXY=1
   MOODLE_SSLPROXY=1
   ```

2. If the GHCR images are private, authenticate on the server:

   ```bash
   echo "$CR_PAT" | docker login ghcr.io -u GITHUB_USERNAME --password-stdin
   ```

3. Pull and start the release:

   ```bash
   docker compose -f compose.production.yaml pull
   docker compose -f compose.production.yaml up -d
   ```

4. Verify the deployment:

   ```bash
   docker compose -f compose.production.yaml ps
   docker compose -f compose.production.yaml logs -f app
   ```

GitHub Actions builds and publishes the application image as
`ghcr.io/diconic-dev/moodle:<version>` and the nginx image as
`ghcr.io/diconic-dev/moodle:<version>-web`. Deploy a new release by changing
`MOODLE_IMAGE_TAG` and running `pull` followed by `up -d`.

Do not run `docker compose down -v` on production unless database and uploaded
file volumes have been backed up and are intentionally being removed.

## Documentation

- Read our [User documentation][3]
- Discover our [developer documentation][5]
- Take a look at our [demo site][4]

## Community

[moodle.org][1] is the central hub for the Moodle Community, with spaces for educators, administrators and developers to meet and work together.

You may also be interested in:

- attending a [Moodle Moot][6]
- our regular series of [developer meetings][7]
- the [Moodle User Association][8]

## Installation and hosting

Moodle is Free, and Open Source software. You can easily [download Moodle][9] and run it on your own web server, however you may prefer to work with one of our experienced [Moodle Partners][10].

Moodle also offers hosting through both [MoodleCloud][11], and our [partner network][10].

## License

Moodle is provided freely as open source software, under version 3 of the GNU General Public License. See our [license page][12] for more information.

[1]: https://moodle.org
[2]: https://moodle.com
[3]: https://docs.moodle.org/
[4]: https://sandbox.moodledemo.net/
[5]: https://moodledev.io
[6]: https://moodle.com/events/mootglobal/
[7]: https://moodledev.io/general/community/meetings
[8]: https://moodleassociation.org/
[9]: https://download.moodle.org
[10]: https://moodle.com/partners
[11]: https://moodle.com/cloud
[12]: https://moodledev.io/general/license
